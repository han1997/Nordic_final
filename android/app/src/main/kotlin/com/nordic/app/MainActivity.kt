package com.nordic.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// 必须继承 [AudioServiceActivity] 而不是 FlutterActivity ——
/// 后台播放的媒体会话要把 Activity 与前台服务绑在一起,
/// 换回 FlutterActivity 后通知栏点回来会失效。
class MainActivity : AudioServiceActivity() {

    /// 网络状态通道。Dart 侧在 `lib/data/network_status.dart`,
    /// 两边通道名必须一致。
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NETWORK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(networkStatus())
                    else -> result.notImplemented()
                }
            }
    }

    /// 现在是什么网络 —— **按「是否计费」回答,不是按 Wi-Fi / 蜂窝**。
    ///
    /// 设置页那句「仅 Wi-Fi 下载」的实质是「流量下不缓存」。这个判断交给
    /// 系统最准:VPN 走蜂窝、按流量计费的手机热点,只看传输类型都会判错。
    private fun networkStatus(): String {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return "unknown"
        val network = manager.activeNetwork ?: return "offline"
        val capabilities = manager.getNetworkCapabilities(network) ?: return "unknown"
        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            return "offline"
        }
        return if (manager.isActiveNetworkMetered) "metered" else "unmetered"
    }

    companion object {
        private const val NETWORK_CHANNEL = "fun.han1997.nordic/network"
    }
}
