package com.nordic.app

import com.ryanheise.audioservice.AudioServiceActivity

/// 必须继承 [AudioServiceActivity] 而不是 FlutterActivity ——
/// 后台播放的媒体会话要把 Activity 与前台服务绑在一起,
/// 换回 FlutterActivity 后通知栏点回来会失效。
class MainActivity : AudioServiceActivity()