import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/theme/accent.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/theme_mode.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/routes.dart';
import 'package:nordic/ui/screens/lyrics_screen.dart';
import 'package:nordic/ui/shell/bottom_stack.dart';
import 'package:nordic/ui/widgets/components.dart';
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
    // 设了 cacheWidth/cacheHeight 之后 Flutter 会用 ResizeImage 包一层,
    // 认里面那个才是「走的是哪条路」。
    expect(_inner(image.image), isA<FileImage>());
    // 而且**必须**设了尺寸:那张图在本机是 1024,这里只画 46。
    expect(image.image, isA<ResizeImage>());
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
    // 网络那一份走**磁盘缓存**(cached_network_image):URL 每次请求都带新的
    // salt,所以它的键另有算法(封面 id + 尺寸),不是 URL 本身。
    expect(image.image, isA<CachedNetworkImageProvider>());
  });

  group('底部胶囊', () {
    // 只造胶囊本身(`showDock: false`),不造播放坞 —— 坞背后是一个真的
    // AudioPlayer,而 widget 测试的 FakeAsync 里等不到平台侧的回话。
    // 坞的行为由 `test/playback/playback_test.dart` 与真机承担。
    Widget harness({required AppTab? active, required bool showDock}) =>
        MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: Scaffold(
            body: Stack(
              children: [
                BottomStack(
                  activeTab: active,
                  showDock: showDock,
                  onTabSelected: (tab) => pendingTab.value = tab,
                ),
              ],
            ),
          ),
        );

    setUp(() => pendingTab.value = null);

    testWidgets('三颗 tab 都在;不属于任何 tab 的页面谁都不高亮', (tester) async {
      // 专辑 / 艺人 / 服务器 / 歌单这几屏浮的就是这一颗(见 ImmersiveScaffold
      // 的 showNav),它们不属于任何一个 tab。
      await tester.pumpWidget(harness(active: null, showDock: false));

      for (final label in ['音乐库', '搜索', '设置']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(pendingTab.value, isNull);
    });

    testWidgets('点胶囊上的 tab 会请主壳切过去', (tester) async {
      await tester.pumpWidget(harness(active: AppTab.library, showDock: false));

      await tester.tap(find.text('搜索'));
      await tester.pump();

      expect(pendingTab.value, AppTab.search);
    });
  });

  group('没有时间轴的歌词', () {
    // 服务端多数时候给带 `start` 的结构化歌词(实测 52 首里 51 首都有),
    // 但没有的时候只能按整首进度平均摊 —— 这一条钉住摊法本身。
    test('按整首的进度摊行', () {
      const hundred = Duration(seconds: 100);
      expect(
        averageIndexFor(position: Duration.zero, duration: hundred, lineCount: 10),
        0,
      );
      expect(
        averageIndexFor(position: const Duration(seconds: 50), duration: hundred, lineCount: 10),
        5,
      );
      // 末尾夹在最后一行里,别越界。
      expect(
        averageIndexFor(position: hundred, duration: hundred, lineCount: 10),
        9,
      );
    });

    test('时长未知时停在第一行,不假装知道进度', () {
      expect(
        averageIndexFor(
          position: const Duration(seconds: 30),
          duration: Duration.zero,
          lineCount: 9,
        ),
        0,
      );
    });

    test('一行都没有时给 -1(界面据此不高亮)', () {
      expect(
        averageIndexFor(
          position: Duration.zero,
          duration: const Duration(seconds: 10),
          lineCount: 0,
        ),
        -1,
      );
    });
  });

  group('封面解码尺寸', () {
    testWidgets('「无限宽」的封面按真实约束解码,不再一路算到 1024', (tester) async {
      // 网格里的封面就是这么传的(`width: double.infinity`)—— 声明尺寸算不出
      // 边长。修之前 `_displayEdge` 得到 Infinity,桶永远是 1024(下载到本机的
      // 那张封面就是 1024,于是每格都按原尺寸解码)。
      await tester.pumpWidget(
        MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: Cover(
                coverArtId: 'cover-1',
                seed: 'al-1',
                uri: Uri.parse(
                  'http://nas.example.com/rest/getCoverArt.view?id=cover-1',
                ),
                width: double.infinity,
              ),
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as CachedNetworkImageProvider;
      expect(provider.maxWidth, isNotNull);
      expect(provider.maxWidth, lessThan(1024), reason: '100 的格子不该按 1024 解');
    });
  });

  group('页面过渡', () {
    /// 播放页 ↔ 歌词页是同一个播放对象的两面,切换要「直接变」。
    /// 这一条钉住它 —— 免得哪天顺手把它们也塞回统一的滑入里。
    test('歌词页:直接换,不滑也不飞', () {
      final route =
          AppRoutes.generate(const RouteSettings(name: AppRoutes.lyrics));

      expect(route, isA<PageRouteBuilder<dynamic>>());
      final page = route! as PageRouteBuilder;
      expect(page.transitionDuration, Duration.zero);
      expect(page.reverseTransitionDuration, Duration.zero,
          reason: '点歌词回封面也要一样直接,不然来路去路手感不一致');
    });

    test('专辑 / 艺人 / 歌单仍是滑入 —— 它们不是「翻面」而是进另一个页面', () {
      for (final name in [AppRoutes.album, AppRoutes.artist, AppRoutes.playlist]) {
        final route = AppRoutes.generate(
          RouteSettings(name: name, arguments: 'x'),
        );
        expect(route, isA<PageRouteBuilder<dynamic>>());
        expect((route! as PageRouteBuilder).transitionDuration,
            greaterThan(Duration.zero),
            reason: '$name 该滑入');
      }
    });
  });

  group('线路信号条', () {
    test('延迟越短亮的根数越多 —— 门槛照内网 / 公网的实感定', () {
      expect(SignalBars.forLatency(const Duration(milliseconds: 8)), 4);
      expect(SignalBars.forLatency(const Duration(milliseconds: 30)), 4);
      expect(SignalBars.forLatency(const Duration(milliseconds: 60)), 3);
      expect(SignalBars.forLatency(const Duration(milliseconds: 150)), 2);
      expect(SignalBars.forLatency(const Duration(milliseconds: 400)), 1);
      expect(SignalBars.forLatency(const Duration(seconds: 2)), 0);
    });

    test('没测出延迟时一根不亮 —— 不亮比亮错一根强', () {
      expect(SignalBars.forLatency(null), 0);
    });
  });
}

/// 剥掉 `ResizeImage` 那层包装(设了 cacheWidth 就会有)。
ImageProvider _inner(ImageProvider provider) =>
    provider is ResizeImage ? provider.imageProvider : provider;
