import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_repository.dart';

/// 歌单写操作打到真服务器上。
///
/// 读接口的口径早有一套 live 用例,写操作却只有假响应 —— 而写错参数名
/// 服务器只会回一句「失败」,不会告诉你哪个字段不对。这里建一条**自检用**的
/// 歌单,加歌、改名、按位置移除,最后删掉它:整个过程只碰这一条歌单,
/// 库里原有的东西一首都不动。
///
/// 服务器不可达时跳过。
const _serverUrl = 'http://192.168.10.4:4533';
const _username = 'hhy';
const _password = 'REDACTED';

void main() {
  late SubsonicRepository repo;

  setUp(() {
    repo = SubsonicRepository(clientFor(
      config: const ServerConfig(
        id: 's1',
        name: '客厅 Navidrome',
        kind: ServerKind.navidrome,
        username: _username,
        routes: [ServerRoute(id: 'lan', name: '局域网直连', url: _serverUrl)],
      ),
      password: _password,
    ));
  });

  Future<bool> reachable() async {
    try {
      final ping = await repo.client.pingRoute(
        const ServerRoute(id: 'lan', name: '局域网直连', url: _serverUrl),
      );
      return ping.isOk;
    } catch (_) {
      return false;
    }
  }

  test('歌单能建、能加歌、能改名、能按位置移除、能删', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达,跳过');
      return;
    }

    // 名字带时间戳:万一半途出错留下一条,也不会和下一次的撞名。
    final name = 'Nordic 自检 ${DateTime.now().millisecondsSinceEpoch}';
    Playlist? created;

    try {
      created = await repo.createPlaylist(name);
      expect(created.name, name, reason: '建完要拿得回对象,不然调用方以为失败了');

      final songs = await repo.allSongs(size: 5);
      if (songs.isEmpty) {
        markTestSkipped('库里没有歌可用,跳过');
        return;
      }
      final song = songs.first;

      // 加一首 —— 参数名要是错的,这一步的断言就会暴露。
      await repo.addToPlaylist(created.id, song.id);
      var detail = await repo.playlist(created.id);
      expect(detail.songs.map((s) => s.id), contains(song.id));

      // 改名。
      await repo.renamePlaylist(created.id, '$name·改');
      final renamed = (await repo.playlists())
          .where((p) => p.id == created!.id)
          .firstOrNull;
      expect(renamed?.name, '$name·改');

      // 按位置移除(协议里没有按 id 移除)。
      final index = detail.songs.indexWhere((s) => s.id == song.id);
      expect(index, greaterThanOrEqualTo(0));
      await repo.removeFromPlaylist(created.id, index);
      detail = await repo.playlist(created.id);
      expect(detail.songs, isEmpty, reason: '移除之后这首歌不该还在');
    } finally {
      // 无论中途怎么失败,自检歌单都要收走 —— 用户库里不该多出一条测试垃圾。
      if (created != null) {
        try {
          await repo.deletePlaylist(created.id);
        } catch (_) {
          // 收尾失败不该盖掉真正的失败原因。
        }
      }
    }

    final remaining = await repo.playlists();
    expect(remaining.map((p) => p.id), isNot(contains(created.id)));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
