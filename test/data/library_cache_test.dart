import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/models.dart';

/// 音乐库缓存:存得下、读得回、认得出「这不是我的服务器」、坏了不炸。
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nordic-cache');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Song song(String id) => Song(
        id: id,
        title: '曲目 $id',
        artist: '艺人',
        album: '专辑',
        albumId: 'al-1',
        suffix: 'flac',
        created: DateTime.utc(2026, 1, 5),
      );

  LibrarySnapshot snapshot() => LibrarySnapshot(
        albums: const [
          Album(
            id: 'al-1',
            name: '可能',
            artist: '程响',
            artistId: 'ar-1',
            year: 2022,
            songCount: 8,
            duration: Duration(minutes: 33),
          ),
        ],
        artists: const [
          Artist(id: 'ar-1', name: '程响', albumCount: 1, albumIds: ['al-1']),
        ],
        songs: [song('s1'), song('s2')],
        playlists: const [
          Playlist(id: 'pl-1', name: '深夜驾驶', songCount: 3, readonly: true),
        ],
        recentlyAdded: const [],
        recentlyAddedSongs: const [],
        // 首页那两条货架也要能往返 —— 它们和整库列表一样落盘。
        recentlyPlayed: const [
          Album(
            id: 'al-9',
            name: '上一张听过的',
            artist: '程响',
            artistId: 'ar-1',
            songCount: 3,
          ),
        ],
        mostPlayed: const [
          Album(
            id: 'al-8',
            name: '听得最多的',
            artist: '李宗盛',
            artistId: 'ar-2',
            songCount: 5,
          ),
        ],
        // 「取全了没有」也要能往返:丢了它,一个已经取全的库冷启动读回来
        // 会被当成还差一截。
        songsComplete: true,
      );

  test('写进去再读回来，内容一字不差', () async {
    final cache = await LibraryCache.open(root: root);
    await cache.write('nas|hhy|http://nas.example.com', snapshot());

    // 换一个实例读 —— 相当于重启应用。
    final reopened = await LibraryCache.open(root: root);
    final cached = await reopened.read('nas|hhy|http://nas.example.com');

    expect(cached, isNotNull);
    expect(cached!.snapshot.albums.single.name, '可能');
    expect(cached.snapshot.songs.map((s) => s.id), ['s1', 's2']);
    expect(cached.snapshot.songs.first.created, DateTime.utc(2026, 1, 5));
    expect(cached.snapshot.playlists.single.readonly, isTrue);
    expect(cached.snapshot.playlists.single.songCount, 3);
    expect(cached.snapshot.songsComplete, isTrue);
    // 存的时候得记下时间 —— 界面要说「上次同步 …」。
    expect(
      DateTime.now().difference(cached.savedAt).inMinutes,
      lessThan(1),
    );
  });

  test('换了服务器就当没有缓存', () async {
    final cache = await LibraryCache.open(root: root);
    await cache.write('nas|hhy|http://nas.example.com', snapshot());

    expect(await cache.read('别的|hhy|http://other'), isNull);
  });

  test('文件坏了当没有缓存，而不是抛异常', () async {
    final cache = await LibraryCache.open(root: root);
    await cache.write('nas|hhy|http://nas.example.com', snapshot());
    File('${root.path}${Platform.pathSeparator}library.json')
        .writeAsStringSync('{ 这不是 json');

    expect(await cache.read('nas|hhy|http://nas.example.com'), isNull);
  });

  test('清掉之后读不到', () async {
    final cache = await LibraryCache.open(root: root);
    await cache.write('nas|hhy|http://nas.example.com', snapshot());

    await cache.clear();

    expect(await cache.read('nas|hhy|http://nas.example.com'), isNull);
  });

  test('第一次装（没有文件）读到的是空，不是异常', () async {
    final cache = await LibraryCache.open(root: root);
    expect(await cache.read('nas|hhy|http://nas.example.com'), isNull);
  });

  /// 后台补齐曲目时会连着要求写好几次(每翻一页一次),而每次都要把整份快照
  /// 编码一遍 —— 越写越大,合起来是平方级的活。所以合并:只保证**最新的那一份**
  /// 最终落盘。但两条硬约定不能因此松掉:await 过之后必须读得到,清缓存必须
  /// 等在写的后面(否则就是把文件删到一半又被写回来)。
  group('合并写', () {
    const key = 'nas|hhy|http://nas.example.com';

    LibrarySnapshot withSongs(List<String> ids) =>
        snapshot().copyWith(songs: [for (final id in ids) song(id)]);

    test('连着写三次，最后落地的是第三份 —— 中间那两版没人要', () async {
      final cache = await LibraryCache.open(root: root);

      await Future.wait([
        cache.write(key, withSongs(['s1'])),
        cache.write(key, withSongs(['s1', 's2'])),
        cache.write(key, withSongs(['s1', 's2', 's3'])),
      ]);

      final cached = await cache.read(key);
      expect(cached!.snapshot.songs.map((s) => s.id), ['s1', 's2', 's3']);
    });

    test('写还没落地就清缓存：等在写的后面，清完读不到', () async {
      final cache = await LibraryCache.open(root: root);

      final writing = cache.write(key, snapshot());
      await cache.clear();
      await writing;

      expect(await cache.read(key), isNull,
          reason: '清就是要清干净，写回来的那份不算数');
    });
  });
}
