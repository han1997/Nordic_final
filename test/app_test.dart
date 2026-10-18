import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/theme/accent.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/theme_mode.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/routes.dart';
import 'package:nordic/ui/screens/album_screen.dart';
import 'package:nordic/ui/screens/lyrics_screen.dart';
import 'package:nordic/ui/shell/bottom_stack.dart';
import 'package:nordic/ui/widgets/album_rail.dart';
import 'package:nordic/ui/widgets/components.dart';
import 'package:nordic/ui/widgets/playback_controls.dart';
import 'package:nordic/ui/shell/shell.dart';
import 'package:nordic/ui/widgets/cover.dart';
import 'package:nordic/ui/widgets/rows.dart';

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

    testWidgets('三颗 tab 都在；不属于任何 tab 的页面谁都不高亮', (tester) async {
      // 专辑 / 艺人 / 服务器 / 歌单这几屏浮的就是这一颗(见 ImmersiveScaffold
      // 的 showNav),它们不属于任何一个 tab。
      //
      // 首页取代了原先的搜索 tab(2026-10-17):搜索是「知道要找什么」时的动作,
      // 用完就退,常驻位置留给「不知道听什么」时的落点。
      await tester.pumpWidget(harness(active: null, showDock: false));

      for (final label in ['首页', '音乐库', '设置']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('搜索'), findsNothing, reason: '搜索不再是常驻 tab');
      expect(pendingTab.value, isNull);
    });

    testWidgets('点胶囊上的 tab 会请主壳切过去', (tester) async {
      await tester.pumpWidget(harness(active: AppTab.library, showDock: false));

      await tester.tap(find.text('首页'));
      await tester.pump();

      expect(pendingTab.value, AppTab.home);
    });

    testWidgets('搜索不再是 tab —— 它靠 push 进来，不依赖主壳在场', (tester) async {
      // 原先这条路是一个全局 ValueNotifier 通知主壳换 tab,而那条线**断过一次**
      // (有人发没人听,顶栏放大镜成了死按钮)。搜索能独立成页之后,
      // 「点它会不会有反应」不再取决于主壳在不在。
      // 三个一级 tab 里没有「搜索」这一格 —— 它靠 push 进来(见 `AppRoutes.search`),
      // 不占常驻位置(2026-10-17 用户要求,那一格给了首页)。
      expect(AppTab.values.map((t) => t.label), isNot(contains('搜索')));
      expect(AppRoutes.generate(
        const RouteSettings(name: AppRoutes.search),
      ), isNotNull);
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

    test('时长未知时停在第一行，不假装知道进度', () {
      expect(
        averageIndexFor(
          position: const Duration(seconds: 30),
          duration: Duration.zero,
          lineCount: 9,
        ),
        0,
      );
    });

    test('一行都没有时给 -1（界面据此不高亮）', () {
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

  group('当前该高亮哪一句', () {
    // 这一条同时管着两件事:高亮落在哪一行,以及**歌词页要不要重建整屏**
    // (位置每秒跳好几次,只有换行那几跳值得重画 —— 见 lyrics_screen 的
    // `_onPosition`)。所以它自己的边界要钉住。
    Lyrics synced(List<int?> starts) => Lyrics(
          lines: [
            for (var i = 0; i < starts.length; i++)
              LyricLine(
                text: '第 $i 句',
                start: starts[i] == null ? null : Duration(seconds: starts[i]!),
              ),
          ],
          synced: true,
        );

    int at(Lyrics lyrics, int seconds) => activeLyricIndex(
          lyrics,
          Duration(seconds: seconds),
          duration: const Duration(seconds: 100),
        );

    test('取最后一个已开始的句子，不是最近的那一句', () {
      final lyrics = synced([0, 10, 20, 30]);
      expect(at(lyrics, 0), 0);
      expect(at(lyrics, 9), 0);
      expect(at(lyrics, 10), 1);
      // 句间间隙停在前一句上 —— 提前跳到下一句会读成「抢拍」。
      expect(at(lyrics, 29), 2);
      expect(at(lyrics, 99), 3);
    });

    test('同一句里位置怎么变，行号都不动 —— 这正是「不必重建」的判据', () {
      final lyrics = synced([0, 10, 20]);
      final a = at(lyrics, 12);
      final b = at(lyrics, 13);
      final c = at(lyrics, 19);
      expect([a, b, c], [1, 1, 1]);
    });

    test('没有时间轴时退回按行平均 —— 与 averageIndexFor 同一套', () {
      final lyrics = Lyrics(
        lines: [for (var i = 0; i < 10; i++) LyricLine(text: '第 $i 句')],
      );
      expect(at(lyrics, 50), 5);
    });

    test('一行都没有时给 -1（界面据此不高亮）', () {
      expect(at(const Lyrics(lines: []), 5), -1);
    });
  });

  group('点某一句跳到哪儿', () {
    Lyrics synced(List<int?> starts) => Lyrics(
          lines: [
            for (var i = 0; i < starts.length; i++)
              LyricLine(
                text: '第 $i 句',
                start: starts[i] == null ? null : Duration(seconds: starts[i]!),
              ),
          ],
          synced: true,
        );

    const duration = Duration(seconds: 100);

    Duration? target(Lyrics lyrics, int index) =>
        seekTargetForLine(lyrics, index, duration: duration);

    test('有时间轴就跳到那一句的起点', () {
      final lyrics = synced([0, 10, 20, 30]);
      expect(target(lyrics, 0), Duration.zero);
      expect(target(lyrics, 2), const Duration(seconds: 20));
    });

    test('没有时间轴就取那一行的中段 —— 起点会因浮点误差退到上一行', () {
      final lyrics = Lyrics(
        lines: [for (var i = 0; i < 10; i++) LyricLine(text: '第 $i 句')],
      );
      // 10 行、100 秒:第 3 行的中段是 35 秒。
      expect(target(lyrics, 3), const Duration(seconds: 35));
      // 起点 30 秒在浮点下会算成 2.9999999 —— 那正是「点第三句、高亮停第二句」。
      expect(target(lyrics, 3), isNot(const Duration(seconds: 30)));
    });

    test('点一句 → 高亮必须落回同一行（与 activeLyricIndex 互为逆运算）', () {
      // 这一条是这段逻辑真正的判据:两边都用「行数 / 时长」这一套比例,
      // 只要有一边改了取整方式,这里立刻翻面。
      final unsynced = Lyrics(
        lines: [for (var i = 0; i < 7; i++) LyricLine(text: '第 $i 句')],
      );
      for (var i = 0; i < unsynced.lines.length; i++) {
        final at = activeLyricIndex(
          unsynced,
          target(unsynced, i)!,
          duration: duration,
        );
        expect(at, i, reason: '点第 $i 句，高亮却落在第 $at 句');
      }

      final withAxis = synced([0, 10, 20, 30, 40]);
      for (var i = 0; i < withAxis.lines.length; i++) {
        final at = activeLyricIndex(
          withAxis,
          target(withAxis, i)!,
          duration: duration,
        );
        expect(at, i, reason: '点第 $i 句，高亮却落在第 $at 句');
      }
    });

    test('跳不到的地方给 null —— 界面据此不接这一下点击', () {
      final unsynced = Lyrics(
        lines: [for (var i = 0; i < 3; i++) LyricLine(text: '第 $i 句')],
      );
      // 没有时间轴又不知道时长:整首摊不开,点了也没处去。
      expect(
        seekTargetForLine(unsynced, 1, duration: Duration.zero),
        isNull,
      );
      expect(target(unsynced, -1), isNull);
      expect(target(unsynced, 3), isNull);
      // 有时间轴时与时长无关 —— 时长未知也跳得动。
      expect(
        seekTargetForLine(synced([0, 10]), 1, duration: Duration.zero),
        const Duration(seconds: 10),
      );
    });

    test('带着时间轴、可这一句没有起点 —— 不猜，给 null', () {
      // 服务器给的是「部分行缺 start」的混合时间轴时,按行数摊出来的那一刻
      // 与这一句真正的位置无关:跳过去只会跳到别处,而用户以为那是这句话的位置。
      final mixed = synced([0, null, 20, 30]);

      expect(target(mixed, 1), isNull, reason: '没有起点就是没有把握');
      expect(target(mixed, 2), const Duration(seconds: 20),
          reason: '有起点的那些照旧跳得动');
    });
  });

  group('封面解码尺寸', () {
    testWidgets('「无限宽」的封面按真实约束解码，不再一路算到 1024', (tester) async {
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
    test('歌词页：直接换，不滑也不飞', () {
      final route =
          AppRoutes.generate(const RouteSettings(name: AppRoutes.lyrics));

      expect(route, isA<PageRouteBuilder<dynamic>>());
      final page = route! as PageRouteBuilder;
      expect(page.transitionDuration, Duration.zero);
      expect(page.reverseTransitionDuration, Duration.zero,
          reason: '点歌词回封面也要一样直接，不然来路去路手感不一致');
    });

    test('专辑 / 艺人 / 歌单仍是滑入 —— 它们不是「翻面」而是进另一个页面', () {
      final settings = [
        RouteSettings(
            name: AppRoutes.album, arguments: (id: 'a1', heroTag: null)),
        RouteSettings(name: AppRoutes.artist, arguments: 'x'),
        RouteSettings(name: AppRoutes.playlist, arguments: 'x'),
      ];
      for (final s in settings) {
        final route = AppRoutes.generate(s);
        expect(route, isA<PageRouteBuilder<dynamic>>());
        expect((route! as PageRouteBuilder).transitionDuration,
            greaterThan(Duration.zero),
            reason: '${s.name} 该滑入');
      }
    });

    /// **起点那张封面的 tag 要随路由传到专辑页。**
    ///
    /// 专辑页的封面只能挂一个 `Hero`,而来源不止一处:音乐库的网格用
    /// `cover-{id}`,首页那两条货架各用各的前缀 —— 前缀必须逐条不同,否则同一张
    /// 专辑同时在两条货架上时,同一条路由里重名 `Hero` 会直接断言失败
    /// (见 `docs/performance.md`,真机表现是「从首页点进任何一页都崩」)。
    /// 两边要对上,唯一的办法是**起点把 tag 交给终点**。
    testWidgets('专辑路由把起点那张封面的 tag 带过去', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      AlbumScreen pageFor(String? heroTag) {
        final route = AppRoutes.generate(RouteSettings(
          name: AppRoutes.album,
          arguments: (id: 'a1', heroTag: heroTag),
        ))! as PageRouteBuilder<dynamic>;
        const still = AlwaysStoppedAnimation<double>(0);
        return route.pageBuilder(ctx, still, still) as AlbumScreen;
      }

      expect(pageFor('cover-rail-recent-a1').heroTag, 'cover-rail-recent-a1');
      expect(
          pageFor('cover-rail-frequent-a1').heroTag, 'cover-rail-frequent-a1');
      expect(pageFor(null).heroTag, isNull, reason: '不传就退回网格那个 tag');
      expect(pageFor('x').albumId, 'a1');
    });

    testWidgets('货架把她自己显示的那个 tag 原样带进专辑路由', (tester) async {
      const album = Album(id: 'a1', name: '可能', artist: '某人', artistId: 'ar-1');
      Object? pushed;

      await tester.pumpWidget(MaterialApp(
        theme: NordicTheme.dark,
        onGenerateRoute: (settings) {
          pushed = settings.arguments;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const SizedBox(),
          );
        },
        home: Scaffold(
          body: AlbumRail(
            albums: const [album],
            repo: null,
            heroPrefix: 'cover-rail-recent',
          ),
        ),
      ));

      final shown = tester.widget<Hero>(find.byType(Hero)).tag;
      await tester.tap(find.byType(Hero));
      await tester.pumpAndSettle();

      final args = pushed as ({String id, String? heroTag});
      expect(args.id, 'a1');
      expect(args.heroTag, shown,
          reason: '起点显示的那个 tag 与终点拿到的必须字字相同，否则飞不起来');
    });

    /// 滑入**只有位移,没有整页淡入**。
    ///
    /// 整屏不透明度会把子树关进一个离屏合成层,而沉浸页里有 62px 的氛围模糊
    /// 和播放坞玻璃的 `BackdropFilter` —— 那样每帧都要在新缓冲里重做这两样,
    /// 就是真机反馈的「切页面 / 返回卡顿」。这一条把「别再顺手加回来」钉死。
    testWidgets('滑入只有位移，没有整页淡入', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      final route = AppRoutes.generate(
        RouteSettings(name: AppRoutes.album, arguments: (id: 'a1', heroTag: null)),
      )! as PageRouteBuilder<dynamic>;

      // 过渡中间那一帧:这里刻意取 0.5,免得 0 / 1 两端把这个区别盖掉。
      const halfway = AlwaysStoppedAnimation<double>(0.5);
      final widget =
          route.transitionsBuilder(ctx, halfway, halfway, const SizedBox());

      expect(widget, isA<SlideTransition>());
      expect(widget, isNot(isA<FadeTransition>()),
          reason: '淡入是那层离屏合成的来源，位置只能靠位移给');
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

  group('弹层蒙板', () {
    // 真机上报的是「弹窗背后还有一层黑蒙板,丑」。原因是两层黑叠着:
    // 框架默认的 `Colors.black54`(一整块纯黑、不模糊)+ NordicScrim
    // (原型那层 66% 压暗 + 6px 模糊)。这一组钉住「只剩原型那一层」。

    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showNordicSheet<void>(
                  context: context,
                  builder: (_) => const NordicScrim(
                    child: NordicSheet(child: Text('内容')),
                  ),
                ),
                child: const Text('开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开'));
      await tester.pumpAndSettle();
    }

    testWidgets('框架那层默认黑被关掉 —— 没有哪道 barrier 还在画颜色', (tester) async {
      await openSheet(tester);

      // `barrierColor` 是透明时,框架走的是不带颜色的那条分支(`color` 为 null)。
      // 谁把 barrierColor 去掉了,这里立刻会看到 Colors.black54。
      final barriers = tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .map((b) => b.color)
          .whereType<Color>()
          .toList();
      // barrier 本身还在(它负责拦住点击、点外面就关),只是不再画黑。
      expect(find.byType(ModalBarrier), findsWidgets);
      expect(barriers, isEmpty, reason: '框架那层黑与蒙板叠起来是 84% 黑');
    });

    testWidgets('蒙板铺满整屏，而不是只盖下半屏', (tester) async {
      await openSheet(tester);

      // 不写 `isScrollControlled: true` 时框架只给内容盒子屏幕高度的 9/16,
      // 蒙板就只盖住下半屏 —— 上半屏剩下一块没有模糊的纯黑。
      final screen = tester.getSize(find.byType(MaterialApp));
      expect(tester.getSize(find.byType(NordicScrim)).height, screen.height);
    });
  });

  group('进度条的一帧', () {
    // 真机:歌在放,进度条却是 0(左端 0:00、右端 --:--、滑块还拖不动)。
    // 根因是时长没送到(`state.duration`),这里钉住界面在那种情况下该怎么画。

    test('时长未知时滑块停最左，但左端写真实位置', () {
      final frame = scrubberFrame(
        position: const Duration(seconds: 35),
        duration: Duration.zero,
      );
      expect(frame.hasDuration, isFalse);
      expect(frame.value, 0, reason: '没有量程就不该假装有个比例');
      expect(frame.max, 1, reason: 'Slider 的 max 不能是 0');
      expect(frame.shownPosition, const Duration(seconds: 35),
          reason: '这里跟着写 0 就成了「歌在放、进度条说还在开头」');
      expect(frame.remaining, Duration.zero);
    });

    test('时长已知时按位置算，越界夹回', () {
      final frame = scrubberFrame(
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 60),
      );
      expect(frame.hasDuration, isTrue);
      expect(frame.value, 30000);
      expect(frame.shownPosition, const Duration(seconds: 30));
      expect(frame.remaining, const Duration(seconds: 30));

      final over = scrubberFrame(
        position: const Duration(seconds: 90),
        duration: const Duration(seconds: 60),
      );
      expect(over.value, 60000);
      expect(over.remaining, Duration.zero);
    });

    test('拖着的期间以手指为准', () {
      final frame = scrubberFrame(
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 60),
        dragValue: 45000,
      );
      expect(frame.value, 45000);
      expect(frame.shownPosition, const Duration(seconds: 45));
    });

    test('拖动中换到更短的一首：那个值也要夹回量程里', () {
      // 「松手之后停在手指放开的地方」那一份值会一直留着,而拖动途中自动接到
      // 下一首时它可能比新曲的时长还大 —— 原样交给 Slider 就是
      // `value <= max` 的断言失败(debug 直接崩)。
      final frame = scrubberFrame(
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 30),
        dragValue: 180000,
      );
      expect(frame.value, 30000);
      expect(frame.value, lessThanOrEqualTo(frame.max));
      expect(frame.remaining, Duration.zero);
    });

    // ---- 缓冲带画到哪儿(见 scrubberFrame 的头一段口径) ----
    // 画不画全在这一层决定,那头的 trackShape 只管画。

    test('缓冲跑到播放位置前面就把那一段标出来', () {
      final frame = scrubberFrame(
        position: const Duration(seconds: 15),
        duration: const Duration(seconds: 60),
        buffered: const Duration(seconds: 30),
      );
      expect(frame.bufferedRatio, 0.5);
    });

    test('整首都在手边就不画 —— 没有待拉的东西', () {
      // 本机文件 / 已下完的那一份整首到手,缓冲值顶到曲尾。
      final frame = scrubberFrame(
        position: const Duration(seconds: 15),
        duration: const Duration(seconds: 60),
        buffered: const Duration(seconds: 60),
      );
      expect(frame.bufferedRatio, isNull);
    });

    test('缓冲没跑到播放位置前面不画', () {
      final frame = scrubberFrame(
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 60),
        buffered: const Duration(seconds: 30),
      );
      expect(frame.bufferedRatio, isNull);
    });

    test('时长未知时不画，越界的缓冲夹回量程', () {
      final unknown = scrubberFrame(
        position: const Duration(seconds: 5),
        duration: Duration.zero,
        buffered: const Duration(seconds: 20),
      );
      expect(unknown.bufferedRatio, isNull, reason: '没有量程就没有比例');

      // 缓冲值越界(平台偶尔报得比时长还大)不该画出格 ——
      // 夹回之后正好等于时长,按「没有待拉的」处理。
      final over = scrubberFrame(
        position: const Duration(seconds: 5),
        duration: const Duration(seconds: 60),
        buffered: const Duration(seconds: 90),
      );
      expect(over.bufferedRatio, isNull);

      // 拖动期间用**真实位置**判,不看手指拖到哪儿。
      final dragging = scrubberFrame(
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 60),
        buffered: const Duration(seconds: 30),
        dragValue: 50000,
      );
      expect(dragging.bufferedRatio, 0.5);
    });
  });

  group('松手之后的落点', () {
    // 远端那一首的 seek 要等本机缓存下完才落地(见 audio_handler 的 seek),
    // 这期间位置还是旧的 —— 拇指一松就弹回去,看着像白拖了。
    final dropped = DateTime(2026, 10, 17, 12);
    const target = Duration(seconds: 45);

    Duration? hold(
      Duration position, {
      Duration? held = target,
      DateTime? at,
      Duration since = Duration.zero,
    }) =>
        scrubberHold(
          held: held,
          heldAt: held == null ? null : (at ?? dropped),
          position: position,
          now: dropped.add(since),
        );

    test('位置还没跟上来时停在落点上', () {
      expect(hold(const Duration(seconds: 12)), target);
    });

    test('位置追上了就交回真实进度', () {
      // 落在 45 秒,位置报到 45.4 —— 差在 settle 以内算落地。
      expect(hold(const Duration(milliseconds: 45400)), isNull);
    });

    test('等够久了要认命 —— 否则一次没生效的 seek 会把拇指永久钉在那儿', () {
      expect(
        hold(const Duration(seconds: 12), since: const Duration(seconds: 8)),
        isNull,
      );
    });

    test('没松过手时没有落点', () {
      expect(hold(const Duration(seconds: 12), held: null), isNull);
    });
  });

  group('循环键的选中态', () {
    // 上一轮这个键点下去会弹一句「顺序播放 / 列表循环 / 单曲循环」,
    // 连点三下就是三条横幅 —— 已按用户要求移除。状态从那以后只剩图标与底色,
    // 这一组钉住「两态分得开」:列表循环与顺序播放**共用一个图标**,
    // 少了那层底色这两个状态在屏幕上就是同一张脸。
    test('顺序播放不亮；列表循环图标不变但必须亮；单曲循环换成带 1 的圈', () {
      expect(
        repeatKeyAppearance(PlaybackRepeat.off),
        (icon: Icons.repeat, on: false),
      );
      expect(
        repeatKeyAppearance(PlaybackRepeat.all),
        (icon: Icons.repeat, on: true),
        reason: '与顺序播放同图标，不亮就等于这两个状态看一样',
      );
      expect(
        repeatKeyAppearance(PlaybackRepeat.one),
        (icon: Icons.repeat_one, on: true),
      );
    });

    testWidgets('按下就有回执，抬手回弹 —— 别等到状态变了才让人知道点着了', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Pressable(
              onTap: () => taps++,
              scale: 0.92,
              child: const SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      );

      double scale() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

      expect(scale(), 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SizedBox)),
      );
      await tester.pump();
      expect(scale(), 0.92, reason: '按下去屏幕上什么都不动 = 手感上「这机器慢」');

      await gesture.up();
      await tester.pump();
      expect(scale(), 1);
      expect(taps, 1);
    });
  });

  group('大字号下不挤爆', () {
    // 系统字号拉大是无障碍里最常见的设置,而这一屏到处是**写死高度的行**。
    // 这里把字号拉到 2 倍:pump 之后 takeException 必须为空(溢出会走那儿)。
    Future<void> pumpAt(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(
            theme: NordicTheme.build(NordicTokens.dark),
            home: Scaffold(body: child),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('歌曲行：长标题 + 长艺人专辑，行要跟着长高而不是裁掉文字', (tester) async {
      await pumpAt(
        tester,
        const NordicRow(
          leading: SizedBox(width: 52, height: 52),
          title: '一首名字特别长的歌 —— 长到在手机屏上必须截断才放得下',
          subtitle: '一位名字同样很长的艺人 · 专辑名也不短',
          height: 64,
        ),
      );
      expect(tester.takeException(), isNull);
      // 行高确实跟着长大 —— 写死 64 的话上面那条就会报溢出。
      expect(tester.getSize(find.byType(NordicRow)).height, greaterThan(64));
    });

    testWidgets('胶囊 / 按钮：文字放大后不溢出', (tester) async {
      await pumpAt(
        tester,
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NordicChip(label: '重新测速', icon: Icons.refresh, onTap: () {}),
              const SizedBox(height: 12),
              PrimaryButton(label: '播放这张专辑', onPressed: () {}),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('章节头：右侧动作和标题要在同一条中线上', () {
    // 真机上报的「测速按钮里『测速』两个字没对齐」。这一组钉两件事:
    //   (1) 右侧那颗胶囊 / 排序键不许被基线行压到标题下面;
    //   (2) 胶囊**自己**的内容要居中 —— 未选中态走玻璃底(Stack 默认顶对齐),
    //       选中态走不透明的定高盒子(会撑满、天然居中),两边不一致的话
    //       点一下「测速」→「测速中」,字会往下跳一截。
    Future<void> pumpHeader(WidgetTester tester, {bool selected = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: Scaffold(
            body: SectionHeader(
              title: '线路',
              count: '3 条',
              trailing: NordicChip(
                label: '测速',
                icon: Icons.refresh,
                height: 30,
                selected: selected,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('胶囊的中心 == 标题的中心', (tester) async {
      await pumpHeader(tester);
      expect(tester.takeException(), isNull);

      final titleCenter = tester.getRect(find.text('线路')).center.dy;
      final chipCenter = tester.getRect(find.byType(NordicChip)).center.dy;

      // 两个都是那一行的直接子节点、都被居中,所以中心恒等于行高的一半 ——
      // 差值是结构性的,不靠字号凑。epsilon 只用来吸收半个像素的取整。
      expect(
        chipCenter,
        moreOrLessEquals(titleCenter, epsilon: 0.5),
        reason: '右侧胶囊要和标题中线对齐（原型 .section .chip{align-self:center})',
      );
    });

    testWidgets('失败形态：胶囊不许沉到标题下面', (tester) async {
      await pumpHeader(tester);
      expect(
        tester.getRect(find.byType(NordicChip)).center.dy,
        lessThanOrEqualTo(tester.getRect(find.text('线路')).center.dy + 0.5),
        reason: '基线行会把非文字的 trailing 往下压，这正是真机上报的那一版',
      );
    });

    testWidgets('胶囊里的字也要在胶囊里居中 —— 选中 / 未选中都是', (tester) async {
      // 两态各差多少才算「字在里面居中」,分开量:
      // 未选中走 NordicGlass(Stack 默认把内容顶对齐),选中走不透明的定高盒子
      // (会撑满、天然居中)。只量未选中态的话,「点一下字往下跳」这件事漏得掉。
      final offsets = <bool, double>{};
      for (final selected in [false, true]) {
        await pumpHeader(tester, selected: selected);
        expect(tester.takeException(), isNull, reason: '选中态 $selected');
        final chip = tester.getRect(find.byType(NordicChip));
        final label = tester.getRect(find.text('测速'));
        offsets[selected] = label.center.dy - chip.center.dy;
        expect(
          offsets[selected],
          moreOrLessEquals(0, epsilon: 0.5),
          reason: '选中态 $selected：字没落在胶囊中线上',
        );
      }
      // 再钉一次「点一下字不跳」:两态下字相对胶囊的偏移必须一致。
      expect(
        offsets[true],
        moreOrLessEquals(offsets[false]!, epsilon: 0.5),
        reason: '「测速」→「测速中」时两个字不该跳',
      );
    });
  });
}

/// 剥掉 `ResizeImage` 那层包装(设了 cacheWidth 就会有)。
ImageProvider _inner(ImageProvider provider) =>
    provider is ResizeImage ? provider.imageProvider : provider;
