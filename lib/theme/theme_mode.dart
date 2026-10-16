import 'package:flutter/material.dart';

import 'tokens.dart';

/// 主题模式偏好。
///
/// 默认**深色**而不是跟随系统:这个设计的主场是近黑底 + 封面光晕,
/// 浅色是「换一副材质」的备选。首次启动落在浅色上会让人以为是排版错了。
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

  /// 从落盘的名字还原。认不出来(没存过 / 存储损坏)时回默认深色。
  static NordicThemeMode byName(String? name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return NordicThemeMode.dark;
  }
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