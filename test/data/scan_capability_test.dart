import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/scan_capability.dart';

/// 「这台设备能不能扫码」—— 一条**能力判断**,不是一个安全判断。
///
/// 这里钉住的核心是那一条:**浏览器跑在安卓上也不算**。只看
/// `defaultTargetPlatform` 的话,安卓上的 Chrome 会被当成安卓,于是网页上会把
/// `MobileScanner` 建起来,而它的 web 实现要页面自己去 unpkg 取 `@zxing` ——
/// 本仓库不许有运行时的 CDN 依赖(与 CanvasKit 那条同一个理由:取不到的表现是
/// 卡住、不报错)。
void main() {
  test('原生安卓 / iOS 可以扫', () {
    expect(
      const ScanCapability.fixed(isWeb: false, platform: TargetPlatform.android)
          .isSupported,
      isTrue,
    );
    expect(
      const ScanCapability.fixed(isWeb: false, platform: TargetPlatform.iOS)
          .isSupported,
      isTrue,
    );
  });

  test('安卓上的 Chrome 不行 —— 这正是两个条件要一起看的理由', () {
    expect(
      const ScanCapability.fixed(isWeb: true, platform: TargetPlatform.android)
          .isSupported,
      isFalse,
      reason: '浏览器报出来的平台就是 android，但那不是一台安卓应用',
    );
  });

  test('桌面一律不行（mobile_scanner 没有那几个平台的实现）', () {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      expect(
        ScanCapability.fixed(isWeb: false, platform: platform).isSupported,
        isFalse,
        reason: '$platform 应当退到粘贴文本',
      );
      expect(
        ScanCapability.fixed(isWeb: true, platform: platform).isSupported,
        isFalse,
      );
    }
  });

  test('问不出个所以然的地方当作「没有」', () {
    // fuchsia 这类我们没打算支持的目标一样是「没有那个能力」。
    expect(
      const ScanCapability.fixed(isWeb: false, platform: TargetPlatform.fuchsia)
          .isSupported,
      isFalse,
    );
  });
}