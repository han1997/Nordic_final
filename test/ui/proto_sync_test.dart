import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
import 'package:nordic/theme/glass.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/adaptive/window.dart';
import 'package:nordic/ui/shell/bottom_stack.dart';
import 'package:nordic/ui/shell/nav_rail.dart';
import 'package:nordic/ui/shell/nav_tabs.dart';
import 'package:nordic/ui/shell/wide_bar.dart';
import 'package:nordic/ui/widgets/components.dart';
import 'package:nordic/ui/widgets/cover.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_playback.dart';

/// **常驻导航区的「原型 ↔ 应用」对账**(2026-10-24 第三十二轮立)。
///
/// 原型是唯一的设计真相来源,而这一片是改动最频繁的地方:同一个数写在两边,
/// 谁顺手改了一边,另一边不会出声 —— 前几轮那几处漂开(坞里的缝、托盘的
/// 进度线、宽屏的底部留白)正是这么来的,见 `docs/CHANGELOG.md` 第三十二轮。
///
/// 这一组把 `prototype/styles.css` 的原文读进来,和应用**实际渲染出来的几何**
/// 逐条比 —— 比的是渲染结果,不是代码里的字面量:
///   1. 托盘:左右 20 / 下 10、r-xl、深度影 `0 20px 40px -20px`;
///   2. 托盘那条分隔线:2 高、左右 `--s4`、`--fill-2` 底槽 + 8px 的光;
///   3. 坞:60 高、8 内衬、每一格 12 的缝、封面 46 / 13;
///   4. 标签栏:58 / 药丸 50 / 内衬与内缩各 20;选中胶囊那两道 1px 内描边;
///   5. 左竖栏:10 / 84 / 8 / 4,按钮 68 × 52;
///   6. 宽屏:让位 104、横条 72 / 内衬 12 / 封面 48 / 14、进度两侧各 24、
///      底部留白 94。
///
/// 改原型 → 改应用;只改一边,这一组就红。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------------ 原型
  final css = File('prototype/styles.css').readAsStringSync();
  final js = File('prototype/app.js').readAsStringSync();
  final wideAt = css.indexOf('@container (min-width: 840px)');

  /// 取出某个选择器的声明块。**注释先去掉** —— 里面也有 `}` 与 `:`;
  /// 选择器允许有缩进(宽屏那一档的规则都缩在容器查询里)。
  String decls(String selector, {int from = 0}) {
    final m = RegExp('\\n[ \\t]*${RegExp.escape(selector)} \\{')
        .firstMatch(css.substring(from));
    expect(m, isNotNull,
        reason: 'prototype/styles.css 里找不到 `$selector {` —— 选择器改名了？');
    final at = from + m!.end;
    final chunk = css
        .substring(at, math.min(css.length, at + 2000))
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    return chunk.substring(0, chunk.indexOf('}'));
  }

  /// 一条声明的值(`padding` / `background` …)。
  String prop(String block, String name) {
    final m = RegExp('(?:^|\\n|;)[ \\t]*$name: *([^;]+)').firstMatch(block);
    expect(m, isNotNull, reason: '声明块里找不到 `$name`:');
    return m!.group(1)!.trim();
  }

  /// 把一段值解析成数:裸 px、光秃秃的 `0`,或 `var(--sN)` 这类令牌。
  double num_(String raw) {
    final t = RegExp(r'var\((--[a-z0-9-]+)\)').firstMatch(raw);
    if (t != null) {
      final m = RegExp('${t.group(1)}: *([0-9.]+)px').firstMatch(css);
      expect(m, isNotNull, reason: '原型里没有令牌 ${t.group(1)}');
      return double.parse(m!.group(1)!);
    }
    final m = RegExp(r'(-?[0-9.]+)px').firstMatch(raw) ??
        RegExp(r'^(-?[0-9.]+)$').firstMatch(raw.trim());
    expect(m, isNotNull, reason: '这段值里没有数：$raw');
    return double.parse(m!.group(1)!);
  }

  /// 一条 px 声明(`height: 58px` → 58)。
  double px(String block, String name) => num_(prop(block, name));

  /// `padding` / `margin` 的多值写法 → 上右下左四条。
  List<double> box(String block, String name) {
    final parts = prop(block, name).split(RegExp(r'\s+'));
    return switch (parts.length) {
      2 => [num_(parts[0]), num_(parts[1]), num_(parts[0]), num_(parts[1])],
      3 => [num_(parts[0]), num_(parts[1]), num_(parts[2]), num_(parts[1])],
      4 => parts.map(num_).toList(),
      _ => List.filled(4, num_(parts[0])),
    };
  }

  // **late**:这些块在第一个用例里才真的去读原型 —— 解析与断言都留在
  // 用例的作用域里(expect 在 main 的顶层会被判成「测试之外」)。
  late final bottomstack = decls('.bottomstack');
  late final tray = decls('.tray');
  late final trayLine = decls('.tray-line');
  late final trayLineFill = decls('.tray-line i');
  late final dock = decls('.dock');
  late final dockCover = decls('.dock .cover');
  late final tabbar = decls('.tabbar');
  late final tabButton = decls('.tabbar button');
  late final tabSelected = decls('.tabbar button[aria-selected="true"]');
  late final panel = decls('.glass-panel');
  late final rail = decls('.railnav');
  late final railButton = decls('.railnav button');
  late final wideDock = decls('.dock', from: wideAt);
  late final wideCover = decls('.dock .cover', from: wideAt);
  late final wideProg = decls('.dock .prog-inline', from: wideAt);
  late final wideScroll = decls('.screen:has(.bottomstack) .scroll', from: wideAt);

  // ------------------------------------------------------------------ 夹具
  const song = Song(
    id: 's-1',
    title: '对账用的歌',
    artist: '艺人',
    album: '专辑',
    albumId: 'al-1',
    coverArtId: 'c-1',
    duration: Duration(seconds: 200),
  );

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
    root = await Directory.systemTemp.createTemp('nordic-proto-sync');
    quality = QualityController();
    // late 局部变量:下载器读应用状态、应用状态持有下载器(与 main.dart 同套)。
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
  });

  tearDown(() async {
    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } on FileSystemException {
      // Windows 上临时目录偶尔被抢住 —— 系统自己会清。
    }
  });

  /// 把常驻区那几件浮在 `Stack` 里渲染出来(托盘 / 竖栏 / 横条都是 Positioned)。
  Future<void> pump(WidgetTester tester, Widget child, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final playback = playingController(song);
    addTearDown(() {
      playback.dispose();
      playback.handler.player.dispose();
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<PlaybackController>.value(value: playback),
        ChangeNotifierProvider<QualityController>.value(value: quality),
      ],
      child: MaterialApp(
        theme: NordicTheme.build(NordicTokens.dark),
        home: Scaffold(body: Stack(children: [child])),
      ),
    ));
    await tester.pump();
  }

  Widget trayAt(AppTab active) =>
      BottomStack(activeTab: active, onTabSelected: (_) {});

  /// 坞 / 横条里那一行(Row)。
  Finder dockRow() => find
      .ancestor(of: find.byType(Cover), matching: find.byType(Row))
      .first;

  /// 那一行里放歌名 / 艺人的那一段(坞与横条共用一套排版)。
  Rect textBlock(WidgetTester tester) => tester.getRect(
        find.descendant(of: dockRow(), matching: find.byType(Column)).first,
      );

  /// 一件玻璃的圆角与深度影(影画在裁剪外面那层 DecoratedBox 上)。
  BoxDecoration glassDecoration(WidgetTester tester) => tester
      .widget<DecoratedBox>(find
          .ancestor(of: find.byType(BackdropFilter), matching: find.byType(DecoratedBox))
          .first)
      .decoration as BoxDecoration;

  // ------------------------------------------------------------------ 用例
  testWidgets('托盘：左右 20 / 下 10、r-xl、深度影 0 20 40 -20', (tester) async {
    await pump(tester, trayAt(AppTab.home), const Size(390, 844));

    final pad = box(bottomstack, 'padding');
    expect(pad[1], BottomStack.trayMargin, reason: '.bottomstack 的左右留白');
    expect(pad[1], NordicSpace.s5);

    final glass = tester.getRect(find.byType(NordicGlass));
    expect(glass.left, pad[1]);
    expect(390 - glass.right, pad[3]);
    expect(844 - glass.bottom, pad[2], reason: '.bottomstack 的下留白');

    expect(prop(tray, 'border-radius'), 'var(--r-xl)');
    expect(num_(prop(tray, 'border-radius')), NordicRadius.xl);
    final decoration = glassDecoration(tester);
    expect(decoration.borderRadius, BorderRadius.circular(NordicRadius.xl),
        reason: '两行的那块做成胶囊，上下缘会鼓得像药丸');

    expect(prop(tray, 'box-shadow').replaceAll(RegExp(r'\s+'), ' '),
        'inset 0 1px 0 var(--glass-rim), 0 20px 40px -20px var(--depth)');
    final shadow = decoration.boxShadow!.single;
    expect(shadow.offset, const Offset(0, 20));
    expect(shadow.blurRadius, 40);
    expect(shadow.spreadRadius, -20, reason: '少了这个负数，影会在四周散成一大圈灰');
    expect(shadow.color, NordicTokens.dark.depth);
  });

  testWidgets('托盘那条分隔线：2 高 / 左右 --s4 / --fill-2 底槽 + 8px 的光', (tester) async {
    await pump(tester, trayAt(AppTab.home), const Size(390, 844));

    expect(px(trayLine, 'height'), 2);
    expect(box(trayLine, 'margin')[1], NordicSpace.s4);
    expect(prop(trayLine, 'background'), 'var(--fill-2)');

    final glass = tester.getRect(find.byType(NordicGlass));
    final line = tester.getRect(find.byType(ProgressLine));
    expect(line.height, px(trayLine, 'height'));
    expect(line.left - glass.left, NordicSpace.s4, reason: 'margin: 0 var(--s4)');
    expect(glass.right - line.right, NordicSpace.s4);
    expect(line.width, glass.width - NordicSpace.s4 * 2,
        reason: '这条线铺满托盘（块级），不是按进度自己收窄 —— 收窄的话底槽整段会消失');

    final fills = tester
        .widgetList<ColoredBox>(find.descendant(
          of: find.byType(ProgressLine),
          matching: find.byType(ColoredBox),
        ))
        .map((w) => w.color)
        .toList();
    expect(fills, contains(NordicTokens.dark.fill2));
    expect(fills, isNot(contains(NordicTokens.dark.fill3)),
        reason: '托盘这条是 .tray-line(--fill-2)，不是 .prog-line(--fill-3)');

    // 亮条末端那圈光 —— 原型里只有这一条有。
    expect(prop(trayLineFill, 'box-shadow').replaceAll(RegExp(r'\s+'), ' '),
        contains('0 0 8px'));
    final glow = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(ProgressLine),
          matching: find.byType(DecoratedBox),
        ))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.boxShadow != null)
        .single;
    expect(glow.boxShadow!.single.blurRadius, 8);
    expect(glow.boxShadow!.single.color.a, closeTo(0.8, 0.01));
  });

  testWidgets('坞：60 高 / 8 内衬 / 每一格 12 的缝 / 封面 46 · 13', (tester) async {
    await pump(tester, trayAt(AppTab.home), const Size(390, 844));

    final row = tester.getRect(dockRow());
    expect(row.height, px(dock, 'height'), reason: '.dock { height: 60px }');
    final glass = tester.getRect(find.byType(NordicGlass));

    final pad = box(dock, 'padding');
    expect(pad[1], pad[3], reason: '`.dock { padding: 0 8px }` 左右对称');
    expect(row.width, glass.width - pad[1] - pad[3]);

    final cover = tester.widget<Cover>(find.byType(Cover));
    expect(cover.size, px(dockCover, 'width'));
    expect(cover.radius, num_(prop(dockCover, 'border-radius')));

    // **每一格之间都是同一个数** —— 原型 `.dock { gap: var(--s3) }`。
    final gap = num_(prop(dock, 'gap'));
    expect(gap, NordicSpace.s3);
    final coverRect = tester.getRect(find.byType(Cover));
    final text = textBlock(tester);
    final keys = [
      for (var i = 0; i < 2; i++) tester.getRect(find.byType(IconButtonRound).at(i)),
    ];
    expect(text.left - coverRect.right, gap, reason: '封面 → 歌名');
    expect(keys[0].left - text.right, gap, reason: '歌名 → 播放键');
    expect(keys[1].left - keys[0].right, gap, reason: '播放键 → 下一首');

    expect(coverRect.left - glass.left, pad[3], reason: '坞的左右内衬（量到玻璃内缘）');
    expect(glass.right - keys[1].right, pad[1]);
    expect(find.byType(IconButtonRound), findsNWidgets(2),
        reason: '手机这一档坞里只有播放键与下一首（上一首是宽屏那档才有的）');
  });

  testWidgets('标签栏：58 / 药丸 50 / 内衬与内缩各 20；选中胶囊有两道 1px 内描边', (tester) async {
    await pump(tester, trayAt(AppTab.home), const Size(390, 844));

    final row = tester.getRect(find.ancestor(
      of: find.byType(NavTabButton).first,
      matching: find.byType(Row),
    ).first);
    expect(row.height, px(tabbar, 'height'));
    expect(px(tabButton, 'height'), 50);

    final glass = tester.getRect(find.byType(NordicGlass));
    final pills = [
      for (var i = 0; i < AppTab.values.length; i++)
        tester.getRect(find.byType(NavTabButton).at(i)),
    ];
    expect(pills[0].height, px(tabButton, 'height'));
    // 托盘留白 → 标签栏内衬 → 药丸内缩,三段同一个数(见 .tabbar 的注释)。
    expect(row.left - glass.left, box(tabbar, 'padding')[1]);
    expect(pills[0].left - row.left, box(tabButton, 'margin')[1]);
    expect(pills[0].left - glass.left,
        box(tabbar, 'padding')[1] + box(tabButton, 'margin')[1]);
    expect(pills[1].left - pills[0].right, closeTo(box(tabButton, 'margin')[1] * 2, 0.01),
        reason: '三颗之间那道缝是两侧内缩之和（三等分除不尽）');
    expect(box(tabbar, 'padding')[1], NordicSpace.s5);
    expect(box(tabButton, 'margin')[1], NordicSpace.s5);

    // 选中态:强调色 17% 的底 + 上下各一道 1px 的内描边。
    expect(prop(tabSelected, 'background').replaceAll(RegExp(r'\s+'), ' '),
        'color-mix(in srgb, var(--accent) 17%, transparent)');
    expect(selectFill(const Color(0xFF7C9EFF)).a, closeTo(0.17, 0.01));

    final home = find.byType(NavTabButton).at(AppTab.home.index);
    final edges = tester
        .widgetList<ColoredBox>(
            find.descendant(of: home, matching: find.byType(ColoredBox)))
        .toList();
    expect(edges.length, 2, reason: '上缘一道 glass-rim、下缘一道 glass-sh');
    expect(edges.map((w) => w.color).toSet(),
        {NordicTokens.dark.glassRim, NordicTokens.dark.glassShadow});
    for (final edge in edges) {
      expect(tester.getSize(find.byWidget(edge)).height, 1);
    }
    expect(
      find.descendant(
        of: find.byType(NavTabButton).at(AppTab.settings.index),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
      reason: '没选中的那颗不该有这两道线',
    );
  });

  testWidgets('左竖栏：左 10 / 宽 84 / 内衬 8 / 缝 4，按钮 68 × 52', (tester) async {
    await pump(
      tester,
      NordicNavRail(activeTab: AppTab.home, onTabSelected: (_) {}),
      const Size(1280, 800),
    );

    final frame = tester.getRect(find.byType(NordicNavRail));
    expect(frame.left, num_(prop(rail, 'left')));
    expect(frame.width, px(rail, 'width'));

    final panel_ = tester.getRect(find.byType(NordicGlass));
    expect(panel_.width, px(rail, 'width'));
    final pad = box(rail, 'padding');
    final button = tester.getRect(find.byType(NavTabButton).first);
    expect(button.left - panel_.left, pad[3]);
    expect(button.width, px(railButton, 'width'));
    expect(button.height, px(railButton, 'height'));

    final buttons = [
      for (var i = 0; i < AppTab.values.length; i++)
        tester.getRect(find.byType(NavTabButton).at(i)),
    ];
    final gap = num_(prop(rail, 'gap'));
    expect(buttons[1].top - buttons[0].bottom, gap);
    // 面板按内容收口(不是一根通到屏底的柱子)。
    expect(panel_.height, pad[0] * 2 + button.height * 3 + gap * 2);
  });

  testWidgets('宽屏横条：72 / 内衬 12 / 封面 48 · 14 / 进度两侧各 24', (tester) async {
    await pump(tester, const WidePlaybackBar(), const Size(1280, 800));

    final glass = tester.getRect(find.byType(NordicGlass));
    expect(glass.height, px(wideDock, 'height'), reason: '宽屏档 .dock { height: 72px }');
    expect(glass.height, NordicWindow.barHeight);
    expect(glass.left, NordicWindow.gutter, reason: '左缘从 104 起，与 .screen 的让位对齐');

    final pad = box(wideDock, 'padding');
    // 横条自己那条:宽屏档 `.bottomstack { left: 104px; padding: 0 10px 10px 0 }`
    // —— 右 / 下各 10(与屏幕边距对齐,不再带手机那 20)。
    final barPad =
        box(decls('.screen:has(> .railnav) .bottomstack', from: wideAt), 'padding');
    expect(1280 - glass.right, barPad[1]);
    expect(800 - glass.bottom, barPad[2]);
    expect(barPad[2], NordicWindow.railMargin);

    final cover = tester.widget<Cover>(find.byType(Cover));
    expect(cover.size, px(wideCover, 'width'));
    expect(cover.radius, num_(prop(wideCover, 'border-radius')));

    final coverRect = tester.getRect(find.byType(Cover));
    expect(coverRect.left - glass.left, pad[3]);
    // 宽屏那一档只覆写 height 与 padding —— `gap` 照旧继承基础那条 `.dock`
    // (CSS 的层叠如此,应用侧也就不该另立一个数)。
    final gap = num_(prop(dock, 'gap'));
    expect(gap, NordicSpace.s3);

    final text = textBlock(tester);
    expect(text.left - coverRect.right, gap, reason: '封面 → 歌名');

    // 进度两侧**各 24**:坞的 gap 12 加上 `.prog-inline` 自己的 margin 12。
    final margin = num_(prop(wideProg, 'margin').split(RegExp(r'\s+'))[1]);
    final line = tester.getRect(find.byType(ProgressLine));
    expect(line.left - text.right, gap + margin, reason: '歌名 → 进度');
    expect(px(wideProg, 'height'), 2);
    expect(line.height, 2);

    final keys = tester
        .widgetList<IconButtonRound>(find.byType(IconButtonRound))
        .toList();
    expect(keys.length, 3);
    expect(keys[0].iconSize, 25, reason: '上一首（原型坞里那颗是 25)');
    expect(keys[1].iconSize, 25);
    expect(keys[2].iconSize, 23);
    final keyRects = [
      for (var i = 0; i < 3; i++)
        tester.getRect(find.byType(IconButtonRound).at(i)),
    ];
    expect(keyRects[0].left - line.right, gap + margin, reason: '进度 → 上一首');
    expect(keyRects[1].left - keyRects[0].right, gap);
    expect(keyRects[2].left - keyRects[1].right, gap);
    expect(glass.right - keyRects[2].right, pad[1]);
  });

  test('两档底部留白与宽屏的几个数：窄 150 / 宽 94 / 让位 104', () {
    expect(prop(decls('.screen:has(.bottomstack) .scroll'), 'padding-bottom'), '150px');
    expect(BottomStack.bottomInset, 150);
    expect(box(wideScroll, 'padding-bottom')[0], NordicWindow.barInset);
    expect(NordicWindow.barInset, 94, reason: '原型宽屏档写的是 94');
    expect(px(wideDock, 'height'), NordicWindow.barHeight);
    expect(css.contains('padding-left: ${NordicWindow.gutter.toInt()}px'), isTrue);
    expect(js.contains('phoneW < ${NordicWindow.expandedMin.toInt()}'), isTrue);
  });

  test('玻璃的深度影：两档都是原型那一串（含负的 spread）', () {
    expect(prop(panel, 'box-shadow').replaceAll(RegExp(r'\s+'), ' '),
        'inset 0 1px 0 var(--glass-rim), inset 0 0 0 0.5px var(--glass-sh), '
        '0 18px 40px -24px var(--depth)');
  });
}

