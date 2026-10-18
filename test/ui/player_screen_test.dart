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
import 'package:nordic/data/models.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/player_screen.dart';
import 'package:nordic/ui/screens/lyrics_screen.dart';
import 'package:nordic/ui/routes.dart';
import 'package:nordic/ui/widgets/cover.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_playback.dart';

/// 播放页 —— 坞 / 歌曲行点进来的那一程的终点。
///
/// 两件事:
///
/// 1. **这一屏不做封面的共享元素过渡。** 原型的起点是**从被点的那个元素**上
///    取的(`app.js` 的 `t.closest('[data-morph]')`),而坞与歌曲行都不带
///    `data-morph` —— 点坞进播放页那一程原型故意不飞。这里留一个 `Hero`,
///    框架就会去**整个来源路由**里按 tag 找起点,保活但看不见的专辑网格会来
///    当起点:封面从屏幕外飞进来、每帧重画,正好落在滑入动画上。
/// 2. **这一屏的重建面。** `_HeroStack` / `_SongInfo` 只该订自己真正用到的那
///    一件事(仓库 / 收藏),而不是整份 `AppState` —— 后者会因为下载进度
///    (最多每秒四次)与缓存淘汰而通知,每来一次就重跑一遍 `repo.coverUri()`
///    (里头要线性翻一遍下载记录)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  /// **不带给封面 id** —— 这一组不接网络:封面走渐变兜底,要验的是重建面,
  /// 不是封面本身(带了 id 就会建一个 HttpClient,测试里那种请求一律 400)。
  const playing = Song(
    id: 's-1',
    title: '正在放的这首',
    artist: '艺人',
    album: '专辑',
    albumId: 'al-1',
    duration: Duration(seconds: 200),
  );

  /// 空载荷 —— 这一组只用到收藏那一个写操作。
  Dio fakeDio() {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        interceptor.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode({
            'subsonic-response': {'status': 'ok', 'version': '1.16.1'}
          }),
        ));
      },
    ));
    return dio;
  }

  late Directory root;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-player-ui');

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
      mediaCache: await MediaCache.open(
        limitBytes: CacheLimit.gb1.bytes,
        root: Directory('${root.path}${Platform.pathSeparator}audio'),
      ),
      dio: fakeDio(),
    );
    state = appState;
    // 收藏要一个仓库才动得了 `_toggleStar`(没有仓库它直接返回)。
    state.adoptServer(config);
    state.attachRepository(config, 'p');
  });

  tearDown(() async {
    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } on FileSystemException {
      // Windows 上临时目录偶尔被抢住(文件句柄还没松)—— 系统自己会清。
    }
  });

  Future<void> pumpPlayer(WidgetTester tester) async {
    final playable = playingController(playing);
    addTearDown(() {
      playable.dispose();
      playable.handler.player.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<PlaybackController>.value(value: playable),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          // 这一组要点进歌词页 —— 而歌词是**一条推入的路由**,路由表得在场。
          // '/' 是起点(这一屏自己),其余照 `AppRoutes.generate`:
          // 歌词那条是零时长的翻面,与产品里走的同一条。
          onGenerateRoute: (settings) =>
              settings.name == Navigator.defaultRouteName
                  ? MaterialPageRoute<void>(builder: (_) => const PlayerScreen())
                  : AppRoutes.generate(settings),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// 让 `_toggleStar` 那一趟网络真的跑完 —— Dio 的拦截器链落在一条
  /// **0 延迟的 Timer** 上,裸 `pump()` 过不去,留着它测试结束会报
  /// 「Pending timers」。
  Future<void> settleStarToggle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  /// 进歌词页那一下的收尾:那一屏会去拉一次歌词,裸 `pump()` 推不动 Dio 的
  /// 拦截器链(它落在一条零延迟的 Timer 上),留着它测试结束会报 Pending timers。
  Future<void> settleLyrics(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  testWidgets('点封面区里的留白也翻到歌词 —— 不只是封面那一块算数', (tester) async {
    await pumpPlayer(tester);

    // 封面旁边那一片空白:它属于封面区(原型里整块 `.player-hero` 是入口),
    // 而原先只有一个裹着封面的 GestureDetector —— 点这儿什么也不发生。
    final cover = tester.getRect(find.byType(Cover));
    await tester.tapAt(Offset(cover.left - 40, cover.center.dy));
    await tester.pump();

    expect(find.byType(LyricsScreen), findsOneWidget);
    await settleLyrics(tester);
  });

  testWidgets('点歌名也翻到歌词', (tester) async {
    await pumpPlayer(tester);

    // 歌名原先谁都不指向;艺人 / 专辑那两条链接各有各的去处(它们的用例在
    // 原型自检里),这里只钉歌名这一处新入口。
    await tester.tap(find.text(playing.title));
    await tester.pump();

    expect(find.byType(LyricsScreen), findsOneWidget);
    await settleLyrics(tester);
  });

  testWidgets('播放页不做封面的共享元素过渡 —— 没有 Hero', (tester) async {
    await pumpPlayer(tester);

    // 封面本身还在,只是不飞。
    expect(find.byType(Cover), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PlayerScreen),
        matching: find.byType(Hero, skipOffstage: false),
      ),
      findsNothing,
      reason: '播放页一旦挂着 Hero，框架就会去整个来源路由里按 tag 找起点 —— '
          '保活但看不见的那张专辑网格会来当起点，封面从屏幕外飞进来',
    );
  });

  testWidgets('与这张封面无关的通知不该重建它', (tester) async {
    await pumpPlayer(tester);
    final before = tester.widget<Cover>(find.byType(Cover));

    // 收藏**别的**歌曲:与这一屏画出来的东西无关,却会走一遍 AppState 的通知。
    // 下载进度(最多每秒四次)与缓存淘汰是同一类。
    //
    // **不能 `await`**:FakeAsync 时钟下那趟网络要 `pump` 才走,在用例体里
    // 等它等于把自己挂住(`_toggleStar` 的本地改动与通知是同步发出的,
    // 所以要验的那一下已经发生了)。
    unawaited(state.toggleSongStar('另一首'));
    await tester.pump();

    expect(
      identical(tester.widget<Cover>(find.byType(Cover)), before),
      isTrue,
      reason: '无关的通知把这一块订阅面拖着重建了',
    );

    await settleStarToggle(tester);
  });

  testWidgets('收藏当前这一首，心形要跟着变', (tester) async {
    await pumpPlayer(tester);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    // 收窄订阅面之后,「自己这一首」的收藏仍要立刻反映出来 ——
    // 这一条守的是另一个方向(别把 `select` 写得收不到通知)。
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(state.isSongStarred(playing.id), isTrue);

    await settleStarToggle(tester);
  });
}