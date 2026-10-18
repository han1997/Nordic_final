// 「扫码同步」的载荷编解码 —— 导出与导入**共用这一份**。
//
// 二维码里那串与「复制文本」复制走的那串**是同一个字符串**,不是两套格式:
// 有相机的设备扫码,没相机的那台(Windows 桌面 / 浏览器)粘贴同一串。只要一份
// 实现,就只会有一种读法。
//
// 纯 Dart:不碰 Flutter、不碰 channel,于是能像 `sorting.dart` 那样裸 `test()`
// 覆盖,不需要 binding、不需要假存储。

import 'dart:convert';

import 'server_config.dart';
import 'server_route.dart';
import 'server_url.dart';

/// 一段载荷读出来的东西 —— **还没落盘**,也还不是 [ServerConfig]。
///
/// 少的那几样都是「原来那台设备自己的」:
///   - `ServerConfig.id`:由落盘时的调用方发(`AppState.connect` 的
///     `_server?.id ?? 'server-1'`);
///   - `lastScannedAt`:「本机上次扫描」对目标机没有意义;
///   - 各条线路的 `id`:导入时重发成 `route-1..route-N`(与 `servers_screen`
///     表单造线路同一个口径)。**所以解码不能复用 `ServerRoute.fromJson`** ——
///     那个读 `json['id']`,载荷里根本没有这个键。
class TransferredServer {
  const TransferredServer({
    required this.kind,
    required this.name,
    required this.username,
    required this.routes,
    this.password,
    this.droppedRoutes = 0,
  });

  final ServerKind kind;
  final String name;
  final String username;
  final List<ServerRoute> routes;

  /// 这段载荷带的密码。null = **没带**(导出那张纸上的开关默认就是关着的)。
  final String? password;

  /// 载荷里写了几条、但地址规范化之后落不下几条 —— 界面拿这个数说明
  /// 「N 条线路里读出 M 条」,而不是静默吞掉。
  final int droppedRoutes;

  bool get carriedPassword => password != null;

  /// 落成一份真配置。[id] 由调用方给 —— 与 `AppState.connect` 同一个口径。
  ServerConfig toServerConfig({required String id}) => ServerConfig(
        id: id,
        name: name,
        kind: kind,
        username: username,
        routes: routes,
      );
}

/// 解码结果。
///
/// 用 sealed 而不是「返回 null + 抛异常」:`decode` 面对着的是**用户手上一段
/// 来路不明的东西**(扫错了码、只复制了一半),每一种读不出来都得有一句能照着
/// 做的话。抛异常会把这段文本的坏处转嫁给整屏。
sealed class TransferResult {
  const TransferResult();
}

final class TransferOk extends TransferResult {
  const TransferOk(this.server);

  final TransferredServer server;
}

final class TransferFailed extends TransferResult {
  const TransferFailed(this.reason);

  final TransferError reason;
}

/// 读不出来的每一种情况,各带一句给用户看的话。
///
/// 这些句子是 `lib/` 里的中文字面量,所以标点守卫
/// (`test/ui/copy_punctuation_test.dart`)免费看着它们 —— 标点要全角。
enum TransferError {
  empty('还没有内容 —— 先扫二维码，或者粘贴一段配置文本。'),
  tooLong('这段文本太长了，不像是一份配置。'),
  wrongScheme('这段文本不是 Nordic 的配置 —— 检查一下有没有复制完整。'),
  unsupportedVersion('这段配置来自另一个版本的 Nordic，当前版本读不了。'),
  badEncoding('这段配置的编码坏了 —— 重新扫一次，或者重新复制一遍。'),
  badJson('这段配置的内容读不出来 —— 重新扫一次，或者重新复制一遍。'),
  missingFields('这段配置缺了服务器信息，可能没有复制完整。'),
  unknownKind('这段配置里的接入类型不认识 —— 当前版本接不了。'),
  noRoute('这段配置里没有可用的服务器地址。');

  const TransferError(this.message);

  /// 给用户看的那句话。**别拿它当判据** —— 判据是枚举本身,文案会改。
  final String message;
}

/// 「扫码同步」的载荷编解码。
abstract final class ConfigTransfer {
  /// 版本号放在**路径**里而不是 query:解码器能在碰 base64 之前,就用一句准确的
  /// 话拒掉别的版本(而不是解到一半报「编码坏了」,让用户去重扫一遍)。
  static const prefix = 'nordic://config/1/';

  static const _version = 1;

  /// 粗筛:一段真实载荷(3 条线路)约 460 字符,4 条长主机名加密码约 700。
  /// 上到 8192 的,是「这显然不是一段配置」,不是二维码的精确容量上限。
  static const maxLength = 8192;

  /// 把一份配置编成载荷。
  ///
  /// [password] 传 null 就**整个键都不写** —— 不是写个 null。「开关关着时这段
  /// 文本里不该出现任何与密码有关的痕迹」这件事,在字节层面就该成立。
  static String encode({
    required ServerKind kind,
    required String name,
    required String username,
    required List<ServerRoute> routes,
    String? password,
  }) {
    final payload = <String, Object?>{
      'v': _version,
      // 键取短的:这串东西的密度直接决定二维码要多少模块(见那几张体积估算)。
      'kind': kind.name,
      'name': name,
      'user': username,
      'routes': [
        for (final r in routes)
          <String, Object?>{
            'n': r.name,
            'u': r.url,
            't': r.tag.name,
            's': r.selected,
          },
      ],
      if (password != null && password.isNotEmpty) 'pw': password,
    };
    // base64url 且去掉 `=`:那两三个字符在二维码里是白占的模块,而解码前补回来
    // 只是一行(见 [_pad])。
    return prefix +
        base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  }

  /// 读一段载荷。**不抛异常** —— 每种失败都落在一个 [TransferError] 上
  /// (与 `ConfigStore.loadServer` 同一姿势:坏数据不该把整屏打崩)。
  static TransferResult decode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const TransferFailed(TransferError.empty);
    if (text.length > maxLength) {
      return const TransferFailed(TransferError.tooLong);
    }
    if (!text.startsWith(prefix)) {
      // 认得是我们的协议、只是版本对不上时说「版本」;别的一律说「不是配置」。
      return TransferFailed(
        text.startsWith('nordic://')
            ? TransferError.unsupportedVersion
            : TransferError.wrongScheme,
      );
    }

    final List<int> bytes;
    try {
      bytes = base64Url.decode(_pad(text.substring(prefix.length)));
    } catch (_) {
      return const TransferFailed(TransferError.badEncoding);
    }

    final String decoded;
    try {
      decoded = utf8.decode(bytes);
    } catch (_) {
      return const TransferFailed(TransferError.badEncoding);
    }

    final Object? parsed;
    try {
      parsed = jsonDecode(decoded);
    } catch (_) {
      return const TransferFailed(TransferError.badJson);
    }
    if (parsed is! Map) return const TransferFailed(TransferError.badJson);
    final json = parsed.cast<String, dynamic>();

    if (json['v'] != _version) {
      return const TransferFailed(TransferError.unsupportedVersion);
    }

    final username = json['user'];
    if (username is! String || username.trim().isEmpty) {
      return const TransferFailed(TransferError.missingFields);
    }

    // 认不出接入类型就**拒掉**,不像 `ServerConfig.fromJson` 那样退回
    // navidrome:那份配置是从**另一台设备**来的,静默按某一档连上去,错误要到
    // 连不上库的时候才显形,那时用户已经不知道自己扫的是哪一份了。
    final kind = _kindFor(json['kind']);
    if (kind == null) return const TransferFailed(TransferError.unknownKind);

    final name = json['name'];
    final routes = <ServerRoute>[];
    var dropped = 0;
    // 锁定是单选语义(见 `toggleRouteLock`):留两条 selected 会让 `activeRoute`
    // 取哪一条不确定,所以只认第一条。
    var locked = false;

    final rawRoutes = json['routes'];
    if (rawRoutes is List) {
      for (final entry in rawRoutes) {
        if (entry is! Map) {
          dropped++;
          continue;
        }
        final rawUrl = entry['u'];
        final url = normalizeServerUrl(rawUrl is String ? rawUrl : '');
        if (url == null) {
          dropped++;
          continue;
        }
        final entryName = entry['n'];
        final wantsLock = entry['s'] == true && !locked;
        if (wantsLock) locked = true;
        routes.add(
          ServerRoute(
            // 线路 id 在这里重发:载荷里那份是**原来那台设备**的键,与本机的
            // 测速结果、锁定状态都对不上。
            id: 'route-${routes.length + 1}',
            name: (entryName is String && entryName.trim().isNotEmpty)
                ? entryName.trim()
                : routeNameFor(url),
            url: url,
            tag: _tagFor(entry['t'], url),
            selected: wantsLock,
          ),
        );
      }
    }
    if (routes.isEmpty) return const TransferFailed(TransferError.noRoute);

    final rawPassword = json['pw'];
    return TransferOk(
      TransferredServer(
        kind: kind,
        name: name is String && name.trim().isNotEmpty ? name.trim() : kind.label,
        username: username.trim(),
        routes: routes,
        password: rawPassword is String && rawPassword.isNotEmpty
            ? rawPassword
            : null,
        droppedRoutes: dropped,
      ),
    );
  }

  static ServerKind? _kindFor(Object? name) {
    for (final kind in ServerKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  /// 标记认不出就退回地址推出来的那个 —— 与 `ServerRoute.fromJson` 同一条兜底。
  /// 标记本来就只影响显示。
  static RouteTag _tagFor(Object? name, String url) {
    for (final tag in RouteTag.values) {
      if (tag.name == name) return tag;
    }
    return tagFor(url);
  }

  /// 补回 base64 的 `=`:编码时去掉了,而 Dart 的解码器要求长度是 4 的倍数。
  /// 长度本来就对(手工粘贴来的带 `=` 那一种)就原样返回。
  static String _pad(String value) => value.length % 4 == 0
      ? value
      : value.padRight((value.length + 3) ~/ 4 * 4, '=');
}