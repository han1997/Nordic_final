import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/sorting.dart';
import 'package:nordic/data/subsonic_payload.dart';
import 'package:nordic/data/subsonic_repository.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 状态层的两类事:
///   1. 写操作**发对了没有、本地快照跟着变没有**;
///   2. 加载失败**是哪一种失败** —— 界面据此决定说什么话(去改密码 / 去下载管理)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  /// 按端点回不同载荷的假 Dio,顺带记下每个请求的完整 Uri。
  ///
  /// [byQueryType] 给**同一个端点不同参数**用:`getAlbumList2` 是被首页那几条
  /// 货架复用的(靠 `type` 区分),不给它按 type 分派的话,「最近播放」与
  /// 「最常播放」会拿到同一份假数据,测出来像是接对了其实没有。
  Dio payloadDio(
    List<Uri> seen,
    Map<String, Map<String, dynamic>> byEndpoint, {
    Map<String, Map<String, dynamic>> byQueryType = const {},
  }) {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        seen.add(options.uri);
        final endpoint = options.uri.pathSegments.last.replaceAll('.view', '');
        final type = options.uri.queryParameters['type'];
        final payload = (type == null ? null : byQueryType[type]) ??
            byEndpoint[endpoint] ??
            _ok(const {});
        interceptor.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode(payload),
        ));
      },
    ));
    return dio;
  }

  Map<String, Map<String, dynamic>> libraryFixtures() => {
        'getPlaylists': _ok({
          'playlists': {
            'playlist': [
              {'id': 'pl-1', 'name': '深夜驾驶', 'songCount': 3},
              {'id': 'pl-2', 'name': '通勤', 'songCount': 0},
            ]
          }
        }),
        'getAlbumList2': _ok({
          'albumList2': {
            'album': [
              _album('al-1', '可能', '程响', 2022),
              _album('al-2', 'Ultraviolet', '3LAU', 2018),
            ]
          }
        }),
        'getArtists': _ok({'artists': {'index': []}}),
        // 三首曲子:标题序、艺人序、入库序三档排出来各不相同。
        'search3': _ok({
          'searchResult3': {
            'song': [
              _song('s1', '可能', '程响', '2025-01-02T00:00:00.000Z'),
              _song('s2', 'Ultraviolet', '3LAU', '2026-01-05T00:00:00.000Z'),
              _song('s3', '山丘', '李宗盛', '2024-06-01T00:00:00.000Z'),
            ]
          }
        }),
        'getStarred2': _ok({'starred2': {}}),
      };

  /// 音频缓存。**单独一个目录** —— 与下载、与库快照都不共用:
  /// 它按自己的上限淘汰,混在一起会把别人的文件数进占用里。
  Future<MediaCache> openAudioCache(Directory root) => MediaCache.open(
        limitBytes: CacheLimit.gb1.bytes,
        root: Directory('${root.path}${Platform.pathSeparator}audio'),
      );

  Future<AppState> buildState(
    Dio dio,
    Directory root, {
    LibraryCache? cache,
    ServerConfig server = config,
  }) async {
    final configStore = await ConfigStore.open();
    final downloads = await DownloadStore.open(root: root);

    // late 局部变量:下载器读应用状态,应用状态持有下载器(与 main.dart 同一套)。
    late final AppState appState;
    appState = AppState(
      configStore: configStore,
      credentialStore: CredentialStore(),
      quality: QualityController(),
      downloadManager: DownloadManager(
        store: downloads,
        repository: () => appState.repository,
        wifiOnly: () => false,
      ),
      libraryCache: cache ?? await LibraryCache.open(root: root),
      mediaCache: await openAudioCache(root),
      dio: dio,
    );

    appState.adoptServer(server);
    appState.attachRepository(server, 'p');
    return appState;
  }

  group('歌单写操作', () {
    late List<Uri> seen;
    late Map<String, Map<String, dynamic>> endpoints;
    late AppState state;
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      seen = [];
      endpoints = libraryFixtures();
      root = await Directory.systemTemp.createTemp('nordic-state');
      state = await buildState(payloadDio(seen, endpoints), root);
      await state.loadLibrary();
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('库里那份歌单是服务器给的那两条', () {
      expect(state.library.playlists.map((p) => p.name), ['深夜驾驶', '通勤']);
    });

    test('加一首进歌单:本地条数立刻跟着变', () async {
      await state.addSongToPlaylist('pl-1', 'song-9');

      final write = seen.last;
      expect(write.path, '/rest/updatePlaylist.view');
      expect(write.queryParameters['songIdToAdd'], 'song-9');
      // 不重拉整库(那会打断浏览),但数字不能停在旧的 —— 否则「已加入」
      // 与列表里的「3 首」互相打脸。
      expect(state.library.playlists.first.songCount, 4);
      expect(state.library.playlists.last.songCount, 0,
          reason: '没被点到的歌单不该跟着变');
    });

    test('从歌单移除一首:本地条数减一', () async {
      await state.removeSongFromPlaylist('pl-1', 1);

      expect(seen.last.queryParameters['songIndexToRemove'], '1');
      expect(state.library.playlists.first.songCount, 2);
    });

    test('重命名:首尾空格去掉,本地名字立刻跟着改', () async {
      await state.renamePlaylist('pl-1', '  夜间驾驶  ');

      expect(seen.last.queryParameters['name'], '夜间驾驶');
      expect(state.library.playlists.first.name, '夜间驾驶');
    });

    test('删除:本地列表里也就不再有它', () async {
      await state.deletePlaylist('pl-1');

      expect(seen.last.path, '/rest/deletePlaylist.view');
      expect(state.library.playlists.map((p) => p.id), ['pl-2']);
    });

    test('服务器拒绝时本地不留假象', () async {
      endpoints['updatePlaylist'] = _failed(50, 'Not allowed');

      await expectLater(
        state.addSongToPlaylist('pl-1', 'song-9'),
        throwsA(isA<SubsonicException>()),
      );
      // 先改本地再发请求的乐观更新在这里是错的:服务器没答应,列表却已经变了。
      expect(state.library.playlists.first.songCount, 3);
    });

    test('还没连服务器时说人话,而不是静默失败', () async {
      final bare = AppState(
        configStore: state.configStore,
        credentialStore: state.credentialStore,
        quality: state.quality,
        downloadManager: state.downloadManager,
        libraryCache: state.libraryCache,
        mediaCache: state.mediaCache,
      );

      await expectLater(
        bare.addSongToPlaylist('pl-1', 'song-9'),
        throwsA(isA<SubsonicException>()
            .having((e) => e.message, 'message', contains('还没有连接服务器'))),
      );
    });
  });

  /// 一条也发不出去的 dio —— 「网断了」用。
  Dio offlineDio() {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) => interceptor.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: '连不上',
      )),
    ));
    return dio;
  }

  group('音乐库缓存', () {
    late Directory root;
    late LibraryCache cache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('nordic-cache');
      cache = await LibraryCache.open(root: root);
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('刷新一次之后,快照落到缓存里 —— 重启就能直接铺出来', () async {
      final warm = await buildState(
        payloadDio([], libraryFixtures()),
        root,
        cache: cache,
      );
      await warm.loadLibrary();

      // 换一个 AppState 读同一块目录,相当于重启应用。
      final fresh = await buildState(
        payloadDio([], libraryFixtures()),
        root,
        cache: cache,
      );
      await fresh.loadCachedLibrary();

      expect(fresh.library.albums.length, 2);
      expect(fresh.library.songs.length, 3);
      expect(fresh.libraryFromCache, isTrue, reason: '这是缓存铺出来的,还没刷新');
      expect(fresh.libraryCachedAt, isNotNull);
      expect(fresh.phase, LoadPhase.ready, reason: '铺完缓存就该 ready,不该空等');
    });

    test('刷新失败但手上有缓存:不切错误态,只留一句「这次没刷上」', () async {
      final warm = await buildState(
        payloadDio([], libraryFixtures()),
        root,
        cache: cache,
      );
      await warm.loadLibrary();

      // 冷启动:先铺缓存,再刷新 —— 这次连不上。
      final offline = await buildState(offlineDio(), root, cache: cache);
      await offline.loadCachedLibrary();
      await offline.loadLibrary();

      expect(offline.phase, LoadPhase.ready, reason: '有缓存就别把界面切成错误态');
      expect(offline.library.albums, isNotEmpty, reason: '缓存那份要留着');
      expect(offline.refreshError, isNotNull);
      expect(offline.libraryFromCache, isTrue);
    });

    test('刷新成功之后,「来自缓存」归位', () async {
      final warm = await buildState(
        payloadDio([], libraryFixtures()),
        root,
        cache: cache,
      );
      await warm.loadLibrary();

      final fresh = await buildState(
        payloadDio([], libraryFixtures()),
        root,
        cache: cache,
      );
      await fresh.loadCachedLibrary();
      await fresh.loadLibrary();

      expect(fresh.libraryFromCache, isFalse);
      expect(fresh.refreshError, isNull);
    });

    test('一点缓存都没有时照旧如实报错', () async {
      final offline = await buildState(offlineDio(), root, cache: cache);
      await offline.loadCachedLibrary(); // 空的
      await offline.loadLibrary();

      expect(offline.phase, LoadPhase.failed);
      expect(offline.refreshError, isNull);
    });

    test('换了服务器就不认上一台的缓存', () async {
      final warm = await buildState(
        payloadDio([], libraryFixtures()),
        root,
        cache: cache,
      );
      await warm.loadLibrary();

      // 同一块缓存目录,但配置里的账号换了 —— 那是另一台库。
      final other = await buildState(
        payloadDio([], libraryFixtures()),
        root,
        cache: cache,
        server: const ServerConfig(
          id: 's1',
          name: '另一个账号',
          kind: ServerKind.navidrome,
          username: 'someone-else',
          routes: [
            ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com'),
          ],
        ),
      );
      await other.loadCachedLibrary();

      expect(other.library.albums, isEmpty, reason: '别拿上一台服务器的库顶上来');
      expect(other.libraryFromCache, isFalse);
    });
  });

  group('测速', () {
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('nordic-ping');
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('测速期间有忙碌态,结束时收回', () async {
      // 局域网一次 ping 是个位数毫秒 —— 没有这个状态,界面上按钮不变、
      // 数字也不变,用户只会觉得「按了没反应」。
      final state = await buildState(payloadDio([], libraryFixtures()), root);
      expect(state.pinging, isFalse);

      final pending = state.refreshRouteLatency();
      // 不 await 就看:同步段里就该已经是「测速中」。
      expect(state.pinging, isTrue);

      await pending;
      expect(state.pinging, isFalse);
    });
  });

  group('换线路', () {
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('nordic-routes');
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('改路线路当场落到正在用的客户端上', () async {
      // 真机报的「线路切换无效」:配置改了,而客户端手上还是建库时那份拷贝。
      final state = await buildState(payloadDio([], libraryFixtures()), root);
      final client = state.repository!.client;

      await state.updateRoutes(const [
        ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com'),
        ServerRoute(
          id: 'wan',
          name: '外网',
          url: 'http://wan.example.com',
          selected: true,
        ),
      ]);

      expect(state.activeRoute?.id, 'wan', reason: '界面上的勾先动');
      expect(
        client.activeRoute?.id,
        'wan',
        reason: '客户端也得跟着换,不然请求照旧走旧线路 —— 那个勾就是假的',
      );
    });

    test('生效线路真变了就通知播放层重载当前曲目', () async {
      final state = await buildState(payloadDio([], libraryFixtures()), root);
      var retargets = 0;
      state.onRouteChanged = () async => retargets++;

      // 没变(还是那条局域网)—— 不该惊动播放层。
      await state.updateRoutes(const [
        ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com'),
      ]);
      expect(retargets, 0, reason: '线路没换就重新装载,只是白等一次缓冲');

      await state.updateRoutes(const [
        ServerRoute(
          id: 'wan',
          name: '外网',
          url: 'http://wan.example.com',
          selected: true,
        ),
      ]);
      expect(retargets, 1);
    });
  });

  group('首页那几条货架', () {
    // 首页的「最近添加 / 最近播放 / 最常播放」都是服务器口径(本地算不出来),
    // 三个货架走的是**同一个端点**(`getAlbumList2`)的不同 `type`。
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('nordic-home');
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    /// 三条货架各给一份**认得出是谁**的数据 —— 接错了顺序当场就能看出来。
    Map<String, Map<String, dynamic>> homeTypes() => {
          'newest': _albumsPayload('刚加进来的'),
          'recent': _albumsPayload('刚听过的'),
          'frequent': _albumsPayload('听得最多的'),
        };

    test('三条货架各按自己的口径取,整合进同一份快照', () async {
      final state = await buildState(
        payloadDio([], libraryFixtures(), byQueryType: homeTypes()),
        root,
      );
      await state.loadLibrary();

      // 「最近添加」不再单独拉专辑货架 —— 它铺的是歌曲,由本地从 songs 排出来
      // (见下面那一条)。所以这里只验另外两条服务器口径的货架。
      expect(state.library.recentlyPlayed.map((a) => a.name), ['刚听过的']);
      expect(state.library.mostPlayed.map((a) => a.name), ['听得最多的']);
      // 整库那一栏仍是用户选的口径,没被这几条顶掉。
      expect(state.library.albums.map((a) => a.name), ['可能', 'Ultraviolet']);
    });

    test('「最近添加」按入库时间降序铺歌曲', () async {
      final state = await buildState(
        payloadDio([], libraryFixtures(), byQueryType: homeTypes()),
        root,
      );
      await state.loadLibrary();

      // 夹具里三首的 created 是 2026-01-05 / 2025-01-02 / 2024-06-01,
      // 所以「最近添加」应当是 s2 → s1 → s3。
      expect(
        state.library.recentlyAddedSongs.map((s) => s.id),
        ['s2', 's1', 's3'],
        reason: '「最近添加」是歌曲,按 Song.created 倒序,而不是专辑',
      );
    });

    test('换歌曲排序后货架还在 —— 只改一份列表不能把别的弄丢', () async {
      final state = await buildState(
        payloadDio([], libraryFixtures(), byQueryType: homeTypes()),
        root,
      );
      await state.loadLibrary();
      await state.setSongSort(SongSort.artist);

      expect(
        state.library.mostPlayed.map((a) => a.name),
        ['听得最多的'],
        reason: '「改一份列表」的写法漏带上这几位,首页那一栏就会悄悄空掉',
      );
      expect(state.library.recentlyPlayed, isNotEmpty);
      expect(state.library.recentlyAddedSongs, isNotEmpty);
    });

    test('缓存往返:重启之后首页照样有东西', () async {
      final cache = await LibraryCache.open(root: root);
      final first = await buildState(
        payloadDio([], libraryFixtures(), byQueryType: homeTypes()),
        root,
        cache: cache,
      );
      await first.loadLibrary();

      // 新实例、同一份缓存 —— 相当于冷启动。
      final restored = await buildState(
        payloadDio([], libraryFixtures(), byQueryType: homeTypes()),
        root,
        cache: cache,
      );
      await restored.loadCachedLibrary();

      expect(restored.library.mostPlayed.map((a) => a.name), ['听得最多的']);
      expect(restored.library.recentlyPlayed.map((a) => a.name), ['刚听过的']);
    });
  });

  group('歌曲翻页', () {
    // 一页 1000(见 `AppState._songPageSize`):常见个人库一个请求就完整,
    // 更大的库由**后台**一页页补齐(滚动到底也会接着取)。这一组钉住:
    // 翻页 offset、去重、后台补齐、「最近添加」随补齐重算。
    late Directory root;
    late List<Uri> seen;

    /// 这一组会**连着翻页**,而翻页那一头现在不 `await` 写盘了
    /// (见 `AppState.loadMoreSongs`)—— 写由 `LibraryCache` 排队合并。
    /// 收尾删目录之前必须等它落定,否则 Windows 上就是
    /// 「另一个程序正在使用此文件」。
    late LibraryCache cache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('nordic-paging');
      cache = await LibraryCache.open(root: root);
      seen = [];
    });

    tearDown(() async {
      await cache.settle();
      if (root.existsSync()) await root.delete(recursive: true);
    });

    /// 一台「有 1200 首」的假服务器:按 `songOffset` 切页,一页最多 `songCount`。
    /// 三个数字都是**服务器口径**里的真值,不另存一份 —— 这样「取了几页」
    /// 只能从发出去的请求看出来。
    ///
    /// [cap] 模拟**把 `search3` 卡在某个条数上**的服务器(Navidrome 之外
    /// 有些实现是 500):要 1000 也只给 500。
    Dio pagingDio(int librarySize, {int? cap}) {
      Dio dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, interceptor) {
          seen.add(options.uri);
          final q = options.uri.queryParameters;
          var count = int.tryParse(q['songCount'] ?? '500') ?? 500;
          if (cap != null && count > cap) count = cap;
          final offset = int.tryParse(q['songOffset'] ?? '0') ?? 0;
          // 每首的入库时间按序号递增 —— 与真机 Navidrome 的 `search3` 一致:
          // 序号越大越新,也就越靠后(升序)。这样「只排第一页」与「排全量」
          // 的结果会明显不同,测试才验得出「补齐后重算」。
          final songs = [
            for (var i = offset; i < offset + count && i < librarySize; i++)
              _song(
                's$i',
                '第 $i 首',
                '艺人',
                DateTime.utc(2026, 1, 1).add(Duration(hours: i)).toIso8601String(),
              ),
          ];
          /* 专辑那一栏是 `totalSongs` 的依据(伺服器标称的总数取自 songCount 之和,
             不是本地取到的条数)—— 不摆一张「有 1200 首」的专辑,
             「还差多少」就永远算成 0。 */
          final body = q.containsKey('songCount') && options.uri.path.contains('search3')
              ? _ok({'searchResult3': {'song': songs, 'album': [], 'artist': []}})
              : _ok({
                  'albumList2': {
                    'album': [
                      {
                        'id': 'al-all',
                        'name': '整库',
                        'artist': '艺人',
                        'artistId': 'ar-1',
                        'songCount': librarySize,
                      }
                    ]
                  }
                });
          interceptor.resolve(Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: jsonEncode(body),
          ));
        },
      ));
      return dio;
    }

    Future<AppState> stateWith(int librarySize) async {
      final state = await buildState(pagingDio(librarySize), root, cache: cache);
      await state.loadLibrary();
      return state;
    }

    test('首屏一页 1000 —— 常见库一个请求就完整', () async {
      final state = await stateWith(900);

      expect(state.library.songs.length, 900);
      expect(state.library.songsComplete, isTrue);
      final searches = seen.where((u) => u.path.contains('search3')).toList();
      expect(searches.length, 1, reason: '一页装下了,不该再发第二页');
      expect(searches.single.queryParameters['songCount'], '1000');
    });

    test('首屏之后后台接着补全 —— 不把几十个往返压在启动路径上', () async {
      final state = await stateWith(1200);
      // 首屏那一页已经回来了;后台补齐还没落地时,列表先给一页。
      expect(state.library.songs.length, 1000);
      expect(state.library.songsComplete, isFalse);

      await state.songsSettled;

      expect(state.library.songs.length, 1200);
      expect(state.library.songsComplete, isTrue);
      expect(state.library.totalSongs, 1200);
      final searches = seen.where((u) => u.path.contains('search3')).toList();
      expect(searches.map((u) => u.queryParameters['songOffset']).toList(),
          [null, '1000'], reason: 'offset 必须按「取回过的原始条数」走');
    });

    test('服务器把一页卡在 500 时也要翻到底 —— 「不足一页」不等于「到底了」', () async {
      final state =
          await buildState(pagingDio(3000, cap: 500), root, cache: cache);
      await state.loadLibrary();

      // 首屏只有 500 条,但它显然不是全部 —— 专辑那一栏报的规模是 3000。
      // 按条数判的话这里就该收摊了,库永远停在 500。
      expect(state.library.songs.length, 500);
      expect(state.library.songsComplete, isFalse);

      await state.songsSettled;

      expect(state.library.songs.length, 3000);
      expect(state.library.songsComplete, isTrue);
      // 「最近添加」按全量重算 —— 最新的那几首在最后一页上。
      expect(state.library.recentlyAddedSongs.first.id, 's2999');
    });

    test('取到不足一页就到底了 —— 页脚那句「已取到全部」的依据', () async {
      final state = await stateWith(1201);
      await state.songsSettled;

      expect(state.library.songs.length, 1201);
      expect(state.library.songsComplete, isTrue);
      // 取全之后总数以实际条数为准,不再拿专辑 songCount 的估计值。
      expect(state.library.totalSongs, 1201);
    });

    test('到底之后再喊一次不会白发请求', () async {
      final state = await stateWith(1201);
      await state.songsSettled;
      seen.clear();

      final again = await state.loadMoreSongs();

      expect(again, isFalse);
      expect(seen, isEmpty, reason: '已经取全了,不该再打服务器');
    });

    test('翻页按 id 去重 + 按当前口径重排', () async {
      final state = await stateWith(2500);
      await state.songsSettled;
      // 换一个「新取的会插到中间」的口径,重排有没有做才看得出来。
      await state.setSongSort(SongSort.title);

      final ids = state.library.songs.map((s) => s.id).toList();
      expect(ids.length, ids.toSet().length, reason: '按 id 去重,不该出重复行');
      // 标题序:后一页不该整块挂在「第 100 首」后面。
      final titles = state.library.songs.map((s) => s.title).toList();
      expect(titles, orderedEquals([...titles]..sort()));
    });

    test('「最近添加」随补齐重算 —— 最新的歌在最后一页也能排到最前', () async {
      // `search3` 是 created **升序**:最后那几页才是最新的。只排第一页时
      // 货架会错(真机报的就是这条),补齐之后必须排对。
      final state = await stateWith(1500);
      await state.songsSettled;

      final newest = state.library.recentlyAddedSongs;
      // 夹具里 created 随序号递增,所以全量排出来应当是最后 20 首,倒序。
      expect(
        newest.map((s) => s.id).take(3).toList(),
        ['s1499', 's1498', 's1497'],
        reason: '补齐之后「最近添加」必须从全量里排,而不是只看第一页',
      );
    });
  });

  group('排序', () {
    late List<Uri> seen;
    late Directory root;
    late AppState state;

    /// 按 `type` 参数回**不同顺序**的专辑 —— 换口径要能看出来真的重拉了一版。
    Dio sortingDio(List<Uri> seen) {
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, interceptor) {
          seen.add(options.uri);
          if (options.uri.path.endsWith('getAlbumList2.view')) {
            final byName = options.uri.queryParameters['type'] == 'alphabeticalByName';
            final albums = byName
                ? [_album('al-1', '可能', '程响', 2022), _album('al-2', 'Ultraviolet', '3LAU', 2018)]
                : [_album('al-2', 'Ultraviolet', '3LAU', 2018), _album('al-1', '可能', '程响', 2022)];
            interceptor.resolve(Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: jsonEncode(_ok({'albumList2': {'album': albums}})),
            ));
            return;
          }
          final endpoint = options.uri.pathSegments.last.replaceAll('.view', '');
          interceptor.resolve(Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: jsonEncode(libraryFixtures()[endpoint] ?? _ok(const {})),
          ));
        },
      ));
      return dio;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      seen = [];
      root = await Directory.systemTemp.createTemp('nordic-state-sort');
      state = await buildState(sortingDio(seen), root);
      await state.loadLibrary();
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('换专辑排序:按新口径重拉这一栏', () async {
      expect(state.albumSort, AlbumSort.alphabeticalByArtist);

      await state.setAlbumSort(AlbumSort.alphabeticalByName);

      final last = seen.last;
      expect(last.path, endsWith('getAlbumList2.view'));
      expect(last.queryParameters['type'], 'alphabeticalByName');
      // 列表真的换了(这一版按名称是「可能」在前)。
      expect(state.library.albums.first.name, '可能');
    });

    test('排序口径存下来:下次开一个 AppState 还是它', () async {
      await state.setAlbumSort(AlbumSort.newest);

      // 同一份 prefs 再建一个 —— 相当于重启应用。
      final fresh = await buildState(sortingDio(<Uri>[]), root);
      expect(fresh.albumSort, AlbumSort.newest);
      expect(fresh.songSort, SongSort.title);
    });

    test('换歌曲排序:本地排,不再打服务器', () async {
      final before = seen.length;

      await state.setSongSort(SongSort.added);

      expect(seen.length, before, reason: '曲子本来就在手上,没必要再问一次');
      expect(
        [for (final s in state.library.songs) s.title],
        ['Ultraviolet', '可能', '山丘'],
        reason: '按入库时间新的在前',
      );
    });

    test('入库时间从载荷里读到了 —— 排序才有依据', () {
      final song = state.library.songs.firstWhere((s) => s.id == 's2');
      expect(song.created, DateTime.utc(2026, 1, 5));
    });

    test('换排序时的失败会抛出来,本地那份列表保持原样', () async {
      final broken = Dio(BaseOptions(validateStatus: (_) => true));
      broken.interceptors.add(InterceptorsWrapper(
        onRequest: (options, interceptor) => interceptor.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: '连不上',
        )),
      ));
      final offline = await buildState(broken, root);

      await expectLater(
        offline.setAlbumSort(AlbumSort.newest),
        throwsA(isA<SubsonicException>()),
      );
      expect(offline.library.albums, isEmpty, reason: '没拉到就保持原样,别清空');
    });
  });

  group('加载失败的类别', () {
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('nordic-state-fail');
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('连不上服务器:标成网络问题(界面据此指去下载管理)', () async {
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, interceptor) => interceptor.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: '连不上',
        )),
      ));

      final state = await buildState(dio, root);
      await state.loadLibrary();

      expect(state.phase, LoadPhase.failed);
      expect(state.errorIsNetwork, isTrue);
      expect(state.errorIsAuth, isFalse, reason: '「连不上」不该被说成密码错');
    });

    test('密码不对:标成认证问题,不误报成网络问题', () async {
      final dio = payloadDio([], {
        for (final key in libraryFixtures().keys)
          key: _failed(40, 'Wrong username or password'),
      });

      final state = await buildState(dio, root);
      await state.loadLibrary();

      expect(state.errorIsAuth, isTrue);
      expect(state.errorIsNetwork, isFalse,
          reason: '认证失败时让用户去下载管理是答非所问');
    });
  });
}

Map<String, dynamic> _ok(Map<String, dynamic> body) => {
      'subsonic-response': {
        'status': 'ok',
        'version': '1.16.1',
        ...body,
      }
    };

Map<String, dynamic> _failed(int code, String message) => {
      'subsonic-response': {
        'status': 'failed',
        'version': '1.16.1',
        'error': {'code': code, 'message': message},
      }
    };

Map<String, dynamic> _album(String id, String name, String artist, int year) => {
      'id': id,
      'name': name,
      'artist': artist,
      'year': year,
      'songCount': 1,
    };

/// `getAlbumList2` 的一份载荷 —— 只有一张专辑,名字就是它的身份标签。
Map<String, dynamic> _albumsPayload(String label) => _ok({
      'albumList2': {
        'album': [
          {
            'id': 'al-$label',
            'name': label,
            'artist': '艺人',
            'artistId': 'ar-1',
            'songCount': 1,
          }
        ]
      }
    });

Map<String, dynamic> _song(String id, String title, String artist, String created) => {
      'id': id,
      'title': title,
      'artist': artist,
      'album': '专辑',
      'albumId': 'al-1',
      'suffix': 'flac',
      'size': 1024,
      'created': created,
    };
