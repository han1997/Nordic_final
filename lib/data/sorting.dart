import 'models.dart';

/// 歌曲的排序口径。
///
/// 与 [AlbumSort](见 `subsonic_repository.dart`)不同,这一组**全在本地做**:
/// 服务器没有「按标题给我排一版歌」这种端点,而曲子本来就是一次拉回来的
/// (见 `allSongs`),本地排一遍比再打一轮请求快得多。
///
/// 中文按**码位**排,不按拼音 —— Dart 没有内置的中文排序规则,要拼音得引一份
/// collator,那是另一个决定。这里的承诺只是「稳定」:同一次运行里排两次,
/// 结果一模一样,不会因为排序方式相同而看起来在闪。
enum SongSort {
  title('标题'),
  artist('艺人'),
  album('专辑'),
  added('添加时间');

  const SongSort(this.label);

  final String label;

  /// 存的是**名字**而不是序号:枚举增删时序号会错位,名字不会。
  static SongSort byName(String? name) =>
      values.where((s) => s.name == name).firstOrNull ?? SongSort.title;
}

/// 按 [sort] 排一份曲子列表。返回**新列表** —— 传进来的那份可能别处还在用。
List<Song> sortSongs(Iterable<Song> songs, SongSort sort) {
  final list = [...songs];
  switch (sort) {
    case SongSort.title:
      list.sort((a, b) => _text(a.title, b.title));
    case SongSort.artist:
      // 同一位艺人底下再按标题 —— 否则同一艺人的曲子顺序取决于服务器给的次序,
      // 换一台服务器看起来就变了。
      list.sort((a, b) =>
          _then(_text(a.artist, b.artist), _text(a.title, b.title)));
    case SongSort.album:
      // 专辑内部按曲序,这样「按专辑」排出来就是一摞一摞的唱片。
      list.sort((a, b) => _then(
            _text(a.album, b.album),
            (a.track ?? 0).compareTo(b.track ?? 0),
          ));
    case SongSort.added:
      // 新的在前。**没给入库时间的排到最后** —— 不把它当成「很久以前」,
      // 那会让缺字段的实现看起来像把新歌塞到了末尾。
      list.sort((a, b) => _addedRank(b).compareTo(_addedRank(a)));
  }
  return list;
}

/// 排序用的入库时间。缺了给一个「比谁都旧」的值,于是落到末尾。
int _addedRank(Song song) =>
    song.created?.millisecondsSinceEpoch ?? -0x7FFFFFFFFFFFF;

int _text(String a, String b) => a.compareTo(b);

/// 先比第一个,平了再比第二个。
int _then(int first, int second) => first != 0 ? first : second;

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
