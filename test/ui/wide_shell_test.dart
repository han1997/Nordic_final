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
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/routes.dart';
import 'package:nordic/ui/screens/home_screen.dart';
import 'package:nordic/ui/screens/library_screen.dart';
import 'package:nordic/ui/screens/player_screen.dart';
import 'package:nordic/ui/shell/bottom_stack.dart';
import 'package:nordic/ui/shell/nav_rail.dart';
import 'package:nordic/ui/shell/shell.dart';
import 'package:nordic/ui/shell/wide_bar.dart';
import 'package:nordic/ui/widgets/components.dart';
import 'package:nordic/ui/widgets/cover.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_playback.dart';

/// 宽屏(>= 840)的常驻区形态:左竖栏 + 播放横条。
///
/// 两条一起守:
///   1. **840 处翻面** —— 1280 是竖栏 + 横条,839 与 390 仍是底部托盘
///      (`BottomStack` 还在、竖栏不在):窄屏那一套一个字都没变;
///   2. 翻面之后语义照旧 —— 竖栏点 tab 真的换树且 HeroMode 仍每 tab 一层、
///      横条按下有底色且点得进播放页、没在放歌时整条不出现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const playing = Song(
    id: 's-1',
    title: '横条里的歌',
    artist: '艺人',
    album: '专辑',
    albumId: 'al-1',
    coverArtId: 'c-1',
    duration: Duration(seconds: 200),
  );

  /// 什么都回空载荷 —— 这一组不关心库里的内容(与 shell_test 同一套)。
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
  late QualityController quality;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-wide-shell-ui');
    quality = QualityController();

    late final AppState appState;
    appState = AppState(
      configStore: await ConfigStore.open(),
      credentialStore: CredentialStore(),
      quality: quality,
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
    // 与 shell_test 同一条:刻意不接管服务器 —— 首帧后的取库要真写缓存文件,
    // 在 FakeAsync 时钟下会挂住;这一组要验的是常驻区形态,库里有没有货无关。
  });

  tearDown(() async {
    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } on FileSystemException {
      // Windows 上临时目录偶尔被抢住 —— 系统自己会清。
    }
  });

  Future<void> pumpShell(
    WidgetTester tester,
    PlaybackController playable,
  ) async {
    addTearDown(() {
      playable.dispose();
      playable.handler.player.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<PlaybackController>.value(value: playable),
          ChangeNotifierProvider<QualityController>.value(value: quality),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          onGenerateRoute: AppRoutes.generate,
          home: const NordicShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void windowAt(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
  }

  /// 与 shell_test 同一条判据(宽视口重跑):某一屏自己还参不参与共享元素过渡。
  bool heroEnabledFor(WidgetTester tester, Type screen) => tester
      .widget<HeroMode>(
        find.ancestor(
          of: find.byType(screen, skipOffstage: false),
          matching: find.byType(HeroMode, skipOffstage: false),
        ),
      )
      .enabled;

  testWidgets('宽屏换左竖栏 + 播放横条；839 与 390 仍是底部托盘', (tester) async {
    addTearDown(tester.view.reset);

    windowAt(tester, const Size(1280, 800));
    await pumpShell(tester, playingController(playing));
    expect(find.byType(NordicNavRail), findsOneWidget);
    expect(find.byType(WidePlaybackBar), findsOneWidget);
    expect(find.byType(BottomStack), findsNothing,
        reason: '宽屏上托盘整条让位给竖栏 + 横条');

    // 840 的下边一像素:形态原样翻回去(这一条最容易被顺手挂错档位)。
    windowAt(tester, const Size(839, 900));
    await pumpShell(tester, playingController(playing));
    expect(find.byType(NordicNavRail), findsNothing);
    expect(find.byType(WidePlaybackBar), findsNothing);
    expect(find.byType(BottomStack), findsOneWidget);

    windowAt(tester, const Size(390, 844));
    await pumpShell(tester, playingController(playing));
    expect(find.byType(BottomStack), findsOneWidget);
    expect(find.byType(NordicNavRail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('竖栏三颗 tab 会真的换树，HeroMode 仍是每 tab 一层', (tester) async {
    addTearDown(tester.view.reset);
    windowAt(tester, const Size(1280, 800));
    await pumpShell(tester, playingController(playing));

    Finder railTab(String label) => find.descendant(
        of: find.byType(NordicNavRail), matching: find.text(label));

    expect(heroEnabledFor(tester, HomeScreen), isTrue);

    await tester.tap(railTab('音乐库'));
    await tester.pump();
    await tester.pump();
    expect(heroEnabledFor(tester, HomeScreen), isFalse);
    expect(heroEnabledFor(tester, LibraryScreen), isTrue);

    await tester.tap(railTab('设置'));
    await tester.pump();
    await tester.pump();
    expect(heroEnabledFor(tester, LibraryScreen), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('播放横条：没在放歌时整条不出现；有歌时可按下、点进播放页', (tester) async {
    addTearDown(tester.view.reset);
    windowAt(tester, const Size(1280, 800));

    // 没在放歌:竖栏照旧,横条不留一块空玻璃。
    await pumpShell(tester, idleController());
    expect(find.byType(NordicNavRail), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(WidePlaybackBar), matching: find.byType(Cover)),
      findsNothing,
    );

    // 有歌:横条在,整条是一块可点区域(与窄屏坞同一条 Pressable 口径)。
    await pumpShell(tester, playingController(playing));
    final barText = find.descendant(
        of: find.byType(WidePlaybackBar), matching: find.text(playing.title));
    expect(barText, findsOneWidget);

    final bar = find.ancestor(of: barText, matching: find.byType(Pressable));
    expect(bar, findsOneWidget, reason: '横条该是一整条可点区域');
    expect(tester.widget<Pressable>(bar).pressedDecoration, isNotNull);

    await tester.tap(barText);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
