import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
      onGenerateRoute: AppRoutes.generate,
      routes: {
        ...AppRoutes.table,
        '/': (_) => const NordicShell(),
      },
    );
  }
}

/// 全局导航键 —— 播放通知栏点回来、以及「从任意位置跳播放页」都要用。
final navigatorKey = GlobalKey<NavigatorState>();