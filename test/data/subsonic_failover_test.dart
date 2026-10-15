import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/subsonic_auth.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_payload.dart';

import 'fake_dio.dart';

/// 故障切换是「多线路」这个卖点的核心行为,不能只靠肉眼推断。
///
/// 用一个记录「每个基址被访问过几次」的假 Dio 来驱动:
/// 让第一条线路连不上,验证第二条被顶上,并且**认证失败不换线**
/// (密码错了换到哪条都错,换线只会让用户困惑)。
void main() {
  group('故障切换', () {
    test('第一条线路网络失败时自动换到下一条', () async {
      final hits = <String>[];
      final client = SubsonicClient(
        auth: SubsonicAuth(username: 'u', password: 'p'),
        routes: const [
          ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.invalid'),
          ServerRoute(id: 'wan', name: '外网', url: 'http://wan.example.com'),
        ],
        dio: recordingDio(
          hits,
          handler: (base) {
            // 局域网线路:模拟连接被拒。
            if (base.contains('lan.invalid')) {
              throw const SubsonicException(
                '局域网 无法连接',
              );
            }
            return {'subsonic-response': {'status': 'ok', 'version': '1.16.1'}};
          },
        ),
      );

      final body = await client.call('ping');

      expect(SubsonicEnvelope.parse(body).isOk, isTrue);
      expect(hits, ['http://lan.invalid', 'http://wan.example.com']);
      // 切换后生效线路要跟过去,下次请求直接走能用的那条。
      expect(client.activeRoute?.id, 'wan');
    });

    test('认证失败不换线 —— 换到哪条都是同样的密码错', () async {
      final hits = <String>[];
      final client = SubsonicClient(
        auth: SubsonicAuth(username: 'u', password: 'wrong'),
        routes: const [
          ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.example.com'),
          ServerRoute(id: 'wan', name: '外网', url: 'http://wan.example.com'),
        ],
        dio: recordingDio(
          hits,
          handler: (base) => {
            'subsonic-response': {
              'status': 'failed',
              'version': '1.16.1',
              'error': {'code': 40, 'message': 'Wrong username or password'},
            }
          },
        ),
      );

      await expectLater(
        client.call('ping'),
        throwsA(isA<SubsonicException>()
            .having((e) => e.isAuthFailure, 'isAuthFailure', isTrue)),
      );
      // 只碰了第一条 —— 认证错误立刻上报,不该在其它线路上重试。
      expect(hits, ['http://lan.example.com']);
    });

    test('所有线路都连不上时,抛出最后那条的错误', () async {
      final client = SubsonicClient(
        auth: SubsonicAuth(username: 'u', password: 'p'),
        routes: const [
          ServerRoute(id: 'a', name: 'A', url: 'http://a.invalid'),
          ServerRoute(id: 'b', name: 'B', url: 'http://b.invalid'),
        ],
        dio: recordingDio(
          <String>[],
          handler: (base) => throw const SubsonicException('连不上'),
        ),
      );

      await expectLater(
        client.call('ping'),
        throwsA(isA<SubsonicException>()),
      );
    });

    test('一条线路都没有时给出可读的提示,而不是空指针', () async {
      final client = SubsonicClient(
        auth: SubsonicAuth(username: 'u', password: 'p'),
        routes: const [],
      );

      await expectLater(
        client.call('ping'),
        throwsA(isA<SubsonicException>().having(
          (e) => e.message,
          'message',
          contains('没有配置'),
        )),
      );
    });

    test('返回 HTML 的地址被识别成「不是 Subsonic 服务」', () async {
      final client = SubsonicClient(
        auth: SubsonicAuth(username: 'u', password: 'p'),
        routes: const [
          ServerRoute(id: 'a', name: 'A', url: 'http://a.example.com'),
        ],
        dio: rawDio('<html><body>路由器管理页</body></html>'),
      );

      await expectLater(
        client.call('ping'),
        throwsA(isA<SubsonicException>()
            .having((e) => e.message, 'message', contains('Subsonic'))),
      );
    });
  });
}