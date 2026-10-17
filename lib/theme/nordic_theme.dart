import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// 组装两套 `ThemeData`。
///
/// 结构只有一份:组件长什么样、在哪儿,全部写在共享组件里;
/// 这里只把 token 塞进 `extensions`,再对齐 Material 自己那几项
/// (字体、水波纹、分割线),让没被我们接管的地方也不跑偏。
abstract final class NordicTheme {
  /// 系统栏样式按亮度分两套 —— 深色下状态栏图标要发白。
  /// 放在这里供沉浸页复用(它们会临时切换系统栏)。
  static SystemUiOverlayStyle overlayFor(NordicTokens tokens) =>
      tokens.isDark
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.light,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.dark,
            );

  /// 两套 `ThemeData` 各只建一次。
  ///
  /// [build] 对同一份 token 是纯函数,而它的开销主要来自 `ColorScheme.fromSeed`
  /// 那趟调色计算 —— 根节点(`app.dart`)每次重建都要拿到这两份,
  /// 放在静态 final 里(Dart 的静态 final 是首次访问才求值,就是懒的)
  /// 就从「每次通知算两遍」变成「每进程算一遍」。
  static final light = build(NordicTokens.light);
  static final dark = build(NordicTokens.dark);

  static ThemeData build(NordicTokens tokens) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C8CFF),
      brightness: tokens.brightness,
    ).copyWith(
      surface: tokens.bg,
      onSurface: tokens.fg,
      primary: tokens.fg,
      onPrimary: tokens.bg,
      outline: tokens.line2,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: tokens.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.bg,
      canvasColor: tokens.bg,
      // 原型是自绘的视觉体系,Material 的这几层默认色反而会串味。
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: tokens.line,
      extensions: [tokens],
      textTheme: _textTheme(tokens),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: tokens.fg,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.glass3,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.glass,
        contentTextStyle: TextStyle(color: tokens.fg, fontSize: NordicType.sm),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.fg,
        linearTrackColor: tokens.fill2,
      ),
      iconTheme: IconThemeData(color: tokens.fg, size: 22),
    );
  }

  /// 字阶对齐 `--fs-*`。字体族不指定 —— 交给系统,
  /// 中文会落到 PingFang / HarmonyOS Sans / 微软雅黑,与原型同一条回退链。
  static TextTheme _textTheme(NordicTokens tokens) {
    final fg = tokens.fg;
    return TextTheme(
      displaySmall: TextStyle(fontSize: NordicType.display, fontWeight: FontWeight.w700, letterSpacing: -0.04, color: fg, height: 1.08),
      headlineLarge: TextStyle(fontSize: NordicType.h1, fontWeight: FontWeight.w700, letterSpacing: -0.035, color: fg, height: 1.1),
      headlineMedium: TextStyle(fontSize: NordicType.h2, fontWeight: FontWeight.w700, letterSpacing: -0.03, color: fg),
      headlineSmall: TextStyle(fontSize: NordicType.h3, fontWeight: FontWeight.w700, letterSpacing: -0.02, color: fg),
      titleMedium: TextStyle(fontSize: NordicType.lg, fontWeight: FontWeight.w600, letterSpacing: -0.012, color: fg),
      titleSmall: TextStyle(fontSize: NordicType.md, fontWeight: FontWeight.w600, letterSpacing: -0.015, color: fg),
      bodyLarge: TextStyle(fontSize: NordicType.lg, fontWeight: FontWeight.w600, letterSpacing: -0.012, color: fg),
      bodyMedium: TextStyle(fontSize: NordicType.md, fontWeight: FontWeight.w400, color: fg),
      bodySmall: TextStyle(fontSize: NordicType.sm, fontWeight: FontWeight.w400, color: tokens.fg3),
      labelSmall: TextStyle(fontSize: NordicType.xs, fontWeight: FontWeight.w600, color: tokens.fg3),
    );
  }
}