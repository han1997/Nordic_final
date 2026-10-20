import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_repository.dart';

import 'live_server.dart';

/// 这些用例打的是开发机上真实的 Navidrome —— 数据层的地基,
/// 用假响应测「字段名对不对」很容易自说自话(照着实现编 JSON,
/// 再照着实现断言),打到真服务器上才能发现协议口径的偏差。
///
/// **凭据从环境变量读**(见 `live_server.dart`):仓库是公开的,
/// 密码不能跟着代码走。没配环境变量时退回一个够不着的地址,
/// 于是整组照旧跳过,不让 CI / 离线开发平白失败。
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

  /// 服务器在不在。不在就跳过 —— 这组用例的价值依赖真实数据。
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

  test('鉴权通过并能拉到专辑列表', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }
    final albums = await repo.albums();
    expect(albums, isNotEmpty, reason: '真实库应该有专辑');
    // 映射后的关键字段不该是占位值 —— 那是「字段名对不上」的典型症状。
    final first = albums.first;
    expect(first.id, isNotEmpty);
    expect(first.name, isNot('未知专辑'));
    expect(first.artist, isNot('未知艺人'));
  });

  test('专辑详情能拉到曲目，且曲目挂在同一张专辑上', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }
    final albums = await repo.albums();
    // 挑一张有曲目的专辑 —— 空专辑测不出映射问题。
    final withSongs = albums.firstWhere((a) => a.songCount > 0);
    final detail = await repo.album(withSongs.id);

    expect(detail.album.id, withSongs.id);
    expect(detail.songs, isNotEmpty);
    for (final song in detail.songs) {
      expect(song.albumId, withSongs.id, reason: '曲目应归属于这张专辑');
      expect(song.title, isNotEmpty);
      expect(song.duration, greaterThan(Duration.zero));
    }
  });

  test('艺人详情返回专辑与热门曲目', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }
    final artists = await repo.artists();
    expect(artists, isNotEmpty);

    // 挑一位真有作品的艺人。
    final target = artists.firstWhere((a) => a.albumCount > 0);
    final detail = await repo.artist(target.id);

    expect(detail.artist.id, target.id);
    expect(detail.artist.name, target.name);
    expect(detail.albums, isNotEmpty);
  });

  test('歌单列表可读', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }
    final playlists = await repo.playlists();
    expect(playlists, isNotEmpty, reason: '库里应有歌单');
    expect(playlists.first.name, isNotEmpty);
  });

  test('搜索命中专辑 / 艺人 / 歌曲', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }
    // 拿一位真实艺人的名字去搜,三个桶至少该中一个。
    final artists = await repo.artists();
    final hits = await repo.search(artists.first.name);
    expect(hits.total, greaterThan(0));
  });

  test('歌词优先走带时间轴的结构化接口', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }
    final albums = await repo.albums();
    final withSongs = albums.firstWhere((a) => a.songCount > 0);
    final songs = (await repo.album(withSongs.id)).songs;

    // 逐首找有歌词的 —— 库里不是每首都配了词。
    Lyrics? found;
    for (final song in songs.take(12)) {
      final lyrics = await repo.lyrics(song.id);
      if (!lyrics.isEmpty) {
        found = lyrics;
        break;
      }
    }
    if (found == null) {
      markTestSkipped('这批曲目都没有歌词，跳过');
      return;
    }
    expect(found.lines, isNotEmpty);
    expect(found.lines.first.text, isNotEmpty);
    // Navidrome 给的是结构化歌词,应当带时间轴。
    expect(
      found.synced,
      isTrue,
      reason: 'getLyricsBySongId 应返回带 start 的结构化歌词',
    );
    expect(found.lines.first.start, isNotNull);
  });

  test('封面与流地址带上鉴权参数且指向当前线路', () async {
    // 这一条不碰网络,但断言的是**真实**账号与地址;没配环境变量就没得可验。
    if (!liveServerConfigured) {
      markTestSkipped('没配 NORDIC_LIVE_* 环境变量，跳过');
      return;
    }
    final cover = repo.coverUri('al-abc', size: 256);
    expect(cover.path, '/rest/getCoverArt.view');
    expect(cover.queryParameters['id'], 'al-abc');
    expect(cover.queryParameters['size'], '256');
    // 图片加载器绕过 SubsonicClient 直接发请求,不带签名会被拒。
    expect(cover.queryParameters['u'], _username);
    expect(cover.queryParameters['t'], isNotEmpty);
    expect(cover.queryParameters['s'], isNotEmpty);
    expect(cover.toString(), startsWith(_serverUrl));
  });

  test('原音档不加转码参数', () async {
    final uri = repo.streamUri('song-1');
    expect(uri.path, '/rest/stream.view');
    expect(uri.queryParameters.containsKey('maxBitRate'), isFalse);
    expect(uri.queryParameters.containsKey('format'), isFalse);
  });

  test('转码档落成 maxBitRate 与 format', () async {
    final uri = repo.streamUri('song-1', maxBitRate: 192, format: 'mp3');
    expect(uri.queryParameters['maxBitRate'], '192');
    expect(uri.queryParameters['format'], 'mp3');
  });

  /// 曲库扫描的状态 —— **只读那一条**。
  ///
  /// 这一条的价值在于**形状**:`getScanStatus` 回的 `scanStatus` 里到底有没有
  /// `count` / `lastScan`,笔头上的文档说不准(实测 Navidrome 0.64.2 三个都有)。
  /// **不测 `startScan`** —— 那会让用户的服务器当场扫盘,是这台机器的副作用,
  /// 不该由一条用例触发。
  test('扫描状态：服务器答得出在做没在做', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }
    final status = await repo.scanStatus();

    // 扫描中不中是一个真值(不是 null) —— 这一条正是「端点通不通」。
    expect(status.scanning, isA<bool>());
    if (status.count != null) {
      expect(status.count, greaterThan(0), reason: '真实库不该报 0 首');
    }
  });

  /// 播放队列:**读**一条。写(savePlayQueue)会改掉用户服务器上那份队列,
  /// 那不该由用例去动。
  test('播放队列读得回来 —— 空队列是「没有 entry」而不是报错', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }
    final queue = await repo.playQueue();

    // 不支持这个端点的实现会返回 null;这一台是支持的。
    expect(queue, isNotNull, reason: 'Navidrome 支持 getPlayQueue');
    // 有没有内容取决于这台服务器上有没有别的客户端存过队列 —— 两种都合法,
    // 要紧的是**空的时候也不报错**(实测:没有 entry 键)。
    if (queue!.songs.isNotEmpty) {
      expect(queue.currentId, isNotNull);
    }
  });

}