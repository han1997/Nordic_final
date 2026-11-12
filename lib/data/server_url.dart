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
///
/// IPv6 也算上(表单的提示写着认 IPv6):`::1`、`fc00::/7` 唯一本地地址、
/// `fe80::/10` 链路本地地址,以及 `::ffff:a.b.c.d` 这种映射地址 ——
/// 最后一种要拆回 IPv4 再判一遍。IPv6 的主机串可能带方括号或 `%en0`
/// 这类 zone id,先剥掉。
///
/// 100.64.0.0/10 也归为「本地」:Tailscale / 运营商级 NAT 用的就是这一段,
/// NAS 用户从外面连回来时它比公网域名更像「直连」。这条只影响线路名与默认
/// 标记,不影响择优 —— 择优照旧看实测延迟。
bool looksLocal(String host) {
  var value = host.trim().toLowerCase();
  if (value.startsWith('[') && value.endsWith(']')) {
    value = value.substring(1, value.length - 1);
  }
  // zone id(`fe80::1%en0`)不是地址的一部分。
  final zone = value.indexOf('%');
  if (zone >= 0) value = value.substring(0, zone);

  if (value == 'localhost' || value == '::1') return true;

  // IPv4 映射的 IPv6:`::ffff:192.168.10.4` —— 拆出后走 IPv4 那一套。
  if (value.startsWith('::ffff:') && value.contains('.')) {
    return looksLocal(value.substring('::ffff:'.length));
  }

  if (value.contains(':')) return _looksLocalV6(value);

  final parts = value.split('.');
  if (parts.length != 4) return false;
  final first = int.tryParse(parts[0]);
  final second = int.tryParse(parts[1]);
  if (first == null || second == null) return false;
  if (first == 10) return true;
  if (first == 100 && second >= 64 && second <= 127) return true;
  if (first == 169 && second == 254) return true;
  if (first == 127) return true;
  if (first == 192 && second == 168) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  return false;
}

/// IPv6 的前两段(16 位)。压缩写法(`fd00::1`)第一段就在最前面;
/// `::1` 已经在上面的特判里处理掉,这里只看首段。
bool _looksLocalV6(String value) {
  final first = value.split(':').first;
  if (first.isEmpty) return false; // `::1` / `::` 之类
  final hextet = int.tryParse(first, radix: 16);
  if (hextet == null) return false;
  // fc00::/7 唯一本地地址;fe80::/10 链路本地地址。
  return (hextet & 0xfe00) == 0xfc00 || (hextet & 0xffc0) == 0xfe80;
}