import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/json_list.dart';
import 'package:nordic/data/subsonic_mapper.dart';

/// 「服务器给了一条读不出来的数据」—— 这一组钉住的是**别因此卡死整屏**。
///
/// 病灶(2026-10-21 通审时发现的):映射层对 `id` 是裸 cast
/// (`json['id'] as String`)。服务器偶尔会给出没有 `id` 的条目,那时抛的是
/// `TypeError` —— 它实现的是 `Error` 而**不是** `Exception`,所以各屏的
/// `on MusicSourceException catch` 一条都接不住:异常一路穿出去,
/// `_loading` 永远停在 `true`,界面就**一直转圈**,而屏幕上没有任何东西
/// 说明发生过什么。
///
/// 两条边界必须同时成立(这一组两头都钉):
///
///   1. **实体**(专辑 / 歌曲 / 艺人 / 歌单)缺 `id` → 丢那一条,其余照常;
///   2. **非实体**的数组(歌词的 `line[]`、`genres[]`)本来就没有 `id`
///      —— **一条都不许丢**。这条是踩出来的:第一版把判据塞进了通用的
///      `mapList`,于是歌词行被整批筛掉,而那个错不响(歌词页只是空着),
///      是 `app_state_test` 的「歌词的磁盘缓存」那三条先红的。
void main() {
  group('实体数组：缺 id 的那一条丢掉，其余照常', () {
    test('album 少了 id → 整条不出现，别的那张还在', () {
      final albums = SubsonicMapper.albums([
        {'id': 'al-1', 'name': '有的那张'},
        {'name': '没有 id 的那张'},
        {'id': '', 'name': 'id 是空串的'},
        {'id': 'al-2', 'name': '另一张'},
      ]);

      expect(albums.map((a) => a.id), ['al-1', 'al-2']);
    });

    test('song / artist / playlist 同一套口径', () {
      expect(
        SubsonicMapper.songs([
          {'id': 's-1', 'title': '有'},
          {'title': '没有 id'},
        ]).map((s) => s.id),
        ['s-1'],
      );
      expect(
        SubsonicMapper.artists([
          {'id': 'ar-1', 'name': '有'},
          {'name': '没有 id'},
        ]).map((a) => a.id),
        ['ar-1'],
      );
      expect(
        SubsonicMapper.playlists([
          {'id': 'p-1', 'name': '有'},
          {'name': '没有 id'},
        ]).map((p) => p.id),
        ['p-1'],
      );
    });

    test('一条都读不出来时给空表 —— 不是抛，也不是 null', () {
      expect(SubsonicMapper.albums([{'name': '没有 id'}]), isEmpty);
      expect(SubsonicMapper.songs([<String, dynamic>{}]), isEmpty);
    });

    test('搜索的三个桶各自筛 —— 一个坏元素不该带走另外两桶', () {
      final hits = SubsonicMapper.search({
        'song': [
          {'id': 's-1', 'title': '歌'},
          {'title': '坏的'},
        ],
        'album': [
          {'id': 'al-1', 'name': '专辑'},
        ],
        'artist': [
          {'id': 'ar-1', 'name': '艺人'},
          {'name': '坏的'},
        ],
      });

      expect(hits.songs.map((s) => s.id), ['s-1']);
      expect(hits.albums.map((a) => a.id), ['al-1']);
      expect(hits.artists.map((a) => a.id), ['ar-1']);
    });
  });

  group('非实体数组：本来就没有 id，一条都不许丢', () {
    test('歌词的 line[] 全留着', () {
      final lyrics = SubsonicMapper.lyrics([
        {
          'line': [
            {'value': '第一句', 'start': 0},
            {'value': '第二句', 'start': 1000},
          ],
        },
      ]);

      expect(lyrics.lines.map((l) => l.text), ['第一句', '第二句']);
      expect(lyrics.synced, isTrue);
    });

    test('mapList 只筛「不是对象」的那些，不看 id', () {
      final list = mapList([
        {'value': '没有 id 也留着'},
        {'id': 'x'},
        '字符串',
        null,
      ]);

      expect(list, hasLength(2), reason: '两个对象都留着 —— id 不是这一层的判据');
    });
  });

  group('hasIdentity 的判据', () {
    test('有非空 String 的 id 才算', () {
      expect(SubsonicMapper.hasIdentity({'id': 'x'}), isTrue);
      expect(SubsonicMapper.hasIdentity({'id': ''}), isFalse);
      expect(SubsonicMapper.hasIdentity({'id': 123}), isFalse);
      expect(SubsonicMapper.hasIdentity(<String, dynamic>{}), isFalse);
    });
  });
}
