/// 打真服务器的那几组 live 用例的凭据 —— **从环境变量读,不进仓库**。
///
/// 仓库是公开的,而密码一旦提交就永远留在 git 历史里(删掉文件也没用)。
/// 所以这三个值一律来自环境:
///
/// ```bash
/// NORDIC_LIVE_URL=http://<服务器>:4533 \
/// NORDIC_LIVE_USER=<账号> \
/// NORDIC_LIVE_PASSWORD=<密码> \
/// flutter test
/// ```
///
/// 没设的时候退回一个**够不着的占位地址**(1 号端口上不会有 Navidrome):
/// 那几组用例照旧的「服务器不可达 → 整组跳过」那条路走,
/// 离线开发与 CI 平白失败的老毛病不复发。
library;

import 'dart:io';

/// 真服务器地址。没设环境变量时是一个够不着的占位地址 —— 于是整组跳过。
String get liveServerUrl {
  final raw = _env('NORDIC_LIVE_URL');
  return raw.isEmpty ? _unreachable : raw;
}

/// 账号。没设就是空串:空凭据会在 `pingRoute` 那一关失败,一样落到跳过那一支。
String get liveServerUser => _env('NORDIC_LIVE_USER');

/// 密码。同上。
String get liveServerPassword => _env('NORDIC_LIVE_PASSWORD');

/// 三个都配齐了没有。
///
/// 有些 live 用例**不碰网络、只断言拼出来的地址与参数**(封面鉴权参数、
/// 流地址指不指向当前线路)—— 没配环境变量时它们会拿着占位地址空跑一遍,
/// 断言虽然绿,却什么也没验到。那一类要照这一条跳过,而不是假绿。
bool get liveServerConfigured =>
    _env('NORDIC_LIVE_URL').isNotEmpty &&
    _env('NORDIC_LIVE_USER').isNotEmpty &&
    _env('NORDIC_LIVE_PASSWORD').isNotEmpty;

/// 够不着的占位地址 —— 它只是让「没配环境变量」与「服务器真的不在」
/// 走同一条降级路径,而不是在代码里另开一个分支。
const _unreachable = 'http://127.0.0.1:1';

String _env(String name) => Platform.environment[name]?.trim() ?? '';