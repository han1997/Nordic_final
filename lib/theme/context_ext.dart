import 'package:flutter/material.dart';

import 'accent.dart';
import 'tokens.dart';

/// 取 token 与强调色的统一入口。
///
/// token 挂在 `ThemeData.extensions` 上而不是自建 InheritedWidget ——
/// 这样 `MaterialApp` 的深浅切换、系统栏、文字缩放全都照常工作,
/// 不必再包一层。强调色则走 [NordicAccentScope],因为它是**运行时按内容变化**的。
extension NordicContextX on BuildContext {
  /// 当前主题的设计 token。assert 而非 ?? 兜底:缺 token 是接线错误,
  /// 静默回退成默认主题只会让样式问题更难查。
  NordicTokens get nordic {
    final tokens = Theme.of(this).extension<NordicTokens>();
    assert(tokens != null, '主题里没有 NordicTokens：检查 NordicTheme.build');
    return tokens!;
  }

  /// 当前强调色。不在沉浸页时返回中性命中色(与原型一致)。
  NordicAccent get accent => NordicAccentScope.of(this);

  /// 压深到足够对比度的强调色 —— **只用于画文字**。
  /// 描边 / 光晕 / 选中底色用 `accent.accent` 原色。
  Color get accentSafe => accent.safe(nordic.brightness);

  bool get isDark => nordic.isDark;
}