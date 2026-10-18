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

  group('手动锁定(关掉线路自动择优)', () {
    test('锁定了哪条就走哪条', () async {
      final hits = <String>[];
      final client = SubsonicClient(
        autoRoute: false,
        auth: SubsonicAuth(username: 'u', password: 'p'),
        routes: const [
          ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.example.com'),
          ServerRoute(
            id: 'wan',
            name: '外网',
            url: 'http://wan.example.com',
            selected: true,
          ),
        ],
        dio: recordingDio(
          hits,
          handler: (_) => {
            'subsonic-response': {'status': 'ok', 'version': '1.16.1'}
          },
        ),
      );

      await client.call('ping');

      expect(hits, ['http://wan.example.com']);
    });

    test('不锁定就用列表第一条 —— 测速说了也不算', () async {
      final hits = <String>[];
      final client = SubsonicClient(
        autoRoute: false,
        auth: SubsonicAuth(username: 'u', password: 'p'),
        routes: const [
          // 故意把慢的放在前面:自动择优会跳过它,手动锁定不该跳。
          ServerRoute(id: 'slow', name: '慢', url: 'http://slow.example.com'),
          ServerRoute(id: 'fast', name: '快', url: 'http://fast.example.com'),
        ],
        dio: recordingDio(
          hits,
          handler: (_) => {
            'subsonic-response': {'status': 'ok', 'version': '1.16.1'}
          },
        ),
      );

      await client.pingAll();
      await client.call('ping');

      expect(client.activeRoute?.id, 'slow', reason: '用户点名的是顺序,不是延迟');
      expect(hits.last, 'http://slow.example.com');
    });

    test('线路不通也不换线 —— 换线路是自动择优的一部分', () async {
      final hits = <String>[];
      final client = SubsonicClient(
        autoRoute: false,
        auth: SubsonicAuth(username: 'u', password: 'p'),
        routes: const [
          ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.invalid'),
          ServerRoute(id: 'wan', name: '外网', url: 'http://wan.example.com'),
        ],
        dio: recordingDio(
          hits,
          handler: (base) {
            if (base.contains('lan.invalid')) {
              throw const SubsonicException('局域网 无法连接');
            }
            return {'subsonic-response': {'status': 'ok', 'version': '1.16.1'}};
          },
        ),
      );

      await expectLater(
        client.call('ping'),
        throwsA(isA<SubsonicException>()),
      );
      // 只碰了锁定的那条 —— 悄悄换一条是用户关掉这个开关时最不想要的。
      expect(hits, ['http://lan.invalid']);
    });

    test('锁定之后,「自动择优」开着也不换线', () async {
      // 判据不能只看那个全局开关:用户点了锁定,开关多半还开着。换过去的话,
      // 线路面板上那句「当前走 X」与实际发请求的那条就不是同一条了 ——
      // 而锁定这件事的含义,原型与面板上写的都是「不再自动切换」。
      final hits = <String>[];
      final client = SubsonicClient(
        auth: SubsonicAuth(username: 'u', password: 'p'),
        routes: const [
          // 用户锁的是这条走不通的 —— 换到另一条正是「自动切换」。
          ServerRoute(
            id: 'lan',
            name: '局域网',
            url: 'http://lan.invalid',
            selected: true,
          ),
          ServerRoute(id: 'wan', name: '外网', url: 'http://wan.example.com'),
        ],
        dio: recordingDio(
          hits,
          handler: (base) {
            if (base.contains('lan.invalid')) {
              throw const SubsonicException('局域网 无法连接');
            }
            return {'subsonic-response': {'status': 'ok', 'version': '1.16.1'}};
          },
        ),
      );

      await expectLater(
        client.call('ping'),
        throwsA(isA<SubsonicException>()),
      );
      expect(hits, ['http://lan.invalid'], reason: '锁定之后不再自动切换');
      expect(client.activeRoute?.id, 'lan');
    });
  });

  group('换线路表', () {
    // 真机报的「线路切换无效」:界面改了配置,而这个类手上那份线路是**建库时
    // 拷贝的一份**,不同步的话勾会动、请求照旧走旧线路。这一组钉住同步。
    const lan = ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.example.com');
    const wan = ServerRoute(id: 'wan', name: '外网', url: 'http://wan.example.com');

    SubsonicClient clientWith(List<ServerRoute> routes, List<String> hits,
            {bool autoRoute = true}) =>
        SubsonicClient(
          auth: SubsonicAuth(username: 'u', password: 'p'),
          autoRoute: autoRoute,
          routes: routes,
          dio: recordingDio(
            hits,
            handler: (_) => {
              'subsonic-response': {'status': 'ok', 'version': '1.16.1'}
            },
          ),
        );

    test('锁定的线路当场生效 —— 不用重建客户端', () async {
      final hits = <String>[];
      final client = clientWith(const [lan, wan], hits);

      client.setRoutes(const [
        ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.example.com'),
        ServerRoute(
          id: 'wan',
          name: '外网',
          url: 'http://wan.example.com',
          selected: true,
        ),
      ]);

      expect(client.activeRoute?.id, 'wan');
      await client.call('ping');
      expect(hits, ['http://wan.example.com']);
    });

    test('生效线路被删掉就作废 —— 不留在一条已经不存在的线路上', () async {
      final hits = <String>[];
      final client = clientWith(const [lan, wan], hits);

      // 先让 wan 成为生效线路。
      await client.pingAll();
      client.setRoutes(const [
        ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.example.com'),
      ]);

      expect(client.routes.length, 1);
      expect(client.activeRoute?.id, 'lan');
      expect(
        client.pings.containsKey('wan'),
        isFalse,
        reason: '删掉的线路不该留着上一次的测速结果,否则「N / M 条可用」会算错',
      );
    });

    test('加一条线路也是当场进候选', () async {
      final hits = <String>[];
      final client = clientWith(const [lan], hits);

      client.setRoutes(const [
        lan,
        ServerRoute(id: 'relay', name: '中继', url: 'http://relay.example.com'),
      ]);

      expect(client.routes.map((r) => r.id), ['lan', 'relay']);
      expect(client.activeRoute?.id, 'lan');
    });
  });
}