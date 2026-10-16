import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/sorting.dart';

/// 歌曲排序 —— 纯函数,直接钉住每一档的顺序,尤其是边界:
/// 没有入库时间的、同专辑不同曲序的、同艺人不同标题的。
void main() {
  Song song(
    String id, {
    String title = '曲目',
    String artist = '艺人',
    String album = '专辑',
    int? track,
    DateTime? created,
  }) =>
      Song(
        id: id,
        title: title,
        artist: artist,
        album: album,
        albumId: 'al-$album',
        track: track,
        created: created,
      );

  List<String> idsOf(List<Song> songs) => [for (final s in songs) s.id];
  List<String> titlesOf(List<Song> songs) => [for (final s in songs) s.title];

  test('按标题', () {
    final songs = [
      song('s1', title: 'b'),
      song('s2', title: 'a'),
      song('s3', title: 'c'),
    ];
    expect(titlesOf(sortSongs(songs, SongSort.title)), ['a', 'b', 'c']);
  });

  test('按艺人:同一位艺人底下再按标题,不靠服务器给的次序', () {
    final songs = [
      song('s1', artist: 'Zoe', title: 'b'),
      song('s2', artist: 'Ana', title: 'z'),
      song('s3', artist: 'Ana', title: 'a'),
    ];
    expect(idsOf(sortSongs(songs, SongSort.artist)), ['s3', 's2', 's1']);
  });

  test('中文按**码位**排,不按拼音', () {
    // 「甲」(U+7532)在「乙」(U+4E59)之后 —— 按码位排就是这个结果,不是按拼音。
    // Dart 没有内置的中文排序规则,要拼音得引一份 collator,那是另一个决定;
    // 这里的承诺只有「稳定」:同一次运行里排两次,结果一模一样。
    final songs = [song('s1', artist: '甲'), song('s2', artist: '乙')];
    expect(idsOf(sortSongs(songs, SongSort.artist)), ['s2', 's1']);
  });

  test('按专辑:专辑内部按曲序 —— 排出来是一摞一摞的唱片', () {
    final songs = [
      song('s1', album: 'B面', track: 1),
      song('s2', album: 'A面', track: 3),
      song('s3', album: 'A面', track: 1),
      song('s4', album: 'A面', track: 2),
    ];
    expect(idsOf(sortSongs(songs, SongSort.album)), ['s3', 's4', 's2', 's1']);
  });

  test('按添加时间:新的在前', () {
    final songs = [
      song('s1', created: DateTime(2025, 1, 1)),
      song('s2', created: DateTime(2026, 6, 1)),
      song('s3', created: DateTime(2024, 3, 9)),
    ];
    expect(idsOf(sortSongs(songs, SongSort.added)), ['s2', 's1', 's3']);
  });

  test('没有入库时间的排到最后,而不是被当成「很久以前」', () {
    // 有些实现不给 created。把它们混在最早的一端,会看起来像
    // 「新歌被塞到了末尾」—— 而真相是「不知道」。
    final songs = [
      song('s1', created: DateTime(2020, 1, 1)),
      song('s2'),
      song('s3', created: DateTime(2024, 1, 1)),
    ];
    expect(idsOf(sortSongs(songs, SongSort.added)), ['s3', 's1', 's2']);
  });

  test('排出来的是新列表,原列表不动', () {
    final songs = [song('s1', title: 'b'), song('s2', title: 'a')];
    final sorted = sortSongs(songs, SongSort.title);

    expect(titlesOf(sorted), ['a', 'b']);
    expect(titlesOf(songs), ['b', 'a'], reason: '调用方那份可能别处还在用');
  });

  test('存的是名字不是序号 —— 认不出来时退回默认档', () {
    expect(SongSort.byName('artist'), SongSort.artist);
    expect(SongSort.byName('added'), SongSort.added);
    expect(SongSort.byName('duration'), SongSort.title, reason: '旧的「按时长」已下线');
    expect(SongSort.byName(null), SongSort.title);
  });
}
