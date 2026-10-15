import 'package:flutter/foundation.dart';

/// 转码档位 —— 原型 `QUALITIES` 的四档。
///
/// 档位最终落成 `stream` 端点的两个查询参数:
/// [maxBitRate](kbps)与 [format]。**原音档两者都不传**,直接取原文件 ——
/// 传了 format 就等于转码,哪怕码率写得再高,那也是重编码过的一道。
@immutable
class QualityOption {
  const QualityOption({
    required this.id,
    required this.name,
    required this.description,
    this.maxBitRate,
    this.format,
    this.tag,
  });

  final String id;
  final String name;
  final String description;

  /// null = 不限制码率(原音直出)。
  final int? maxBitRate;

  /// null = 不转码(保持原始容器)。
  final String? format;

  /// 卡片上的小标签,如「无损」。
  final String? tag;

  /// 是否原音直出。界面上用来决定「线路」提示的措辞 ——
  /// 局域网才建议走原音,公网走原音容易卡。
  bool get isOriginal => maxBitRate == null && format == null;

  /// 原型里的四档,顺序即界面顺序。
  static const original = QualityOption(
    id: 'original',
    name: '原音直出',
    description: '不转码,按原始文件播放。仅建议在局域网使用。',
    tag: '无损',
  );

  static const high = QualityOption(
    id: 'high',
    name: '高质量',
    description: '转码为 320 kbps。音质接近原始,流量约减半。',
    maxBitRate: 320,
    format: 'mp3',
  );

  static const medium = QualityOption(
    id: 'medium',
    name: '均衡',
    description: '转码为 192 kbps。移动网络下推荐,拖动进度更快。',
    maxBitRate: 192,
    format: 'mp3',
  );

  static const low = QualityOption(
    id: 'low',
    name: '省流',
    description: '转码为 96 kbps。弱网或流量紧张时使用。',
    maxBitRate: 96,
    format: 'mp3',
  );

  static const all = [original, high, medium, low];

  /// 原型默认「均衡」—— 移动网络下的稳妥选择。
  static const fallback = medium;

  static QualityOption byId(String? id) =>
      all.where((q) => q.id == id).firstOrNull ?? fallback;
}

/// 当前档位的持有者。
///
/// 单独一个可变对象(而不是散在设置里),是为了让 [NordicAudioHandler]
/// 与设置页、播放页共享同一个真值 —— 三方各存一份的话,
/// 界面上显示「均衡」而实际按「原音」在请求,这种事迟早发生。
class QualityController extends ValueNotifier<QualityOption> {
  QualityController([QualityOption? initial])
      : super(initial ?? QualityOption.fallback);

  void set(QualityOption option) {
    if (value == option) return;
    value = option;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}