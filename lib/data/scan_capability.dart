import 'package:flutter/foundation.dart';

/// 「这台设备能不能**扫码**」。
///
/// **为什么不用 `dart:io` 的 `Platform.isAndroid`**:web 上那个 `Platform` 的每个
/// 取值都抛 `UnsupportedError`(见 dart2js 的 io_patch),而它继承的是 `Error`
/// 不是 `Exception` —— `on Exception` 接不住,只能裸 `catch`,于是「不是安卓」
/// 与「根本问不出来」这两种情况分不开。
///
/// **为什么只用 `defaultTargetPlatform` 也不够**:它的名字有欺骗性 —— Android 上
/// 的 Chrome 报的就是 `TargetPlatform.android`。只看它,网页上会把摄像头那一支
/// 建起来,顺带把 mobile_scanner 的 web 实现拖进来,而那个实现要**页面自己去
/// unpkg 取 `@zxing`**(见它的 `BarcodeReader.maybeLoadLibrary`)。本仓库明令不许
/// 有运行时的 CDN 依赖 —— 理由与 CanvasKit 那条一模一样:取不到的表现是**卡住、
/// 不报错**。所以两个条件必须**一起**看。
///
/// 形状照 `NetworkProbe` / `DownloadStore`:生产走 [ScanCapability.auto],
/// 测试传一份 [ScanCapability.fixed] 进来。问不出来的地方**当作没有** ——
/// 这不是安全判断,是「这台设备有没有那个硬件与实现」;没有就退到粘贴文本,
/// 而不是把入口锁掉。
class ScanCapability {
  /// 这台设备真实的取值。
  ///
  /// 不是 const:[defaultTargetPlatform] 是运行时取值(测试还能用
  /// `debugDefaultTargetPlatformOverride` 改它),不像 [kIsWeb] 那样是编译期常量。
  factory ScanCapability.auto() => ScanCapability.fixed(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      );

  /// 把两个入参钉死 —— 于是「安卓上的 Chrome」这种组合在测试里能真的构造出来。
  const ScanCapability.fixed({required this.isWeb, required this.platform});

  final bool isWeb;
  final TargetPlatform platform;

  /// 只有**原生的** Android / iOS 算数。
  ///
  /// web 一律不算(哪怕浏览器正跑在安卓上);桌面一律不算 —— `mobile_scanner`
  /// 的平台清单里只有 android / ios / macos / web,别的目标连构建都不参与
  /// (与 `just_audio_windows` 那条是同一个道理)。
  bool get isSupported =>
      !isWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
}