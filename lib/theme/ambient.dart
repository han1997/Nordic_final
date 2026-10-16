import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'accent.dart';
import 'context_ext.dart';

/// 沉浸式页面的氛围背景 —— `.ambient` 的等价物。
///
/// 三层径向渐变(强调色 / 封面主色 / 强调色)叠在一起后整体模糊,
/// 再用一层自上而下的压暗把内容区托亮。深色下这层是界面层次的主要来源,
/// 浅色下 `glow` 把强度压到 0.14,只剩一点温度。
class NordicAmbient extends StatelessWidget {
  const NordicAmbient({super.key, this.accent});

  /// 不传则取 [NordicAccentScope] —— 沉浸页里通常就是当前封面。
  final NordicAccent? accent;

  /// 原型 `filter: blur(62px)`。浅色下收一点,浅底上大半径会糊成一片。
  static const _blurDark = 62.0;
  static const _blurLight = 34.0;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final a = accent ?? context.accent;
    final blur = t.isDark ? _blurDark : _blurLight;

    return Positioned.fill(
      child: IgnorePointer(
        // 单独一层:这层模糊对同一套配色是**完全静态**的(内容在它上面滚,
        // 它自己不动),隔成一层才可能被光栅缓存住,不必每帧重算一遍。
        child: RepaintBoundary(
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: CustomPaint(
                painter: _AmbientPainter(
                  accent: a.accent,
                  c1: a.c1,
                  glow: t.glow,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 只画三层光晕。压暗单独一层,免得跟着一起被模糊掉
/// (模糊之后的压暗层边缘会发虚,屏幕上下会露出没压住的亮边)。
class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.accent,
    required this.c1,
    required this.glow,
  });

  final Color accent;
  final Color c1;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    // 原型的 ::before 是 inset:-28%,光晕铺得比屏幕大一圈,
    // 这样模糊之后边缘不会露出硬边。
    final bleed = Rect.fromLTWH(
      -size.width * 0.28,
      -size.height * 0.28,
      size.width * 1.56,
      size.height * 1.56,
    );

    // 三层渐变各自独立画,而不是拼成一个 shader —— 每层的圆心与半径
    // 都不一样,叠起来才是原型那种「左上偏冷、右下有底光」的味道。
    void glowLayer(Alignment center, double radius, Color color, double strength) {
      final alpha = strength * glow;
      if (alpha <= 0.001) return;
      canvas.drawRect(
        bleed,
        Paint()
          ..shader = RadialGradient(
            center: center,
            radius: radius,
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
          ).createShader(bleed),
      );
    }

    glowLayer(const Alignment(-0.52, -0.80), 0.62, accent, 0.66);
    glowLayer(const Alignment(0.64, -0.52), 0.58, c1, 0.78);
    glowLayer(const Alignment(0.0, 0.92), 0.72, accent, 0.42);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.accent != accent || old.c1 != c1 || old.glow != glow;
}

/// 氛围背景之上的压暗层 —— `.ambient::after`。
/// 单独一个 widget,不被模糊,保证屏幕边缘的压暗是实的。
class NordicAmbientShade extends StatelessWidget {
  const NordicAmbientShade({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Positioned.fill(
      child: IgnorePointer(
        // 同上:压暗层也是静态的,隔一层交给缓存。
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  t.shade,
                  Color.lerp(t.shade, t.shade2, 0.72)!,
                  t.shade2,
                ],
                stops: const [0.0, 0.44, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }
}