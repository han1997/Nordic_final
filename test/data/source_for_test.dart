import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/music_source.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_repository.dart';

/// `ServerConfig` → [MusicSource] 的分派点。
///
/// 这一组不是「断言 implements 生效了」那种空转守卫(那是编译期的事)。
/// 它钉的是两条**决定**:
///
///  1. **飞牛音乐今天也走 Subsonic 那一条**。仓库自己的口径(`ServerKind`
///     的注释)是「三者都讲 Subsonic 协议,飞牛音乐基于社区逆向」,而且
///     `clientFor` 从来没读过 `kind` —— 选它的用户今天拿到的是普通客户端。
///     谁哪天把它换成「抛未实现的空壳」,这里当场变红;
///  2. **`localCover` 真的透传到了音源上**。少了它,断网时已下载内容的封面
///     会静默地从「看得见」变成「没有」。
void main() {
  ServerConfig configOf(ServerKind kind) => ServerConfig(
        id: 'server-1',
        name: kind.label,
        kind: kind,
        username: 'u',
        routes: const [
          ServerRoute(id: 'lan', name: '内网', url: 'http://nas.example.com'),
        ],
      );

  group('sourceFor', () {
    test('三个接入类型今天都落到 Subsonic 那一条', () {
      for (final kind in ServerKind.values) {
        final source = sourceFor(config: configOf(kind), password: 'p');
        expect(
          source,
          isA<SubsonicRepository>(),
          reason: '${kind.name} 应当仍走 Subsonic —— 见 ServerKind 的注释',
        );
        expect(source.connection, isA<SubsonicClient>());
      }
    });

    test('线路照配置进来，择优问得出来', () {
      final source = sourceFor(config: configOf(ServerKind.fnos), password: 'p');
      expect(source.connection.routes, hasLength(1));
      expect(source.connection.routes.single.url, 'http://nas.example.com');
      // 还没测速也没有锁定,于是退到列表首条。
      expect(source.connection.activeRoute?.id, 'lan');
    });

    test('localCover 透传到了音源上（封面本机优先）', () {
      final source = sourceFor(
        config: configOf(ServerKind.navidrome),
        password: 'p',
        localCover: (id) => '/tmp/covers/$id.jpg',
      );
      final uri = source.coverUri('art-1');
      expect(uri.scheme, 'file');
      expect(uri.path, '/tmp/covers/art-1.jpg');
    });

    test('没给 localCover 时封面仍回退到服务器地址', () {
      final source = sourceFor(config: configOf(ServerKind.navidrome), password: 'p');
      final uri = source.coverUri('art-1');
      expect(uri.scheme, 'http');
      expect(uri.path, contains('/rest/getCoverArt'));
    });
  });
}