import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_repository.dart';

import 'live_server.dart';

/// 收藏的写操作打到真服务器上。
///
/// 歌单那套有 `playlist_writes_live_test.dart`,收藏却只有假响应形态的
/// `write_operations_test.dart` —— 而参数名或端点写错时,服务器只会回一句
/// 「失败」,不会告诉你哪个字段不对。`setStarred` 有三条道(songId / albumId /
/// artistId),这里三条都真走一遍。
///
/// **收藏是就地可逆的**,所以做法是「读当前状态 → 切换 → 回读断言 → 还原」:
/// 跑完这一组,用户库里的收藏与开工前**完全一样**。收尾那一步比对的是三个
/// 集合的全部 id,不只是目标那几个 —— 只找回目标、顺手把别人改没了同样是事故。
///
/// **凭据从环境变量读**(见 `live_server.dart`):仓库是公开的,密码不能跟着
/// 代码走。没配时退回一个够不着的地址,整组照旧跳过。
final _serverUrl = liveServerUrl;
final _username = liveServerUser;
final _password = liveServerPassword;

void main() {
  late SubsonicRepository repo;

  setUp(() {
    repo = SubsonicRepository(clientFor(
      config: ServerConfig(
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
        ServerRoute(id: 'lan', name: '局域网直连', url: _serverUrl),
      );
      return ping.isOk;
    } catch (_) {
      return false;
    }
  }

  test('曲、专辑、艺人都能收藏也能取消，跑完原样还回去', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }

    final songs = await repo.allSongs(size: 5);
    final albums = await repo.albums();
    final artists = await repo.artists();
    if (songs.isEmpty || albums.isEmpty || artists.isEmpty) {
      markTestSkipped('库里素材不够，跳过');
      return;
    }
    final song = songs.first;
    final album = albums.first;
    final artist = artists.first;

    // **先读当前状态**:这几个目标本来就收藏过也说不定,还原要照着各自的原值
    // 来,不能一律「取消收藏」—— 那会把用户原本收藏的反而抹掉。
    final before = await repo.starred();
    final songWas = _songIds(before.songs).contains(song.id);
    final albumWas = _albumIds(before.albums).contains(album.id);
    final artistWas = _artistIds(before.artists).contains(artist.id);

    try {
      await repo.setStarred(songId: song.id, starred: !songWas);
      await repo.setStarred(albumId: album.id, starred: !albumWas);
      await repo.setStarred(artistId: artist.id, starred: !artistWas);

      // **回读才是这一组要验的东西** —— 三条道的端点与参数名对不对。
      // 写错的话服务器只回一句 failed,`SubsonicClient.call` 会当场抛。
      final after = await repo.starred();
      expect(_songIds(after.songs).contains(song.id), !songWas,
          reason: '歌曲的收藏没翻转');
      expect(_albumIds(after.albums).contains(album.id), !albumWas,
          reason: '专辑的收藏没翻转');
      expect(_artistIds(after.artists).contains(artist.id), !artistWas,
          reason: '艺人的收藏没翻转');
    } finally {
      // 无论中途怎么失败,这三项都要还原成开工前的样子。
      try {
        await repo.setStarred(songId: song.id, starred: songWas);
        await repo.setStarred(albumId: album.id, starred: albumWas);
        await repo.setStarred(artistId: artist.id, starred: artistWas);
      } catch (_) {
        // 收尾失败不该盖掉真正的失败原因。
      }
    }

    // 收尾之后再看一遍:整个收藏集要与开工前一致 —— 用户库里一个字都不该变。
    final restored = await repo.starred();
    expect(_songIds(restored.songs), _songIds(before.songs), reason: '歌曲收藏被动过');
    expect(_albumIds(restored.albums), _albumIds(before.albums), reason: '专辑收藏被动过');
    expect(_artistIds(restored.artists), _artistIds(before.artists),
        reason: '艺人收藏被动过');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Set<String> _songIds(Iterable<Song> items) => items.map((s) => s.id).toSet();

Set<String> _albumIds(Iterable<Album> items) => items.map((a) => a.id).toSet();

Set<String> _artistIds(Iterable<Artist> items) => items.map((a) => a.id).toSet();