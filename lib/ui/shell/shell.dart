import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/ambient.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import 'bottom_stack.dart';

/// 应用主壳:三个常驻 tab。
///
/// 沉浸页(播放 / 歌词 / 专辑 / 艺人)走**独立路由**(见 [AppRoutes])而不是
/// 塞进 tab 的子页面 —— 它们要盖住标签栏、要自己的氛围背景与共享元素过渡,
/// 挂在 tab 下面会让这三件事都别扭。
class NordicShell extends StatefulWidget {
  const NordicShell({super.key});

  @override
  State<NordicShell> createState() => _NordicShellState();
}

class _NordicShellState extends State<NordicShell> {
  AppTab _tab = AppTab.library;

  /// 已经露过面的 tab。**没露过面的先不建**:冷启动时把搜索与设置那两棵树
  /// 也建出来是白花的 —— 用户可能整场都不点它们,而设置页有几十行。
  /// 建过之后 IndexedStack 照旧保活,滚动位置不丢。
  final Set<AppTab> _built = {AppTab.library};

  void _select(AppTab tab) {
    if (tab == _tab && _built.contains(tab)) return;
    setState(() {
      _tab = tab;
      _built.add(tab);
    });
  }

  /// tab → 那一屏。没建过的用空盒子占位(IndexedStack 要按 index 取用)。
  static Widget _screenOf(AppTab tab) => switch (tab) {
        AppTab.library => const LibraryScreen(),
        AppTab.search => const SearchScreen(),
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

  /// 顶栏那个放大镜(见 `AppRoutes.openSearchTab`)。
  ///
  /// 这条线**断过一阵**:`searchTabRequest` 一直有人发、没人听,于是音乐库
  /// 顶栏的放大镜点了什么也不发生 —— 一颗死按钮。现在接回来。
  void _applySearchRequest() => _select(AppTab.search);

  @override
  void initState() {
    super.initState();
    pendingTab.addListener(_applyPendingTab);
    searchTabRequest.addListener(_applySearchRequest);
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
    });
  }

  @override
  void dispose() {
    pendingTab.removeListener(_applyPendingTab);
    searchTabRequest.removeListener(_applySearchRequest);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // IndexedStack 而不是条件渲染 —— 切回来时滚动位置还在。
          IndexedStack(
            index: _tab.index,
            children: [
              for (final tab in AppTab.values)
                if (_built.contains(tab))
                  _screenOf(tab)
                else
                  const SizedBox.shrink(),
            ],
          ),
          BottomStack(activeTab: _tab, onTabSelected: _select),
        ],
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
        body: Stack(
          children: [
            if (showAmbient) ...[
              NordicAmbient(accent: accent),
              const NordicAmbientShade(),
            ],
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                // 沉浸页自己管底部留白 —— 歌词页的控制排要贴着指示条。
                child: Column(
                  children: [
                    Expanded(child: child),
                    if (bottomBar != null) bottomBar!,
                  ],
                ),
              ),
            ),
            if (showNav)
              BottomStack(
                // 这几屏不属于任何 tab —— 原型上也是谁都不高亮。
                activeTab: null,
                onTabSelected: (tab) => openTab(context, tab),
              ),
          ],
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