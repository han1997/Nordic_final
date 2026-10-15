import 'package:flutter/material.dart';

import 'tokens.dart';

/// 主题模式偏好。原型只有深 / 浅两档(没有「跟随系统」)——
/// 这里加上 follow 作为默认,但保留原型里那两个显式档。
enum NordicThemeMode {
  follow('跟随系统'),
  dark('深色'),
  light('浅色');

  const NordicThemeMode(this.label);

  final String label;

  ThemeMode get material => switch (this) {
        NordicThemeMode.follow => ThemeMode.system,
        NordicThemeMode.dark => ThemeMode.dark,
        NordicThemeMode.light => ThemeMode.light,
      };
}

/// 把 [NordicThemeMode] 解析成实际用的 token。
NordicTokens tokensFor(BuildContext context, NordicThemeMode mode) {
  final platformDark =
      MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
  return switch (mode) {
    NordicThemeMode.dark => NordicTokens.dark,
    NordicThemeMode.light => NordicTokens.light,
    NordicThemeMode.follow => platformDark ? NordicTokens.dark : NordicTokens.light,
  };
}