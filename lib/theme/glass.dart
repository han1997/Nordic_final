import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'context_ext.dart';
import 'tokens.dart';

/// 磨砂玻璃材质 —— `styles.css` 里 `.glass` / `.glass-panel` / `.glass-thin` 的等价物。
///
/// 三层做法:半透明底 + 模糊身后 + **上缘一道高光内描边**。
/// 那道高光是玻璃感的关键 —— 没有它,半透明色块只会读成「一块灰」。
///
/// 注意:玻璃必须真的**浮在内容之上**才有东西可模糊。放在正常流里、
/// 身后是空的,模糊出来只是一块灰。
class NordicGlass extends StatelessWidget {
  const NordicGlass({
    super.key,
    required this.child,
    this.panel = NordicGlassPanel.thin,
    this.borderRadius,
    this.blurOverride,
    this.saturationOverride,
    this.border = true,
    this.shadow = true,
  });

  final Widget child;
  final NordicGlassPanel panel;

  /// 未指定时跟随面板默认圆角。
  final BorderRadius? borderRadius;

  /// 需要按组件微调模糊半径时用(如顶栏比面板更薄)。
  final double? blurOverride;
  final double? saturationOverride;

  final bool border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final spec = switch (panel) {
      // 面板玻璃:卡片 / 弹层 / 分段控件 —— 底下的内容透得最少,文字最稳。
      NordicGlassPanel.panel => (t.glass3, t.blur, NordicRadius.lg, shadow),
      // 薄玻璃:输入框 / 筛选胶囊 —— 能透出较多背景,但不承载长文本。
      NordicGlassPanel.thin => (t.glass4, t.blurSm, NordicRadius.full, false),
      // 导航玻璃:播放坞 / 标签栏 —— 常驻且要压住滚过去的列表。
      NordicGlassPanel.nav => (t.glass, t.blur, NordicRadius.full, shadow),
    };
    final fill = spec.$1;
    final blur = blurOverride ?? spec.$2;
    final radius = borderRadius ?? BorderRadius.circular(spec.$3);
    final wantsShadow = spec.$4;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        // 原型是 `blur(...) saturate(...)`;dart:ui 的 ColorFilter 本身就是
        // 一种 ImageFilter,compose 起来就能得到同一套效果。
        filter: ui.ImageFilter.compose(
          outer: _saturationFilter(saturationOverride ?? t.glassSaturation),
          inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: border ? Border.all(color: t.line2, width: 1) : null,
            boxShadow: [
              if (wantsShadow)
                BoxShadow(color: t.depth, blurRadius: 40, offset: const Offset(0, 20)),
              // 上缘高光 —— 玻璃感的关键,始终保留。
              BoxShadow(color: t.glassRim, blurRadius: 0, offset: const Offset(0, 1), spreadRadius: -0.5),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  /// 饱和度矩阵。亮度权重用 Rec.709(与浏览器 backdrop-filter 的口径一致)。
  /// 系数为 1 时是单位阵,直接跳过 filter,免得白吃一层合成。
  static ui.ImageFilter _saturationFilter(double s) {
    if ((s - 1).abs() < 0.01) return ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0);
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
    final ir = (1 - s) * lr;
    final ig = (1 - s) * lg;
    final ib = (1 - s) * lb;
    return ui.ColorFilter.matrix(<double>[
      ir + s, ig, ib, 0, 0, //
      ir, ig + s, ib, 0, 0, //
      ir, ig, ib + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ]);
  }
}

enum NordicGlassPanel {
  /// 卡片 / 弹层 / 分段控件。
  panel,

  /// 输入框 / 筛选胶囊。
  thin,

  /// 播放坞 / 标签栏。
  nav,
}

/// 玻璃上的 1px 发丝分隔线 —— `.divider`。
class NordicDivider extends StatelessWidget {
  const NordicDivider({super.key, this.indent = NordicSpace.s5, this.endIndent});

  final double indent;
  final double? endIndent;

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        endIndent: endIndent ?? indent,
        color: context.nordic.line,
      );
}