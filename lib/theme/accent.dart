import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import 'tokens.dart';

/// 强调色:从当前封面提取,驱动光晕、进度条、选中态与按钮。
///
/// 原型里每张专辑手写了 `accent` / `c1` / `c2`;真实数据没有这些字段,
/// 所以这里做两件事:
///   1. 有封面图时从图片里提取主色([NordicAccent.fromImage]);
///   2. 没有封面(或提取失败)时,按条目标识**确定性**地派一套配色
///      ([NordicAccent.derived])——同一张专辑每次进来颜色一致,不会是随机的。
///
/// [safe] 是原型 `safeAccent()` 的等价物:浅色底上黄 / 绿 / 青这类高亮色
/// 对比度不够,逐档压深到阈值以下再用。**只用于画文字**,描边与光晕仍用原色。
@immutable
class NordicAccent {
  const NordicAccent({
    required this.accent,
    required this.c1,
    required this.c2,
  });

  /// 原色:画描边 / 光晕 / 选中底色。
  final Color accent;

  /// 封面渐变的两端(有真实封面时用于氛围背景兜底)。
  final Color c1;
  final Color c2;

  /// 原型 `ACCENT_CEIL`:浅色主题下只给「用强调色画文字」的地方压到这条线以下。
  static const _accentCeil = 168;

  /// 压深后的强调色。深色主题原样返回 —— 深底上高亮色本来就够亮。
  Color safe(Brightness brightness) {
    if (brightness == Brightness.dark) return accent;
    var r = (accent.r * 255).round();
    var g = (accent.g * 255).round();
    var b = (accent.b * 255).round();
    // 逐档 ×0.86,与原型的循环同构(最多 8 档,够把最亮的黄压到线下)。
    for (var i = 0; i < 8 && _maxChannel(r, g, b) > _accentCeil; i++) {
      r = (r * 0.86).round();
      g = (g * 0.86).round();
      b = (b * 0.86).round();
    }
    return Color.fromARGB(255, r, g, b);
  }

  static int _maxChannel(int r, int g, int b) =>
      r > g ? (r > b ? r : b) : (g > b ? g : b);

  /// 从封面图里提取主色。失败(图片损坏 / 全灰 / 无网络)时返回 null,
  /// 由调用方回退到 [derived] —— 不在这里兜底,免得掩盖住「图没取到」这件事。
  static Future<NordicAccent?> fromImage(ImageProvider provider) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 16,
        // 缩小解码尺寸:取色不需要原图分辨率,大图会拖慢进入沉浸页的速度。
        size: const Size(96, 96),
      );
      // 依次取「鲜明 → 主色 → 次鲜明」;全是灰阶时 PaletteGenerator 的
      // vibrant / dominant 可能都是 null,那就认输让调用方兜底。
      final picked = palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.mutedColor?.color;
      if (picked == null) return null;
      return NordicAccent(
        accent: _lift(picked),
        c1: palette.darkVibrantColor?.color ?? _darken(picked, 0.55),
        c2: _darken(palette.darkMutedColor?.color ?? picked, 0.82),
      );
    } catch (_) {
      return null;
    }
  }

  /// 按标识派生一套配色。用 FNV-1a 而不是 `hashCode`——
  /// Dart 的 String.hashCode 在不同运行间**不保证稳定**,那样同一张专辑
  /// 每次冷启动颜色都会变,「每张专辑有自己的气质」就散了。
  ///
  /// 派生结果是**记下来的**:同一个标识每次算出来的必须是同一套颜色(纯函数),
  /// 而每张封面、每个艺人牌在每次重建时都会来问一遍 —— 网格滚动时一帧里就是
  /// 几十个格子,每格都要算一次 FNV 哈希加三次 HSL 转色。
  static const _derivedLimit = 512;
  static final Map<String, NordicAccent> _derivedCache = {};

  static NordicAccent derived(String seed) {
    final hit = _derivedCache[seed];
    if (hit != null) return hit;

    final hue = (_fnv1a(seed) % 360).toDouble();
    // 与原型「新建歌单」的色板同构:hsl(h 42% 30%) → hsl(h 48% 12%)。
    final c1 = HSLColor.fromAHSL(1, hue, 0.42, 0.30).toColor();
    final c2 = HSLColor.fromAHSL(1, hue, 0.48, 0.12).toColor();
    // 强调色取同一个色相但更亮更饱和,才能在近黑底上跳出来。
    final accent = HSLColor.fromAHSL(1, hue, 0.68, 0.66).toColor();
    final value = NordicAccent(accent: accent, c1: c1, c2: c2);

    // 满了只挤掉最早那一份,而不是整体清空:一次横扫(库里几百张封面同时
// 算一遍)撞上「整体清空」时,后面每一格都会重新算一遍 —— 而重算的正是
// 刚刚才缓存过的那些。挤一份只让一格重新算。
    if (_derivedCache.length >= _derivedLimit) {
      _derivedCache.remove(_derivedCache.keys.first);
    }
    _derivedCache[seed] = value;
    return value;
  }

  /// 无封面时的中性兜底 —— 对应原型的 `--c1` / `--c2` 默认值。
  static NordicAccent neutral(Brightness brightness) {
    final t = NordicTokens.of(brightness);
    return NordicAccent(
      accent: const Color(0xFF7C8CFF),
      c1: t.coverPlaceholder1,
      c2: t.coverPlaceholder2,
    );
  }

  /// 图片主色常常偏暗(封面本身是深色的),直接拿去画进度条会看不清。
  /// 提到一个够用的亮度下限,同时保住色相 —— 每张专辑的「气质」靠色相区分。
  static Color _lift(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.lightness >= 0.5) return color;
    return hsl.withLightness(0.62).withSaturation(
          hsl.saturation.clamp(0.35, 1.0),
        ).toColor();
  }

  static Color _darken(Color color, double factor) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness * factor).clamp(0.0, 1.0)).toColor();
  }

  /// FNV-1a 32 位。取值稳定且分布够散,拿来当「从字符串派生色相」够用。
  static int _fnv1a(String input) {
    var hash = 0x811C9DC5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  @override
  bool operator ==(Object other) =>
      other is NordicAccent &&
      other.accent == accent &&
      other.c1 == c1 &&
      other.c2 == c2;

  @override
  int get hashCode => Object.hash(accent, c1, c2);
}

/// 把 [NordicAccent] 挂在 widget 树上,沉浸页(播放 / 专辑 / 艺人)与
/// 它们内部任意深度的组件都能取到当前配色,不用逐层传参。
class NordicAccentScope extends InheritedWidget {
  const NordicAccentScope({
    super.key,
    required this.accent,
    required super.child,
  });

  final NordicAccent accent;

  static NordicAccent of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<NordicAccentScope>();
    // 不在沉浸页里时退回中性命中色,与原型「强调色只在沉浸页生效」一致。
    if (scope == null) {
      return NordicAccent.neutral(
        ui.PlatformDispatcher.instance.platformBrightness,
      );
    }
    return scope.accent;
  }

  @override
  bool updateShouldNotify(NordicAccentScope oldWidget) =>
      oldWidget.accent != accent;
}