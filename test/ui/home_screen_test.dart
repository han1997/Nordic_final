import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/playback/audio_handler.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首页是**主屏**(冷启动落在这儿),它自己的错最贵:
/// 一条货架接错了、空态写成了「暂无」、或者少带一个 provider,
/// 用户一进门就看见。这一组把「有没有东西、说的是不是人话」钉住。
/// 音频缓存。**单独一个目录** —— 与下载、与库快照都不共用:
/// 它按自己的上限淘汰,混在一起会把别人的文件数进「已用空间」。
Future<MediaCache> openAudioCache(Directory root) => MediaCache.open(
      limitBytes: CacheLimit.gb1.bytes,
      root: Directory('${root.path}${Platform.pathSeparator}audio'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  Map<String, dynamic> ok(Map<String, dynamic> body) => {
        'subsonic-response': {
          'status': 'ok',
          'version': '1.16.1',
          ...body,
        }
      };

  Map<String, dynamic> albumsPayload(String label, {String? id}) => ok({
        'albumList2': {
          'album': [
            {
              'id': id ?? 'al-$label',
              'name': label,
              'artist': '艺人',
              'artistId': 'ar-1',
              'songCount': 1,
            }
          ]
        }
      });

  /// 歌曲载荷 —— 「最近添加」货架现在铺**歌曲**,列表由本地按 `created` 排。
  /// 这里给两首,时间新的那首该排在前面。
  Map<String, dynamic> songsPayload() => ok({
        'searchResult3': {
          'song': [
            {
              'id': 's-old',
              'title': '早一点的',
              'artist': '艺人',
              'album': '专辑',
              'albumId': 'al-1',
              'duration': 200,
              'created': '2026-01-01T00:00:00.000Z',
            },
            {
              'id': 's-new',
              'title': '刚加进来的',
              'artist': '艺人',
              'album': '专辑',
              'albumId': 'al-2',
              'duration': 180,
              'created': '2026-10-12T00:00:00.000Z',
            },
          ]
        }
      });

  /// 只按 `type` 分派 `getAlbumList2`、按端点分派歌曲,其余端点给空载荷 ——
  /// 首页只用得到货架那几条。
  Dio fakeDio() {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        final endpoint = options.uri.pathSegments.last.replaceAll('.view', '');
        final type = options.uri.queryParameters['type'];
        final payload = switch (endpoint) {
          // 「最近播放」与「最常播放」**给同一张专辑** —— 真机上这两条榜单
          // 本来就常常有重合,而两条货架的封面各自挂着一个共享元素。
          'getAlbumList2' => albumsPayload(
              switch (type) {
                'recent' => '刚听过的',
                'frequent' => '听得最多的',
                _ => '刚加进来的',
              },
              id: type == 'recent' || type == 'frequent' ? 'al-hot' : null,
            ),
          'search3' => songsPayload(),
          _ => ok(const {}),
        };
        interceptor.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode(payload),
        ));
      },
    ));
    return dio;
  }

  late Directory root;
  late MediaCache audioCache;
  late AppState state;
  late PlaybackController playable;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-home-ui');
    audioCache = await openAudioCache(root);

    // late 局部变量:下载器读应用状态,应用状态持有下载器(与 main.dart 同一套)。
    late final AppState appState;
    appState = AppState(
      configStore: await ConfigStore.open(),
      credentialStore: CredentialStore(),
      quality: QualityController(),
      downloadManager: DownloadManager(
        store: await DownloadStore.open(root: root),
        repository: () => appState.repository,
        wifiOnly: () => false,
      ),
      libraryCache: await LibraryCache.open(root: root),
      mediaCache: audioCache,
      dio: fakeDio(),
    );
    state = appState;
    state.adoptServer(config);
    state.attachRepository(config, 'p');

    // 首页的播放卡要一个真的播放层。**不碰 `AudioService.init`** ——
    // 走 main.dart 里那条兜底路径(见 playback_test 的「播放层无条件在场」)。
    playable = PlaybackController(
      NordicAudioHandler(() => state.repository, QualityController()),
    );
  });

  tearDown(() async {
    playable.dispose();
    playable.handler.player.dispose();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<PlaybackController>.value(value: playable),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: const HomeScreen(),
        ),
      ),
    );
    // 不用 pumpAndSettle:转圈指示器永远在动,settle 不下来。
    await tester.pump();
    await tester.pump();
  }

  /// 拉一次库。**必须走 `runAsync`**:`loadLibrary` 里要真写一次缓存文件
  /// (见 `library_cache.write`),而 `testWidgets` 的 FakeAsync 时钟下真 I/O
  /// 永远等不回来 —— 直接 await 会挂在那儿不报错。
  Future<void> loadLibrary(WidgetTester tester) =>
      tester.runAsync(() => state.loadLibrary());

  testWidgets('加载完就把三条货架铺出来,各是各的', (tester) async {
    await loadLibrary(tester);
    await pumpHome(tester);

    // 一屏放不下三条,后一条要滚上来 —— 顺带验了这页是能滚的。
    expect(find.text('最近添加'), findsOneWidget);
    expect(find.text('刚加进来的'), findsOneWidget);
    expect(find.text('最近播放'), findsOneWidget);
    expect(find.text('刚听过的'), findsOneWidget);

    await tester.drag(find.text('最近播放'), const Offset(0, -420));
    await tester.pump();

    expect(find.text('最常播放'), findsOneWidget);
    expect(find.text('听得最多的'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一张专辑同时在两条货架上 —— 共享元素的 tag 不能撞', (tester) async {
    // 上面那份假载荷让「最近播放」与「最常播放」给的是**同一张专辑**(真机
    // 常态)。框架按 tag 在整条来源路由里找共享元素的起点(`heroes.dart` 的
    // `_allHeroesFor`),同一个 tag 出现两次直接断言失败 —— 症状是「从首页点进
    // 任何一页都崩」。早先两条货架用的是同一个前缀,测试没抓到只是因为夹具
    // 让两条榜单恰好不重合。
    await loadLibrary(tester);
    await pumpHome(tester);

    final tags = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((h) => h.tag)
        .toList();
    expect(tags, isNotEmpty);
    expect(tags.toSet().length, tags.length, reason: '同一条路由里 tag 不能重复');

    // 真走一次过渡:重复的 tag 会在这里被框架抛出来。
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });

  testWidgets('还没播过东西时,正在播放那一块说的是「从哪儿开始」', (tester) async {
    await loadLibrary(tester);
    await pumpHome(tester);

    // 不是空白、也不是假进度条 —— 一张说明性的卡片。
    expect(find.text('还没有在播的歌'), findsOneWidget);
    expect(find.text('已暂停'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('还没连服务器时给一句人话,不去碰播放层', (tester) async {
    // 全新用户看到的第一屏就是这个。这里造一个**没接管服务器**的实例 ——
    // 而不是调 disconnect():那条路要碰系统密钥库(测试里没有那个插件)。
    final fresh = AppState(
      configStore: await ConfigStore.open(),
      credentialStore: CredentialStore(),
      quality: QualityController(),
      downloadManager: DownloadManager(
        store: await DownloadStore.open(root: root),
        repository: () => null,
        wifiOnly: () => false,
      ),
      libraryCache: await LibraryCache.open(root: root),
      mediaCache: audioCache,
      dio: fakeDio(),
    );
    state = fresh;

    await pumpHome(tester);

    expect(find.text('还没有连接服务器'), findsWidgets);
    expect(find.text('最近添加'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('还没在播时给一颗「随机播放」,按下去就开播', (tester) async {
    await loadLibrary(tester);
    await pumpHome(tester);

    // 空态不是死的说明卡:最缺的就是「怎么开始」,所以给一个动作。
    expect(find.text('随机播放'), findsOneWidget);

    await tester.tap(find.text('随机播放'));
    await tester.pump();
    await tester.pump();

    // 队列装上了(库里那两首),界面从空态切到「正在播放」。
    expect(playable.queue, isNotEmpty);
    expect(find.text('还没有在播的歌'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
