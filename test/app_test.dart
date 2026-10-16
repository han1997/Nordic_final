import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/theme/accent.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/theme_mode.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/shell/bottom_stack.dart';
import 'package:nordic/ui/shell/shell.dart';
import 'package:nordic/ui/widgets/cover.dart';

/// 主题层的用例。
///
/// 刻意**不**整树 pump `NordicApp`:它下方的一级页面要
/// [PlaybackController](audio_service 的处理器),而处理器在测试环境里
/// 没有平台通道。为一个主题测试去造一份假的播放层,测的就不是主题了。
/// 主题相关的行为(默认档、token 注入、材质差异)下面这几条都能直接验到。
void main() {
  testWidgets('默认走深色 —— 这套设计的主场是近黑底 + 封面光晕', (tester) async {
    // 没存过偏好时 byName(null) 应回深色,而不是跟随系统。
    expect(NordicThemeMode.byName(null), NordicThemeMode.dark);
    expect(NordicThemeMode.byName('没这个档'), NordicThemeMode.dark);
    // 显式存过的档要照实还原。
    expect(NordicThemeMode.byName('light'), NordicThemeMode.light);
    expect(NordicThemeMode.byName('follow'), NordicThemeMode.follow);
  });

  testWidgets('两套主题都装上了 NordicTokens extension', (tester) async {
    for (final tokens in [NordicTokens.dark, NordicTokens.light]) {
      final theme = NordicTheme.build(tokens);
      expect(theme.extension<NordicTokens>(), same(tokens));
      expect(theme.brightness, tokens.brightness);
    }
  });

  testWidgets('沉浸页外壳把强调色挂进了作用域', (tester) async {
    final accent = NordicAccent.derived('album-1');
    late BuildContext inner;

    await tester.pumpWidget(
      MaterialApp(
        theme: NordicTheme.build(NordicTokens.dark),
        home: ImmersiveScaffold(
          accent: accent,
          child: Builder(builder: (context) {
            inner = context;
            return const SizedBox.shrink();
          }),
        ),
      ),
    );

    // 页面内任意深度都能拿到同一个强调色 —— 这正是「随封面取色」
    // 能遍布整屏的机制。在 pump 之后取 context,不在 build 里比 ——
    // build 期间 inherited widget 的注册尚未完成。
    expect(NordicAccentScope.of(inner), accent);
  });

  testWidgets('AppBar 的大标题与窄标题都不溢出', (tester) async {
    for (final big in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: Scaffold(
            appBar: NordicAppBar(
              title: '音乐库',
              subtitle: big ? 'HomeMusic · 531 首' : null,
              big: big,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 溢出时 Flutter 会把异常塞进 takeException,这里必须为空。
      expect(tester.takeException(), isNull, reason: 'big=$big 时标题栏不应溢出');
    }
  });

  testWidgets('封面认 file:// —— 下载过的封面断网也要显出来', (tester) async {
    // 用一个不存在的路径:Image.file 会走 errorBuilder 退回渐变兜底,
    // 但树里那一层仍是 FileImage。这里验的是「有没有走本机这条路」,
    // 走错了会变成 Image.network(把一个本地路径当网址发出去)。
    await tester.pumpWidget(
      MaterialApp(
        theme: NordicTheme.build(NordicTokens.dark),
        home: Cover(
          coverArtId: 'cover-1',
          seed: 'al-1',
          uri: Uri.file('/tmp/nordic-不存在的封面.jpg'),
          size: 80,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
  });

  testWidgets('没下过的封面照旧走网络', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NordicTheme.build(NordicTokens.dark),
        home: Cover(
          coverArtId: 'cover-1',
          seed: 'al-1',
          uri: Uri.parse('http://nas.example.com/rest/getCoverArt.view?id=cover-1'),
          size: 80,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
  });

  group('沉浸页上的浮动胶囊', () {
    /// 播放层可能起不来(见 main.dart 的兜底),所以坞查的是**可空**的那一份。
    /// 这里就按「没有播放层」搭一棵树 —— 顺带把那条降级路径钉住。
    Widget harness({required bool showNav, Widget? child}) => MultiProvider(
          providers: [Provider<PlaybackController?>.value(value: null)],
          child: MaterialApp(
            theme: NordicTheme.build(NordicTokens.dark),
            home: ImmersiveScaffold(
              accent: NordicAccent.derived('al-1'),
              showNav: showNav,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );

    setUp(() => pendingTab.value = null);

    testWidgets('专辑 / 艺人 / 服务器这类页面也浮着标签栏 —— 与原型一致', (tester) async {
      await tester.pumpWidget(harness(showNav: true));

      for (final label in ['音乐库', '搜索', '设置']) {
        expect(find.text(label), findsOneWidget);
      }
      // 这些屏不属于任何 tab,谁都不该高亮。
      expect(pendingTab.value, isNull);
    });

    testWidgets('不给胶囊的页面(播放 / 歌词)底下就是干净的', (tester) async {
      await tester.pumpWidget(harness(showNav: false));

      expect(find.text('音乐库'), findsNothing);
    });

    testWidgets('点胶囊上的 tab:请主壳切过去', (tester) async {
      await tester.pumpWidget(harness(showNav: true));

      await tester.tap(find.text('搜索'));
      await tester.pump();

      expect(pendingTab.value, AppTab.search);
    });

    testWidgets('没有播放层时不崩 —— 坞整个不出现', (tester) async {
      await tester.pumpWidget(harness(showNav: true));

      expect(tester.takeException(), isNull);
      // 坞不在,但标签栏还在:浏览不该因为播放服务起不来而瘫痪。
      expect(find.text('设置'), findsOneWidget);
    });
  });
}
