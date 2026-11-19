import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 这台设备是什么形态 —— 目前只有一件:**是不是电视**。
///
/// 为什么不能从 `MediaQuery` 推出来:电视的逻辑宽也可能只有 960(1080p @
/// density 2),与平板横屏 / 小桌面窗完全同宽。宽高比、分辨率都会撞车。
/// 系统自己知道答案(`UiModeManager.UI_MODE_TYPE_TELEVISION`),所以走平台通道问
/// 一次,启动时问完再 `runApp` —— 一次调用,不架轮询。
///
/// 桌面与 Web 直接答「不是」:那边没有 leanback 这回事,键盘 / 鼠标的焦点
/// 仍按同一套走(见 `Pressable`),只是不额外放大字号。
abstract final class DeviceProfile {
  /// 通道名与 `android/.../MainActivity.kt` 的 `DEVICE_CHANNEL` 必须一致。
  static const channel = MethodChannel('fun.han1997.nordic/device');

  /// 电视为真;其余平台 / 通道不可用时为假。
  ///
  /// **失败按「不是电视」处理**:这个标记只影响字号与焦点环的尺寸,不该因为
  /// 一次平台调用失败把应用拦在启动之前。
  static Future<bool> isTelevision() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await channel.invokeMethod<bool>('isTelevision') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
