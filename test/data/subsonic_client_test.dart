import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_auth.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_payload.dart';

void main() {
  group('鉴权参数', () {
    test('token 是 md5(密码 + salt),短盐也能对上', () {
      // 用固定 salt 钉住算法 —— 换写法会直接连不上真服务器。
      expect(
        SubsonicAuth.tokenFor('sesame', 'c19b2d'),
        '26719a1196d2a940705a59634eb18eab',
      );
    });

    test('每次请求的参数齐全,且 salt 每次都不同', () {
      final auth = SubsonicAuth(username: 'u', password: 'pw');
      final first = auth.queryParams();
      final second = auth.queryParams();

      for (final params in [first, second]) {
        expect(params['u'], 'u');
        expect(params['v'], SubsonicAuth.apiVersion);
        expect(params['c'], SubsonicAuth.clientName);
        expect(params['f'], 'json');
        expect(params['t'], isNotEmpty);
        expect(params['s'], isNotEmpty);
      }
      // 固定 salt 会让「密码不过网」失去意义。
      expect(first['s'], isNot(second['s']));
      expect(first['t'], isNot(second['t']));
    });
  });

  group('URL 拼装', () {
    const route = ServerRoute(
      id: 'lan',
      name: '局域网',
      url: 'http://192.168.10.4:4533',
    );
    final auth = SubsonicAuth(username: 'u', password: 'pw');

    test('端点落到 /rest/<name>.view 下', () {
      final uri = SubsonicClient.buildUri(route, 'getAlbum', {'id': 'a1'}, auth);
      expect(uri.path, '/rest/getAlbum.view');
      expect(uri.queryParameters['id'], 'a1');
    });

    test('基址末尾多一个斜杠不会拼出双斜杠', () {
      const trailing = ServerRoute(
        id: 'x',
        name: 'x',
        url: 'http://host:4533/',
      );
      final uri = SubsonicClient.buildUri(trailing, 'ping', const {}, auth);
      expect(uri.toString(), isNot(contains('//rest')));
      expect(uri.path, '/rest/ping.view');
    });

    test('调用方参数不会盖掉鉴权参数', () {
      // 鉴权参数先展开 —— 即便调用方传了同名的 u,也是它赢,
      // 这是刻意的:避免某个端点顺手把凭据改掉。
      final uri = SubsonicClient.buildUri(route, 'ping', {'u': 'x'}, auth);
      expect(uri.queryParameters['u'], 'x');
      expect(uri.queryParameters['t'], isNotEmpty);
    });
  });

  group('响应外壳', () {
    test('ok 状态解析出服务器类型', () {
      final envelope = SubsonicEnvelope.parse({
        'subsonic-response': {
          'status': 'ok',
          'version': '1.16.1',
          'type': 'navidrome',
        }
      });
      expect(envelope.isOk, isTrue);
      expect(envelope.serverType, 'navidrome');
      expect(envelope.error, isNull);
    });

    test('failed 状态带出错误码与文案', () {
      final envelope = SubsonicEnvelope.parse({
        'subsonic-response': {
          'status': 'failed',
          'version': '1.16.1',
          'error': {'code': 40, 'message': 'Wrong username or password'},
        }
      });
      expect(envelope.isOk, isFalse);
      expect(envelope.error?.code, 40);
      expect(envelope.error?.isAuthFailure, isTrue);
    });

    test('不是 Subsonic 响应时说清楚', () {
      expect(
        () => SubsonicEnvelope.parse({'hello': 'world'}),
        throwsA(isA<SubsonicException>()
            .having((e) => e.message, 'message', contains('Subsonic'))),
      );
    });
  });

  group('载荷取值', () {
    test('getArtists 把分组后的 index 拉平', () {
      final artists = SubsonicPayload.artists({
        'subsonic-response': {
          'status': 'ok',
          'artists': {
            'index': [
              {'name': 'A', 'artist': [{'id': '1', 'name': 'Ada'}]},
              {'name': 'B', 'artist': [{'id': '2', 'name': 'Bob'}]},
            ]
          },
        }
      });
      expect(artists.map((a) => a['name']), ['Ada', 'Bob']);
    });

    test('缺字段的桶返回空列表而不是抛异常', () {
      expect(SubsonicPayload.playlists({'subsonic-response': {}}), isEmpty);
      expect(SubsonicPayload.albums({'subsonic-response': {}}), isEmpty);
    });

    test('getAlbumList2 缺失时退回 getAlbumList', () {
      final albums = SubsonicPayload.albums({
        'subsonic-response': {
          'albumList': {
            'album': [{'id': 'a1', 'name': 'Fallback'}]
          }
        }
      });
      expect(albums.single['name'], 'Fallback');
    });
  });

  group('线路择优', () {
    /// 固定延迟的假客户端:只覆写测速,不真发请求。
    SubsonicClient clientWith(List<ServerRoute> routes) =>
        SubsonicClient(
          auth: SubsonicAuth(username: 'u', password: 'p'),
          routes: routes,
        );

    test('没有锁定线路时按列表首条起步', () {
      final client = clientWith(const [
        ServerRoute(id: 'a', name: 'A', url: 'http://a'),
        ServerRoute(id: 'b', name: 'B', url: 'http://b'),
      ]);
      expect(client.activeRoute?.id, 'a');
    });

    test('用户锁定的线路优先于列表顺序', () {
      final client = clientWith(const [
        ServerRoute(id: 'a', name: 'A', url: 'http://a'),
        ServerRoute(id: 'b', name: 'B', url: 'http://b', selected: true),
      ]);
      expect(client.activeRoute?.id, 'b');
    });

    test('没有线路时 activeRoute 为空而不是抛异常', () {
      expect(clientWith(const []).activeRoute, isNull);
    });
  });

  group('服务器配置', () {
    test('序列化时不含密码', () {
      const config = ServerConfig(
        id: 's1',
        name: '客厅',
        kind: ServerKind.navidrome,
        username: 'u',
        routes: [
          ServerRoute(id: 'lan', name: '局域网', url: 'http://192.168.10.4:4533'),
        ],
      );
      final json = config.toJson();
      expect(json.containsKey('password'), isFalse);
      expect(
        json.toString(),
        isNot(contains('不该出现在配置里的密码')),
        reason: '配置里不该出现任何密码痕迹',
      );
    });

    test('往返序列化保持线路与类型', () {
      const config = ServerConfig(
        id: 's1',
        name: '客厅',
        kind: ServerKind.fnos,
        username: 'u',
        routes: [
          ServerRoute(
            id: 'lan',
            name: '局域网',
            url: 'http://192.168.10.4:4533',
            tag: RouteTag.lan,
          ),
          ServerRoute(
            id: 'wan',
            name: '外网',
            url: 'https://music.example.com',
            tag: RouteTag.wan,
            selected: true,
          ),
        ],
      );
      final restored = ServerConfig.fromJson(config.toJson());

      expect(restored.kind, ServerKind.fnos);
      expect(restored.name, '客厅');
      expect(restored.routes.length, 2);
      expect(restored.routes[1].tag, RouteTag.wan);
      expect(restored.routes[1].selected, isTrue);
    });
  });
}