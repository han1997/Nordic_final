import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/ambient.dart';
import '../../theme/tokens.dart';
import '../adaptive/window.dart';
import '../routes.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/queue_restore_sheet.dart';
import '../screens/settings_screen.dart';
import '../widgets/components.dart';
import 'bottom_stack.dart';
import 'chrome.dart';

/// 应用主壳:三个常驻 tab(首页 / 音乐库 / 设置)。
///
/// 沉浸页(播放 / 歌词 / 专辑 / 艺人)**走独立路由**(见 [AppRoutes])而不是
/// 塞进 tab 的子页面 —— 它们要盖住标签栏、要自己的氛围背景与共享元素过渡,
/// 挂在 tab 下面会让这三件事都别扭。搜索也是这条路(2026-10-17 起:
/// 它不再是常驻 tab,而是一张推入的页面)。
class NordicShell extends StatefulWidget {
  const NordicShell({super.key});

  @override
  State<NordicShell> createState() => _NordicShellState();
}

class _NordicShellState extends State<NordicShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 冷启动落在**首页**:「现在在听 / 最近在听」是打开播放器最想先看到的一屏。
  AppTab _tab = AppTab.home;

  /// 已经露过面的 tab。**没露过面的先不建**:冷启动时把音乐库与设置那两棵树
  /// 也建出来是白花的 —— 用户可能整场都不点它们,而音乐库有四百多张专辑的网格、
  /// 设置页有几十行。建过之后 IndexedStack 照旧保活,滚动位置不丢。
  final Set<AppTab> _built = {AppTab.home};

  /// 切 tab 那一下的进度。**与底部悬浮 tab 的胶囊同一套缓动**(`NordicMotion.ease`,
  /// 时长 `NordicMotion.screenFade`)—— 高亮滑过去、新一屏浮上来,两件事读起来
  /// 才是一下。
  ///
  /// 这个值**只喂给 [TabEntrance] 那一块实色**,不参与任何内容的合成:内容在
  /// 点下的那一帧就换完了(`IndexedStack` 自己重建),220ms 里动的只有盖在新一屏
  /// 上的那层底色。
  ///
  /// 2026-10-18 那版是挂在 `IndexedStack` 外面的 `FadeTransition`(整屏不透明度
  /// 外面垫一张 `RepaintBoundary`)。手感一样,账不一样:整屏不透明度会为整棵
  /// 子树开一层离屏 —— 边界只隔住**重画**,那 220ms 里每一帧仍要把整屏当成一张
  /// 纹理重新合成;而这段里正赶上新一屏的数据落地、播放进度与胶囊高亮,内容每
  /// 重画一次都要再穿过那层。换成 [TabEntrance] 之后内容根本不进离屏层,每帧
  /// 只多画一块实色。
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: NordicMotion.screenFade,
    value: 1,
  );

  late final Animation<double> _fadeCurve =
      CurvedAnimation(parent: _fade, curve: NordicMotion.ease);

  /// 「接着上次听」那一问是不是正在进行(纸开着 / 正在打 `getPlayQueue`)。
  /// 见 [_maybeOfferQueueRestore]。
  bool _offeringRestore = false;

  void _select(AppTab tab) {
    if (tab == _tab && _built.contains(tab)) return;
    setState(() {
      _tab = tab;
      _built.add(tab);
    });
    // 从 0 起:这一帧 [TabEntrance] 整片盖住新一屏,220ms 内褪干净。
    // 淡的是「换过来」这一下,不是某一棵子树 —— 切回来时位置照旧保活。
    _fade.forward(from: 0);
  }

  /// tab → 那一屏。没建过的用空盒子占位(IndexedStack 要按 index 取用)。
  static Widget _screenOf(AppTab tab) => switch (tab) {
        AppTab.home => const HomeScreen(),
        AppTab.library => const LibraryScreen(),
        AppTab.settings => const SettingsScreen(),
      };

  /// 沉浸页上那颗胶囊点了某个 tab(见 [openTab])。
  ///
  /// 用掉就清掉,不然下次从沉浸页退回来还会莫名其妙跳一次。
  void _applyPendingTab() {
    final tab = pendingTab.value;
    if (tab == null) return;
    pendingTab.value = null;
    _select(tab);
  }

  @override
  void initState() {
    super.initState();
    // 「接着上次听」除了冷启动那一问,回到前台也要再看一眼 ——
    // 见 [didChangeAppLifecycleState]。
    WidgetsBinding.instance.addObserver(this);
    pendingTab.addListener(_applyPendingTab);
    // 首帧之后再拉数据 —— 在 initState 里直接发起会让第一次 build
    // 就撞上「正在加载」而白闪一下。
    //
    // 这里必须**无条件**触发一次(而不是只在某个 tab 被选中时),
    // 否则冷启动进来停在音乐库却永远不加载 —— 用户看到的是
    // 「这个库里还没有内容」,而其实只是没人去取。
    // `loadLibrary` 内部自己对「没配服务器」与「已在加载」做了短路。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      if (!state.hasServer) return;

      // 两种情况都要拉:一次还没拉过(idle),或者眼下铺的是**本机缓存** ——
      // 缓存那份是拿来立刻可见的,不是拿来当真的,得在后台换成最新的。
      // 后者走 silent:屏幕上已经有内容,不该再闪一次加载态。
      if (state.phase == LoadPhase.idle) {
        state.loadLibrary();
      } else if (state.libraryFromCache) {
        state.loadLibrary(silent: true);
      }

      // 「接着上次听」:服务器上要是留着一份**别的设备**写的队列,问一句。
      // 与拉库同一处(首帧之后),但它自己会判断值不值得问 —— 我们自己刚写的那
      // 一份不会问(见 AppState.checkPlayQueue 的指纹比对)。
      unawaited(_maybeOfferQueueRestore(state));
    });
  }

  /// 值得问的时候问一句「接着上次听?」。
  ///
  /// 「继续」= 装载那份队列 + 摆好落点,**但不出声**(`autoPlay: false`)——
  /// 打开应用自己放起来是很吓人的事,让用户自己按播放。
  ///
  /// 落点跟着装载一起给(`initialPosition`),不是装完再 seek:冷转码流不可
  /// seek(见 `NordicAudioHandler._seekRemote`),那一刀会静静落空,接着听就
  /// 变成从头听。装载那一刻的落点还会被 [PlaybackController.playAll] 摆到
  /// 位置通道上,于是紧接着那次队列同步**不会**把服务器上的落点写回 0。
  ///
  /// 两种回答都调 [AppState.forgetPendingQueue]:那一步会把这一次的**指纹**
  /// 记下来 —— 「忽略」是他刚说了不要,「继续」是这一份已经装载过了。
  /// 下次换个队列(另一台设备又改了)才会再问。
  ///
  /// 装载失败是例外:不记指纹(见 [AppState.forgetPendingQueue] 的
  /// `remember`),并且**当场说一句** —— 否则用户按了「继续」,队列没出现、
  /// 也没有第二次机会。
  Future<void> _maybeOfferQueueRestore(AppState state) async {
    // 前后台切换常常连着来两下;已经有一张纸开着的时候不必再问一遍,
    // 也不必再打一趟 `getPlayQueue`。
    if (_offeringRestore) return;
    if (state.pendingQueueRestore != null) return;
    // **本机正在放的时候不问**:那不是「换设备接着听」,而是两台同时在出声。
    // 把「换到这台」摆到正在听的那一台眼前,打断的正是这一首。
    if (context.read<PlaybackController>().state.playing) return;

    _offeringRestore = true;
    try {
      await state.checkPlayQueue();
      if (!mounted) return;
      final pending = state.pendingQueueRestore;
      if (pending == null) return;

      final accepted = await showQueueRestoreSheet(context, pending);
      if (!mounted) return;

      if (accepted) {
        final playable = context.read<PlaybackController>();
        final messenger = ScaffoldMessenger.maybeOf(context);
        final failure = await playable.playAll(
          pending.songs,
          index: queueRestoreIndex(pending),
          autoPlay: false,
          initialPosition: pending.position,
        );
        if (!mounted) return;
        if (failure != null) {
          messenger?.showSnackBar(
            SnackBar(
              content: Text('没能把队列接过来 —— $failure'),
              duration: const Duration(seconds: 2),
            ),
          );
          // 不记指纹:回到前台还会再问一次。
          await state.forgetPendingQueue(remember: false);
          return;
        }
      }
      await state.forgetPendingQueue();
    } finally {
      _offeringRestore = false;
    }
  }

  /// 回到前台,再看一眼服务器上的队列。
  ///
  /// 冷启动那一问只在 `initState` 的后一帧做一次 —— 而「换到另一台设备」最
  /// 常见的姿势是**把一个还开着的窗口切回来**(桌面最小化了一夜、手机从后台
  /// 切回来),应用根本没重启。少了这一条,用户要杀掉应用重开才会被问到。
  ///
  /// **只在 `resumed` 上做**:`inactive` / `paused` 不是「用户回到了这台设备」;
  /// 而这条路上会打一趟 `getPlayQueue`,后台里定时去打才是费电的那一类事。
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.repository == null) return;
    unawaited(_maybeOfferQueueRestore(state));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pendingTab.removeListener(_applyPendingTab);
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 点空白处收起软键盘 —— 主壳自己没输入框,但沉浸页推上来时键盘可能还开着
      // (比如从搜索页点进专辑),那一下点击要能收掉它(理由见 [DismissKeyboardOnTap])。
      body: DismissKeyboardOnTap(
        child: Stack(
          children: [
            // 第二十六轮:宽屏下内容整体右移 104,给左侧竖栏让位 ——
            // 让位只在壳上给一次,页面里那 12 处 listInset 不必各改一遍。
            NavGutter(
              // 这张 Stack 只装两样:内容,和盖在内容上的那一层 [TabEntrance]。
              // 常驻区在它**外面** —— 切 tab 时胶囊 / 竖栏 / 播放坞一下都不闪。
              child: Stack(
                children: [
                  // IndexedStack 而不是条件渲染 —— 切回来时滚动位置还在。
                  //
                  // 这张 `RepaintBoundary` 守的是**重画**:里面挂着各 tab 保活的
                  // 整棵子树(含首页那层 62px 的 `ImageFiltered` 氛围与玻璃的
                  // `BackdropFilter`),而上面那块实色每帧都在变 —— 少了边界,
                  // 它每变一次就把这些一起拖着重画一遍。
                  RepaintBoundary(
                    child: IndexedStack(
                      index: _tab.index,
                      children: [
                        for (final tab in AppTab.values)
                          if (_built.contains(tab))
                            // **只有屏幕上那一屏的 `Hero` 才参与共享元素过渡。**
                            //
                            // 框架按 tag 在**整个来源路由**里找起点,不看元素在不在
                            // 屏幕上(`heroes.dart` 的 `_allHeroesFor` 只认 `HeroMode`)。
                            // 而 IndexedStack 把逛过的 tab **整棵保活**:只要切过一次
                            // 音乐库的「专辑」分段,那张网格就一直挂着 —— 于是
                            // 「在首页点一张专辑 / 点播放坞」时起点会被**看不见的那张
                            // 网格**偷走,封面从屏幕外飞进来(每帧重画一次,
                            // 正好落在滑入动画上)。`HeroMode` 就是框架给这件事的做法:
                            // 关掉的子树整个跳过,英雄名字空间于是**每个 tab 一份**。
                            HeroMode(enabled: tab == _tab, child: _screenOf(tab))
                          else
                            const SizedBox.shrink(),
                      ],
                    ),
                  ),
                  // 切 tab 那一下盖在新一屏上的实色(见 [_fade] 上那段)。
                  TabEntrance(progress: _fadeCurve),
                ],
              ),
            ),
            // 常驻区:窄屏是底部胶囊托盘,宽屏(>= 840)换左竖栏 + 播放横条。
            // 形态切换只此一处(见 chrome.dart)。
            NordicChrome(activeTab: _tab, onTabSelected: _select),
          ],
        ),
      ),
    );
  }
}

/// 切 tab 时盖在新一屏上的那一层实色 —— 唯一一件还在动的东西。
///
/// 为什么不是 `FadeTransition` 包住内容:整屏不透明度会为整棵子树开一层离屏
/// 合成。外面垫一张 `RepaintBoundary` 只省掉**重画**,那 220ms 里每一帧仍要把
/// 这张整屏纹理重新合成一次 —— 而这段里正赶上新一屏的数据落地、播放进度与
/// 底部胶囊高亮,内容每一次重画都得再穿过那层。
///
/// 这里反过来:内容一帧切到位(一点没淡),淡的是**盖在它前面的一层不透明
/// 底色**,从满到零。读起来仍然是「一屏化进另一屏」,贵的东西一次都没进过
/// 离屏层,每帧只多画一块实色。
class TabEntrance extends StatelessWidget {
  const TabEntrance({super.key, required this.progress});

  /// 0 = 整片盖住(刚切过去),1 = 完全褪掉。
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    final bg = context.nordic.bg;
    return Positioned.fill(
      // 不吃点击:这一层只是视觉上的过渡,底下的新一屏从第一帧起就是活的。
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: progress,
          builder: (context, child) {
            final t = progress.value;
            // 到点连这块实色都不必再画。
            if (t >= 1) return const SizedBox.shrink();
            return ColoredBox(color: bg.withValues(alpha: 1 - t));
          },
        ),
      ),
    );
  }
}

/// 沉浸页的外壳:氛围背景 + 主色作用域。
///
/// [accent] 由调用方按当前内容给出(专辑 / 艺人 / 当前播放的歌)。
/// 强调色挂在 [NordicAccentScope] 上,页面内部任意深度的组件都能取到,
/// 不必逐层传参 —— 这正是「随封面取色」能遍布整屏的原因。
class ImmersiveScaffold extends StatelessWidget {
  const ImmersiveScaffold({
    super.key,
    required this.accent,
    required this.child,
    this.bottomBar,
    this.showAmbient = true,
    this.showNav = false,
  });

  final NordicAccent accent;
  final Widget child;

  /// 页面底部的固定区(歌词页的控制排)。
  final Widget? bottomBar;

  /// 沉浸页默认铺氛围背景;列表型的二级页(如服务器设置)关掉它。
  final bool showAmbient;

  /// 是否浮出底部的播放坞 + 标签栏胶囊。
  ///
  /// 原型在专辑 / 艺人 / 服务器这几屏上是浮着的(`bottom()` 与一级页面同一颗),
  /// 播放页与歌词页则整屏都是播放控制,不给。带着它的页面用
  /// [BottomStack.listInset] 留出底部空间。
  final bool showNav;

  @override
  Widget build(BuildContext context) {
    return NordicAccentScope(
      accent: accent,
      child: Scaffold(
        backgroundColor: context.nordic.bg,
        // 二级页面里也有输入框(搜索、新建歌单、加线路)—— 点空白处收起软键盘。
        body: DismissKeyboardOnTap(
          child: Stack(
            children: [
              if (showAmbient) ...[
                NordicAmbient(accent: accent),
                const NordicAmbientShade(),
              ],
              Positioned.fill(
                child: SafeArea(
                  bottom: false,
                  // 沉浸页自己管底部留白 —— 歌词页的控制排要贴着指示条。
                  //
                  // NavGutter 只在**浮常驻区**的屏上让位(showNav):
                  // 播放 / 歌词(showNav: false)保持满宽居中,与原型一致。
                  child: NavGutter(
                    enabled: showNav,
                    child: Column(
                      children: [
                        Expanded(child: child),
                        ?bottomBar,
                      ],
                    ),
                  ),
                ),
              ),
              if (showNav)
                NordicChrome(
                  // 这几屏不属于任何 tab —— 原型上也是谁都不高亮。
                  activeTab: null,
                  onTabSelected: (tab) => openTab(context, tab),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶栏 —— `.appbar`。
///
/// 两种形态:[big] 大标题(一级页面),[small] 窄标题(二级页面,带返回)。
/// 结构只有一份,差异落在字号与对齐上。
class NordicAppBar extends StatelessWidget implements PreferredSizeWidget {
  const NordicAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.big = true,
    this.transparent = false,
    this.centerTitle = false,
    this.titleWidget,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final bool big;

  /// 标题居中 —— 播放页与歌词页的顶栏(`back … 标题 … ⋯`)是这副样子。
  /// 只对窄标题([big] 为 false)有意义。
  final bool centerTitle;

  /// 自定义标题。给了就用它 —— 播放页那颗「正在播放」是**小字标签**,
  /// 不是标题,套默认大标题的字号与字重都不对。
  final Widget? titleWidget;

  /// 沉浸页顶栏不加底色,让氛围背景透上来。
  final bool transparent;

  @override
  Size get preferredSize => Size.fromHeight(big ? 84 : 60);

  /// 标题本体:自定义的优先,否则按大小归类铺。
  Widget _titleOf(BuildContext context, NordicTokens t) {
    final custom = titleWidget;
    if (custom != null) return custom;

    if (!big) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: NordicType.h3,
              fontWeight: FontWeight.w600,
            ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.fg3),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;

    return Material(
      color: transparent ? Colors.transparent : t.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: big
              ? const EdgeInsets.fromLTRB(
                  NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s4)
              : const EdgeInsets.fromLTRB(
                  NordicSpace.s4, NordicSpace.s2, NordicSpace.s4, NordicSpace.s3),
          child: SizedBox(
            // 内容高度只给「一行标题 + 可选副标题」的**恰好**所需,
            // 不再写死。之前写死 54 而标题两行要 55,于是常年挂着
            // 那条黄黑相间的溢出警示带。
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: NordicSpace.s3),
                ],
                Expanded(
                  child: centerTitle
                      ? Center(child: _titleOf(context, t))
                      : _titleOf(context, t),
                ),
                for (final action in actions) ...[
                  const SizedBox(width: NordicSpace.s1),
                  action,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}