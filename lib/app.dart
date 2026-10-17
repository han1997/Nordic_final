import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'playback/playback_controller.dart';
import 'state/app_state.dart';
import 'theme/nordic_theme.dart';
import 'theme/theme_mode.dart';
import 'ui/routes.dart';
import 'ui/shell/shell.dart';

/// 应用根。主题在这里定调,其余一切都在它之下。
///
/// 提供者(Provider)的挂载在 `main.dart` —— 那里才能先 `await` 出配置与
/// 播放服务。这里只管主题与路由。
///
/// 主题档位读自 [AppState](用户的选择已落盘),所以切完主题重启应用
/// 仍是那一个 —— 不会每次回到默认。
class NordicApp extends StatelessWidget {
  const NordicApp({super.key});

  @override
  Widget build(BuildContext context) {
    // **只 select 主题档位这一件事。**
    //
    // 根这里每重建一次都要重挂 `MaterialApp`(整棵路由树)并取两套主题,
    // 而 `AppState` 的通知里混着下载进度(最多每秒四次)与缓存淘汰 ——
    // `watch` 整个 `AppState` 就是把它们统统算成了「根要重建」。
    // 根真正关心的只有主题档位(它自己会落盘,重启后仍是那个)。
    final state = context.select<AppState, String?>((s) => s.themeModeName);
    final mode = NordicThemeMode.byName(state);

    return MaterialApp(
      title: 'Nordic',
      debugShowCheckedModeBanner: false,
      // 两套主题取的是 [NordicTheme] 里缓存好的那一份:`ColorScheme.fromSeed`
      // 那趟调色计算不必每次重建都重来(见那里的说明)。
      theme: NordicTheme.light,
      darkTheme: NordicTheme.dark,
      // 设计的主场是深色(近黑底靠光晕撑层次),系统没表态时按深色走。
      themeMode: mode.material,
      navigatorKey: navigatorKey,
      // 生命周期规则挂在 MaterialApp 的 builder 上而不是各页面里 ——
      // 它是应用级的一条,页面来去都不该影响它。
      builder: (context, child) =>
          _BackgroundPlayGuard(child: child ?? const SizedBox.shrink()),
      // 全部页面(含三个 tab 的主壳)都由 AppRoutes 出路由 —— 那里统一了
      // 过渡,见 AppRoutes.generate 的说明。
      onGenerateRoute: AppRoutes.generate,
      home: const NordicShell(),
    );
  }
}

/// 「播放时后台运行」关掉之后:切到后台就暂停。
///
/// 用 [WidgetsBindingObserver] 而不是在每个页面里听 `AppLifecycleState`:
/// 用户是按「应用」理解这个开关的,不是按「页面」。
class _BackgroundPlayGuard extends StatefulWidget {
  const _BackgroundPlayGuard({required this.child});

  final Widget child;

  @override
  State<_BackgroundPlayGuard> createState() => _BackgroundPlayGuardState();
}

class _BackgroundPlayGuardState extends State<_BackgroundPlayGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) return;
    final playback = context.read<PlaybackController>();
    pauseWhenBackgrounded(
      backgroundPlay: context.read<AppState>().backgroundPlay,
      pause: playback.pause,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 全局导航键 —— 播放通知栏点回来、以及「从任意位置跳播放页」都要用。
final navigatorKey = GlobalKey<NavigatorState>();