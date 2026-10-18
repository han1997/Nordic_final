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
import 'package:nordic/ui/screens/settings_screen.dart';
import 'package:nordic/ui/shell/bottom_stack.dart';
import 'package:nordic/ui/shell/shell.dart';
import 'package:nordic/ui/widgets/components.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_playback.dart';

/// 主壳与底部托盘。
///
/// 这一组守的是两件**看不见但很贵**的事:
///
/// 1. **共享元素过渡的起点只在屏幕上那一屏里找。** 框架是按 tag 在**整个来源
///    路由**里找起点的、不看元素在不在屏幕上(`heroes.dart` 的 `_allHeroesFor`
///    只认 `HeroMode`),而 `IndexedStack` 会把逛过的 tab **整棵保活** ——
///    少了 `HeroMode` 这一层,「在首页点一张专辑 / 点播放坞」时起点会被音乐库
///    那张**看不见的专辑网格**偷走:封面从屏幕外飞进来,而且每帧都在一个变化的
///    矩形里重画(含投影模糊),正好落在滑入动画上 —— 读起来就是「卡」。
/// 2. **播放坞按下去要有反馈。** docs/performance.md 的「性能姿态」记过:可点元素没有按下
///    反馈时,手感上就是「这机器慢」—— 而坞是一整条大块面。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const playing = Song(
    id: 's-1',
    title: '坞里的歌',
    artist: '艺人',
    album: '专辑',
    albumId: 'al-1',
    coverArtId: 'c-1',
    duration: Duration(seconds: 200),
  );

  /// 什么都回空载荷 —— 这一组不关心库里的内容,只要那几棵树能立起来。
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
    root = await Directory.systemTemp.createTemp('nordic-shell-ui');
    quality = QualityController();

    // late 局部变量:下载器读应用状态,应用状态持有下载器(与 main.dart 同一套)。
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
      // 音频缓存**单独一个目录** —— 与下载、与库快照都不共用(见 home_screen_test)。
      mediaCache: await MediaCache.open(
        limitBytes: CacheLimit.gb1.bytes,
        root: Directory('${root.path}${Platform.pathSeparator}audio'),
      ),
      dio: fakeDio(),
    );
    state = appState;
    // **刻意不接管服务器**:主壳首帧之后会无条件触发一次取库(`shell.dart`
    // 的 initState),而那条路要真写缓存文件 —— 在 `testWidgets` 的 FakeAsync
    // 时钟下会挂在那儿,并留下一堆 pending timer。这一组要验的是主壳的
    // 共享元素与坞的手感,库里有没有货无关。
  });

  tearDown(() async {
    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } on FileSystemException {
      // Windows 上临时目录偶尔被抢住(文件句柄还没松)—— 系统自己会清,
      // 不影响用例结论。
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
          // 设置页要看转码档位(与 main.dart 同一份)。
          ChangeNotifierProvider<QualityController>.value(value: quality),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          // 路由表也接上 —— 点坞要能真的推到播放页。
          onGenerateRoute: AppRoutes.generate,
          home: const NordicShell(),
        ),
      ),
    );
    // 不用 pumpAndSettle:首页的转圈指示器永远在动,settle 不下来。
    await tester.pump();
    await tester.pump();
  }

  /// 某一屏**自己**还参不参与共享元素过渡 —— 看它外面那层 `HeroMode`。
  ///
  /// **必须 `skipOffstage: false`**:`IndexedStack` 的元素只把选中的那一个
  /// 当作 onstage(`_RenderIndexedStackElement.debugVisitOnstageChildren`),
  /// 被保活的其他 tab 默认会被 finder 跳过 —— 而它们**恰恰还在元素树里**,
  /// 这正是这一组要守的那件事。
  bool heroEnabledFor(WidgetTester tester, Type screen) => tester
      .widget<HeroMode>(
        find.ancestor(
          of: find.byType(screen, skipOffstage: false),
          matching: find.byType(HeroMode, skipOffstage: false),
        ),
      )
      .enabled;

  /// 底部胶囊上的某颗 tab。**必须限定在托盘里** —— 音乐库那屏的顶栏
  /// 标题也叫「音乐库」。
  Finder tabButton(String label) =>
      find.descendant(of: find.byType(BottomStack), matching: find.text(label));

  testWidgets('每个 tab 一层 HeroMode —— 只有屏幕上那一屏参与共享元素过渡', (tester) async {
    await pumpShell(tester, playingController(playing));

    // 没露过面的 tab 还没建,所以此刻只有首页那一层,而且是开着的。
    expect(find.byType(HeroMode), findsOneWidget);
    expect(heroEnabledFor(tester, HomeScreen), isTrue);

    await tester.tap(tabButton('音乐库'));
    await tester.pump();
    await tester.pump();

    // 音乐库建起来了,首页**被保活但退出了**共享元素过渡 ——
    // 这就是「点坞时封面被看不见的网格偷走」的根因。
    expect(heroEnabledFor(tester, HomeScreen), isFalse);
    expect(heroEnabledFor(tester, LibraryScreen), isTrue);

    await tester.tap(tabButton('设置'));
    await tester.pump();
    await tester.pump();

    expect(heroEnabledFor(tester, LibraryScreen), isFalse);
    expect(heroEnabledFor(tester, SettingsScreen), isTrue);
    expect(tester.takeException(), isNull);
  });

  /// 切 tab 那一层淡入用的**就是播放页进出那个常量**(`NordicMotion.screenFade`)。
  ///
  /// 2026-10-18 用户要求「进播放页用切 tab 那套动画」—— 两处各写一个字面量迟早漂开
  /// (一边改了另一边不知道)。`app_test` 那一组验的是播放页那条路由,这一条验的是
  /// 主壳这一层,两边合起来才说明「同一套」。
  testWidgets('切 tab 的淡入与播放页进出是同一个时长、同一根缓动', (tester) async {
    await pumpShell(tester, playingController(playing));

    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(IndexedStack),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    final curve = fade.opacity as CurvedAnimation;

    expect((curve.parent as AnimationController).duration,
        NordicMotion.screenFade);
    expect(curve.curve, NordicMotion.ease);
    expect(tester.takeException(), isNull);
  });

  testWidgets('按住播放坞会亮一层底色，松手撤掉，抬手进播放页', (tester) async {
    await pumpShell(tester, playingController(playing));

    // 坞里的曲名 —— 限定在托盘里取:首页那张「正在播放」卡上也有同一个歌名。
    final dockText = find.descendant(
      of: find.byType(BottomStack),
      matching: find.text(playing.title),
    );
    final dock = find.ancestor(of: dockText, matching: find.byType(Pressable));
    expect(dock, findsOneWidget, reason: '坞该是一整条可点区域');

    // 裸 `GestureDetector` 没有按下反馈 —— 这一条最容易被打回原形。
    expect(tester.widget<Pressable>(dock).pressedDecoration, isNotNull);

    /// 坞自己那层底色(它直接包在 `Pressable` 的 `DecoratedBox` 上,
    /// 深度优先里排在封面那层 `Container` 前面)。
    BoxDecoration fill() => tester
        .widget<DecoratedBox>(
          find.descendant(of: dock, matching: find.byType(DecoratedBox)).first,
        )
        .decoration as BoxDecoration;

    expect(fill().color, isNull, reason: '没按下时不该有底色');

    final gesture = await tester.startGesture(tester.getCenter(dockText));
    // 要**过 `kPressTimeout`(100ms)那一下**:坞上面还压着主壳那层
    // 「点空白收起键盘」的 tap 识别器,手势竞技场不会在按下那一刻就判给坞,
    // `onTapDown` 于是要等 deadline。
    await tester.pump(const Duration(milliseconds: 150));
    expect(fill().color, NordicTokens.dark.fill1, reason: '按下去要亮一层');

    await gesture.up();
    await tester.pump();
    expect(fill().color, isNull, reason: '松手要撤掉，不能一直亮着');

    // 抬手这一下就是「点了坞」—— 路由名收在一处,应该真的推到播放页。
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}