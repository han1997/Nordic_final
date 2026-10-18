// 服务器地址的规范化与线路命名。
//
// 原先这三件事各写了两份:`servers_screen.dart` 里有
// `_normalizeUrl` / `_routeNameFor` / `_tagFor` / `_looksLocal` 四个静态方法,
// `add_route_screen.dart` 里又有一份 `_normalized`(逐字相同)。扫码同步的载荷
// 解码还要用第三份 —— 三份一模一样的东西迟早只改一处,表现成「这个入口能填的
// 地址,那个入口填不进去」(与 `toggleRouteLock` 当初被写两遍是同一类问题,
// 见 `server_route.dart`)。
//
// 所以收成这一份。纯 Dart:不碰 Flutter,能裸 `test()` 覆盖。

import 'server_route.dart';

/// 规范化一个服务器地址:补 `http://`、去掉尾斜杠。
///
/// **只认 http / https** —— 别的前缀直接判不合法。早先的写法是「不是
/// `http://` / `https://` 开头就补一个 `http://`」,于是 `ftp://x` 会被拼成
/// `http://ftp://x`:那串解析得出来(`host` 是 `ftp`)、因此一路通过校验,
/// 但连不上,用户看到的是一个莫名其妙的网络错误。现在它走「不合法」那一支,
/// 界面说的是既有的那句「地址要以 http:// 或 https:// 开头。」
String? normalizeServerUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final hasScheme = value.startsWith('http://') || value.startsWith('https://');
  // 带协议头却不认识:不硬补,判不合法(见上)。
  if (!hasScheme && value.contains('://')) return null;
  final full = hasScheme ? value : 'http://$value';
  final uri = Uri.tryParse(full);
  if (uri == null || uri.host.isEmpty) return null;
  return full.replaceAll(RegExp(r'/+$'), '');
}

/// 从地址里起个线路名 —— 内网地址标「局域网直连」,其余用主机名。
String routeNameFor(String url) {
  final host = Uri.tryParse(url)?.host ?? url;
  return looksLocal(host) ? '局域网直连' : host;
}

/// 从地址推线路标记。**标记只影响显示**,择优仍按实测延迟来
/// (见 `SubsonicClient.activeRoute` 的三级优先)。
RouteTag tagFor(String url) {
  final host = Uri.tryParse(url)?.host ?? url;
  return looksLocal(host) ? RouteTag.lan : RouteTag.wan;
}

/// 私有网段判定 —— 只为给线路起个像样的名字,不做任何安全判断。
bool looksLocal(String host) {
  if (host == 'localhost' || host.startsWith('127.')) return true;
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final first = int.tryParse(parts[0]);
  final second = int.tryParse(parts[1]);
  if (first == null || second == null) return false;
  if (first == 10) return true;
  if (first == 192 && second == 168) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  return false;
}