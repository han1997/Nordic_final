import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'subsonic_auth.dart';
import 'subsonic_payload.dart';

/// 一个服务器地址(线路)。同一个音乐库可以配多条 —— 内外网各一条,
/// 出门也能听。择优与故障切换都围绕它做。
class ServerRoute {
  const ServerRoute({
    required this.id,
    required this.name,
    required this.url,
    this.tag = RouteTag.lan,
    this.selected = false,
  });

  final String id;
  final String name;

  /// 不带尾斜杠的基址,如 `http://192.168.10.4:4533`。
  final String url;

  final RouteTag tag;

  /// 用户是否手动锁定了这条线路。锁定后不再自动切换(原型里的规则)。
  final bool selected;

  ServerRoute copyWith({String? name, String? url, RouteTag? tag, bool? selected}) =>
      ServerRoute(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        tag: tag ?? this.tag,
        selected: selected ?? this.selected,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'tag': tag.name,
        'selected': selected,
      };

  static ServerRoute fromJson(Map<String, dynamic> json) => ServerRoute(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        tag: RouteTag.values.firstWhere(
          (t) => t.name == json['tag'],
          orElse: () => RouteTag.lan,
        ),
        selected: json['selected'] as bool? ?? false,
      );
}

/// 线路标记 —— 原型「添加线路」页的三档。
enum RouteTag {
  lan('内网'),
  wan('公网'),
  relay('中继');

  const RouteTag(this.label);

  final String label;
}

/// 一条线路的可用性与延迟。
class RoutePing {
  const RoutePing({required this.routeId, this.latency, this.error});

  final String routeId;

  /// 往返延迟。null 表示测速失败 —— 与「还没测(user 主动跳过的档位)」区分开:
  /// 前者是 [error] 非空,后者两者都空。
  final Duration? latency;

  final String? error;

  bool get isOk => latency != null && error == null;
}

/// 订阅式 HTTP 客户端:所有 Subsonic 请求都从这里出去。
///
/// 两条重要行为:
///   1. **自动择优** —— 未锁定线路时,请求发给当前最快的那条;
///   2. **故障切换** —— 当前线路网络失败(超时 / 连接被拒)时,
///      自动换到下一条可用线路再试一次。认证失败**不换**线
///      (密码错了换到哪条都错,换线只会让用户困惑)。
class SubsonicClient {
  SubsonicClient({
    required this.auth,
    required List<ServerRoute> routes,
    Dio? dio,
  })  : _routes = List.of(routes),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 20),
              // 自己判状态码,避免 Dio 把 4xx 直接抛成无上下文的异常。
              validateStatus: (_) => true,
            ));

  final SubsonicAuth auth;
  final Dio _dio;
  final List<ServerRoute> _routes;

  /// 当前生效的线路 id。优先级:用户锁定 > 实测最快 > 列表首条。
  String? _activeRouteId;

  /// 最近一次测速结果。
  final Map<String, RoutePing> _pings = {};

  List<ServerRoute> get routes => List.unmodifiable(_routes);

  Map<String, RoutePing> get pings => Map.unmodifiable(_pings);

  ServerRoute? get activeRoute {
    if (_routes.isEmpty) return null;
    final locked = _routes.where((r) => r.selected).firstOrNull;
    if (locked != null) return locked;
    final byId = _routes.where((r) => r.id == _activeRouteId).firstOrNull;
    if (byId != null) return byId;
    return _fastestAvailable ?? _routes.first;
  }

  /// 实测最快且可用的线路。测速失败的线路不参与择优 ——
  /// 只比 ping 值会把「不可用」当成「延迟很大」,选出一条其实连不上的线。
  ServerRoute? get _fastestAvailable {
    final ok = _routes
        .map((r) => (r, _pings[r.id]))
        .where((e) => e.$2 == null || e.$2!.isOk)
        .toList()
      ..sort((a, b) =>
          (a.$2?.latency ?? const Duration(days: 1))
              .compareTo(b.$2?.latency ?? const Duration(days: 1)));
    return ok.isEmpty ? null : ok.first.$1;
  }

  /// 批量测速。逐条并发,单条失败不影响其它条。
  Future<Map<String, RoutePing>> pingAll() async {
    final results = await Future.wait(_routes.map(pingRoute));
    for (final ping in results) {
      _pings[ping.routeId] = ping;
    }
    // 测速完让择优重新算一次。
    _activeRouteId = _fastestAvailable?.id;
    return pings;
  }

  /// 单条线路测速。用 `ping.view`(最轻的端点)量一次往返。
  Future<RoutePing> pingRoute(ServerRoute route) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _get(route, 'ping', const {});
      stopwatch.stop();
      return RoutePing(routeId: route.id, latency: stopwatch.elapsed);
    } on SubsonicException catch (e) {
      // 认证失败也算「这条线路通」—— 能回 40 说明网络是好的,
      // 只是凭据不对。否则用户填错密码时会看到所有线路都不可用。
      if (e.isAuthFailure) {
        stopwatch.stop();
        return RoutePing(routeId: route.id, latency: stopwatch.elapsed);
      }
      return RoutePing(routeId: route.id, error: e.message);
    } catch (e) {
      return RoutePing(routeId: route.id, error: '$e');
    }
  }

  /// 发一次请求并返回载荷。
  ///
  /// [path] 是不带 `.view` 的端点名(如 `getAlbumList2`)。
  /// 出错时抛 [SubsonicException];网络层失败会尝试下一条线路。
  Future<Map<String, dynamic>> call(
    String path, [
    Map<String, String> params = const {},
  ]) async {
    final candidates = _candidateOrder();
    if (candidates.isEmpty) {
      throw const SubsonicException('还没有配置任何服务器线路');
    }

    SubsonicException? lastError;
    for (final route in candidates) {
      try {
        final body = await _get(route, path, params);
        // 成功即认定这条线路可用,记下来供下次优先。
        _activeRouteId = route.id;
        return body;
      } on SubsonicException catch (e) {
        // 认证 / 业务错误:换线路不会有不同结果,直接抛。
        if (!e.isNetworkFailure) rethrow;
        lastError = e;
      }
    }
    throw lastError ?? const SubsonicException('所有线路都连不上');
  }

  /// 候选线路顺序:当前生效的排第一,其余按延迟升序兜底。
  List<ServerRoute> _candidateOrder() {
    final active = activeRoute;
    if (active == null) return const [];
    final rest = _routes.where((r) => r.id != active.id).toList()
      ..sort((a, b) =>
          (_pings[a.id]?.latency ?? const Duration(days: 1))
              .compareTo(_pings[b.id]?.latency ?? const Duration(days: 1)));
    return [active, ...rest];
  }

  Future<Map<String, dynamic>> _get(
    ServerRoute route,
    String path,
    Map<String, String> params,
  ) async {
    final uri = buildUri(route, path, params, auth);
    Response<String> response;
    try {
      response = await _dio.getUri<String>(
        uri,
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (e) {
      throw SubsonicException(_describeDioError(e, route));
    }

    if (response.statusCode != 200) {
      throw SubsonicException(
        '服务器返回 HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final raw = response.data;
    if (raw == null || raw.isEmpty) {
      throw const SubsonicException('响应为空');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // 拿到 HTML 通常意味着地址指到了一个网页(端口错了 / 被网关劫持),
      // 这是配置问题,不是网络抖动 —— 说清楚比抛 JSON 解析错更有用。
      throw SubsonicException(
        '${route.url} 返回的不是 Subsonic 响应,检查地址与端口',
        statusCode: 200,
      );
    }

    final envelope = SubsonicEnvelope.parse(body);
    if (!envelope.isOk) {
      final error = envelope.error;
      throw SubsonicException(
        error?.message ?? '服务器返回失败状态',
        code: error?.code,
      );
    }
    return body;
  }

  /// 拼出最终 URL。公开出来是为了让单元测试能直接钉住鉴权参数与路径格式。
  static Uri buildUri(
    ServerRoute route,
    String path,
    Map<String, String> params,
    SubsonicAuth auth, {
    String? salt,
  }) {
    final base = route.url.endsWith('/')
        ? route.url.substring(0, route.url.length - 1)
        : route.url;
    return Uri.parse('$base/rest/$path.view').replace(
      queryParameters: {
        ...auth.queryParams(salt: salt),
        ...params,
      },
    );
  }

  static String _describeDioError(DioException e, ServerRoute route) {
    final type = e.type;
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.sendTimeout) {
      return '${route.name} 连接超时';
    }
    if (e.error is SocketException) {
      return '${route.name} 无法连接';
    }
    return '${route.name} 请求失败:${e.message ?? e.type.name}';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}