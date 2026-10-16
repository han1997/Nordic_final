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
      );

  test('写进去再读回来,内容一字不差', () async {
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

  test('文件坏了当没有缓存,而不是抛异常', () async {
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

  test('第一次装(没有文件)读到的是空,不是异常', () async {
    final cache = await LibraryCache.open(root: root);
    expect(await cache.read('nas|hhy|http://nas.example.com'), isNull);
  });
}
