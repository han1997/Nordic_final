import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 胶片颗粒底纹 —— 原型 `.cover::after` 用的内联 SVG `feTurbulence`。
///
/// 这里程序化生成一张 64×64 的噪点图,首次用到时**异步**生成一次并缓存。
/// 之所以不放一张 PNG 进仓库:那点视觉差异不值得为它背一个二进制资源;
/// 之所以不每次现算:每张封面各画一遍噪点会明显掉帧。
class GrainTexture {
  GrainTexture._();

  static const _size = 64;

  static ui.Image? _image;
  static Future<ui.Image>? _pending;

  /// 已生成的颗粒图。没准备好时返回 null —— 调用方跳过颗粒层即可,
  /// 不要为了等它而留白(那会闪一下)。
  static ui.Image? get image => _image;

  /// 生成(或等待正在进行的生成)。幂等。
  static Future<ui.Image> ensure() {
    final ready = _image;
    if (ready != null) return Future.value(ready);
    return _pending ??= _generate().then((image) {
      _image = image;
      _pending = null;
      return image;
    });
  }

  static Future<ui.Image> _generate() async {
    // 固定种子:每次启动颗粒图案一致,冷启动之间不会「换一张底纹」。
    final random = math.Random(0x4E6F7264); // "Nord"
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    for (var y = 0; y < _size; y++) {
      for (var x = 0; x < _size; x++) {
        final v = random.nextInt(256);
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()..color = Color.fromARGB(255, v, v, v),
        );
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_size, _size);
    picture.dispose();
    return image;
  }

  /// 缩放后的小图(部分设备上直接平铺原分辨率会显得太细)。
  static Uint8List? _bytes;
  static Uint8List? get bytes => _bytes;
}

/// 颗粒叠加层。颗粒图就绪后自动重绘一次。
class GrainOverlay extends StatelessWidget {
  const GrainOverlay({super.key, this.opacity = 0.17});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: _GrainReady(
        builder: (image) => CustomPaint(
          painter: _GrainPainter(image: image, opacity: opacity),
        ),
      ),
    );
  }
}

/// 等颗粒图就绪后再画。用一个 [FutureBuilder] 而不是在 initState 里预取,
/// 因为多数封面在第一帧就该出图,不能为底纹让路。
class _GrainReady extends StatelessWidget {
  const _GrainReady({required this.builder});

  final Widget Function(ui.Image image) builder;

  @override
  Widget build(BuildContext context) {
    final ready = GrainTexture.image;
    if (ready != null) return builder(ready);
    return FutureBuilder<ui.Image>(
      future: GrainTexture.ensure(),
      builder: (context, snapshot) {
        final image = snapshot.data;
        return image == null ? const SizedBox.shrink() : builder(image);
      },
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.image, required this.opacity});

  final ui.Image image;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final paint = Paint()
      ..blendMode = BlendMode.overlay
      ..color = Color.fromARGB((opacity * 255).round(), 255, 255, 255);

    // 平铺 —— 64px 一格,尺寸取整避免边界出现半像素缝。
    for (var y = 0.0; y < size.height; y += image.height) {
      for (var x = 0.0; x < size.width; x += image.width) {
        canvas.drawImageRect(
          image,
          src,
          Rect.fromLTWH(
            x,
            y,
            math.min(image.width.toDouble(), size.width - x),
            math.min(image.height.toDouble(), size.height - y),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.image != image || old.opacity != opacity;
}