import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:nordic/data/subsonic_payload.dart';

/// 测试用的假 Dio:按基址决定怎么回应,并记录被访问过的基址顺序。
///
/// 用它来驱动故障切换 —— 这是「多线路」的核心行为,只有让第一条线路
/// 真的失败、观察第二条被顶上,才算验过。
Dio recordingDio(
  List<String> hits, {
  required Object? Function(String base) handler,
}) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, interceptor) {
      final base = '${options.uri.scheme}://${options.uri.host}'
          '${options.uri.hasPort ? ':${options.uri.port}' : ''}';
      hits.add(base);
      try {
        final payload = handler(base);
        interceptor.resolve(
          Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: jsonEncode(payload),
          ),
        );
      } on SubsonicException catch (e) {
        interceptor.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: e,
          message: e.message,
        ));
      }
    },
  ));
  return dio;
}

/// 返回固定原始文本的假 Dio —— 用来模拟「地址指向了别的服务,回了 HTML」。
Dio rawDio(String body) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, interceptor) => interceptor.resolve(
      Response<String>(requestOptions: options, statusCode: 200, data: body),
    ),
  ));
  return dio;
}