import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'music_source.dart';
import 'server_route.dart';
import 'subsonic_auth.dart';
import 'subsonic_payload.dart';

// 线路那一块(ServerRoute / RouteTag / RoutePing 与两个编辑函数)搬去了
// `server_route.dart` —— 它们是协议无关的,而本文件讲的是 Subsonic 协议。
// 这里再导出一次,让原先从本文件拿这些名字的地方零改动。
// (`export` 不把名字带进本文件的 scope,所以上面那句 import 不能省。)
export 'server_route.dart';

/// 订阅式 HTTP 客户端:所有 Subsonic 请求都从这里出去。
///
/// 两条重要行为:
///   1. **自动择优** —— 未锁定线路时,请求发给当前最快的那条;
///   2. **故障切换** —— 当前线路网络失败(超时 / 连接被拒)时,
///      自动换到下一条可用线路再试一次。认证失败**不换**线
///      (密码错了换到哪条都错,换线只会让用户困惑)。
class SubsonicClient implements ServerConnection {
  SubsonicClient({
    required this.auth,
    required List<ServerRoute> routes,
    Dio? dio,
    this.autoRoute = true,
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

  /// 是否按延迟自动择优。
  ///
  /// 关掉之后**只用手动锁定的那条**(没锁就用列表第一条),并且不再故障
  /// 切到别的线路。设置页那句「每条线路要手动锁定」说的就是这件事:
  /// 用户既然点名了走哪条,就不该在他不知情的时候换成另一条。
  /// 运行中可以改(设置页的开关直接改这个字段)。
  @override
  bool autoRoute;

  /// 当前生效的线路 id。优先级:用户锁定 > 实测最快 > 列表首条。
  String? _activeRouteId;

  /// 最近一次测速结果。
  final Map<String, RoutePing> _pings = {};

  @override
  List<ServerRoute> get routes => List.unmodifiable(_routes);

  /// 换一份线路表(增删 / 改名 / 锁定)。
  ///
  /// **必须走这里,不能只改 `ServerConfig`**:这个类手上那份线路是**建库时
  /// 拷贝的一份**([SubsonicClient] 的构造参数),配置改了而这里不同步,
  /// 界面上的勾会动、请求却照旧走旧线路 —— 真机报的「线路切换无效」就是它。
  ///
  /// 顺手把不存在的线路留下的痕迹清掉:生效线路若已被删,择优结果跟着作废
  /// (否则 [activeRoute] 会退到「列表首条」这种没根据的答案上);测速结果同理,
  /// 留着的话「N / M 条可用」会跟着算错。
  @override
  void setRoutes(List<ServerRoute> routes) {
    _routes
      ..clear()
      ..addAll(routes);

    final ids = routes.map((r) => r.id).toSet();
    if (_activeRouteId != null && !ids.contains(_activeRouteId)) {
      _activeRouteId = null;
    }
    _pings.removeWhere((id, _) => !ids.contains(id));
  }

  @override
  Map<String, RoutePing> get pings => Map.unmodifiable(_pings);

  @override
  ServerRoute? get activeRoute {
    if (_routes.isEmpty) return null;
    final locked = _routes.where((r) => r.selected).firstOrNull;
    if (locked != null) return locked;
    // 手动锁定模式:不问延迟,按用户配的顺序来。
    if (!autoRoute) return _routes.first;
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
  @override
  Future<Map<String, RoutePing>> pingAll() async {
    final results = await Future.wait(_routes.map(pingRoute));
    for (final ping in results) {
      _pings[ping.routeId] = ping;
    }
    // 测速完让择优重新算一次 —— 手动锁定模式下不动,用户的点名优先。
    if (autoRoute) _activeRouteId = _fastestAvailable?.id;
    return pings;
  }

  /// 单条线路测速。用 `ping.view`(最轻的端点)量一次往返。
  @override
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

  /// 与 [call] 同一趟流程,区别只有一个:**参数名可以重复出现**。
  ///
  /// Subsonic 里少数端点就是这样(`savePlayQueue` 的 `id` 有几个队列项就出现几次),
  /// 而 `Map<String, String>` 表达不了 —— 拼进查询串时会被压成最后一个。
  /// 用 `Map<String, List<String>>`,值有几个就重复几遍。
  Future<Map<String, dynamic>> callMulti(
    String path,
    Map<String, List<String>> params,
  ) async {
    final candidates = _candidateOrder();
    if (candidates.isEmpty) {
      throw const SubsonicException('还没有配置任何服务器线路');
    }

    SubsonicException? lastError;
    for (final route in candidates) {
      try {
        final body = await _get(route, path, params);
        _activeRouteId = route.id;
        return body;
      } on SubsonicException catch (e) {
        if (!e.isNetworkFailure) rethrow;
        lastError = e;
      }
    }
    throw lastError ?? const SubsonicException('所有线路都连不上');
  }

  /// 候选线路顺序:当前生效的排第一,其余按延迟升序兜底。
  ///
  /// **用户手动锁定了一条,就只有那一条**。锁定这件事的含义在原型与线路面板里
  /// 都写着同一句「手动锁定后不再自动切换」—— 而故障切换正是「自动择优」的
  /// 一部分。锁定之后还偷偷换到别条去,界面上「当前走 X 线」会与实际用的线路
  /// 对不上(换过去的那条与 [activeRoute] 报的不是同一个),用户更没法解释。
  ///
  /// 判据是 [ServerRoute.selected] 本身,不是那个全局开关:用户点了锁定,
  /// 「自动择优」这个开关多半还开着。
  List<ServerRoute> _candidateOrder() {
    final active = activeRoute;
    if (active == null) return const [];
    if (active.selected) return [active];
    if (!autoRoute) return [active];
    final rest = _routes.where((r) => r.id != active.id).toList()
      ..sort((a, b) =>
          (_pings[a.id]?.latency ?? const Duration(days: 1))
              .compareTo(_pings[b.id]?.latency ?? const Duration(days: 1)));
    return [active, ...rest];
  }

  Future<Map<String, dynamic>> _get(
    ServerRoute route,
    String path,
    Map<String, dynamic> params,
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
        '${route.url} 返回的不是 Subsonic 响应，检查地址与端口',
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
  /// [params] 的值类型是 dynamic —— 少数端点(如 `savePlayQueue` 的 `id`)
  /// **同一个参数名要重复出现**,那种情况传一个 `List<String>`:
  /// `Uri.replace` 会把可迭代值逐个展开成同名参数。
  /// 普通端点照旧传 `Map<String, String>`,它本来就是它的子类型。
  static Uri buildUri(
    ServerRoute route,
    String path,
    Map<String, dynamic> params,
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
    return '${route.name} 请求失败：${e.message ?? e.type.name}';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}