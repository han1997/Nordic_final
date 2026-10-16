import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'playback/playback_controller.dart';
import 'state/app_state.dart';
import 'theme/nordic_theme.dart';
import 'theme/theme_mode.dart';
import 'theme/tokens.dart';
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
    final state = context.watch<AppState>();
    final mode = NordicThemeMode.byName(state.themeModeName);

    return MaterialApp(
      title: 'Nordic',
      debugShowCheckedModeBanner: false,
      theme: NordicTheme.build(NordicTokens.light),
      darkTheme: NordicTheme.build(NordicTokens.dark),
      // 设计的主场是深色(近黑底靠光晕撑层次),系统没表态时按深色走。
      themeMode: mode.material,
      navigatorKey: navigatorKey,
      // 生命周期规则挂在 MaterialApp 的 builder 上而不是各页面里 ——
      // 它是应用级的一条,页面来去都不该影响它。
      builder: (context, child) =>
          _BackgroundPlayGuard(child: child ?? const SizedBox.shrink()),
      onGenerateRoute: AppRoutes.generate,
      routes: {
        ...AppRoutes.table,
        '/': (_) => const NordicShell(),
      },
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