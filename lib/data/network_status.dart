import 'package:flutter/services.dart';

/// 当前网络的性质。**按「是否计费」回答,而不是按 Wi-Fi / 蜂窝** ——
/// 设置页那句「仅 Wi-Fi 下载」的实质是「流量下不缓存」,
/// 而系统知道得比传输类型更准:VPN 走蜂窝、按流量计费的手机热点,
/// 只看 TRANSPORT_* 都会判错。
enum NetworkStatus {
  /// 不计费的连接(Wi-Fi / 有线)。
  unmetered,

  /// 计费连接(蜂窝、计费热点)。
  metered,

  /// 没有网。
  offline,

  /// 问不出来(桌面 / iOS 没接这一路,或平台通道异常)。
  ///
  /// **当作「能用」处理**:门控是为了省流量,不是为了在问不出来的时候
  /// 把功能锁死 —— 那会让桌面端一句下载都发不出去。
  unknown;

  /// 现在能不能开始下载。
  bool get canTransfer => this != offline;
}

/// 网络状态探针。
///
/// Android 侧由 `MainActivity` 应答(系统 `ConnectivityManager`
/// 的 `isActiveNetworkMetered`);其它平台没有实现,一律回 [NetworkStatus.unknown]。
/// 通道名与 Android 侧常量必须一致。
class NetworkProbe {
  NetworkProbe({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'fun.han1997.nordic/network';

  final MethodChannel _channel;

  Future<NetworkStatus> status() async {
    try {
      final raw = await _channel.invokeMethod<String>('status');
      return switch (raw) {
        'unmetered' => NetworkStatus.unmetered,
        'metered' => NetworkStatus.metered,
        'offline' => NetworkStatus.offline,
        _ => NetworkStatus.unknown,
      };
    } on MissingPluginException {
      // 桌面 / 测试环境没有这个通道 —— 不是错误。
      return NetworkStatus.unknown;
    } catch (_) {
      // 通道在但应答不了(平台侧异常、绑定还没起来)。
      // 同样按「问不出来」处理:门控是为了省流量,不是为了让下载在
      // 问不出来的地方彻底不能用。
      return NetworkStatus.unknown;
    }
  }
}
