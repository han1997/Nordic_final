import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
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
  Dio payloadDio(List<Uri> seen, Map<String, Map<String, dynamic>> byEndpoint) {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        seen.add(options.uri);
        final endpoint = options.uri.pathSegments.last.replaceAll('.view', '');
        final payload = byEndpoint[endpoint] ?? _ok(const {});
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
