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

/// 「最近添加」那几条 —— 按入库时间倒序取前 [limit] 首。
///
/// **只从已加载的 `songs` 里排**,所以它准不准取决于 `songs` 全不全:
/// 服务器(`search3`)给的是 `created` 升序,最新的那几首排在最后 ——
/// 只加载了前几页时,这条排出来的是「已加载里最新的」,不是库里最新的。
/// 因此整库取全之后必须**重算一次**(见 `mergeSongPage` 与
/// `AppState._completeSongs`),否则货架会与服务器对不上。
List<Song> recentlyAddedSongsOf(Iterable<Song> songs, {int limit = 20}) {
  final sorted = [...songs]..sort((a, b) {
    final da = a.created;
    final db = b.created;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
  return sorted.take(limit).toList();
}

/// 翻页取回一页之后并上去 —— **按 id 去重 + 按同一口径重排 + 重算「最近添加」**。
///
/// 伺服器的「全部歌曲」一次给一页(见 `AppState._songPageSize`),余下的
/// 一页页补(滚动懒加载 / 后台补齐)。三件事必须在这里一起做:
///
/// - **去重**:翻页期间服务器上可能增删曲目,页与页会重叠或错位 ——
///   偏移量在那种时候本来就不可靠,不去重会出重复行;
/// - **重排**:不重排的话新取的那一页会整块挂在列表末尾,按标题排的列表里
///   会突然冒出「B 开头的歌排在 Z 后面」;
/// - **重算「最近添加」**:它依赖全量,每补一页就该重排一次 —— 不然补齐之后
///   货架还停在「只有第一页时」算出来的那一版。
LibrarySnapshot mergeSongPage(
  LibrarySnapshot library,
  List<Song> page, {
  required bool complete,
  required SongSort sort,
}) {
  final seen = {for (final s in library.songs) s.id};
  final merged = [
    ...library.songs,
    ...page.where((s) => seen.add(s.id)),
  ];
  return library.copyWith(
        songs: sortSongs(merged, sort),
        recentlyAddedSongs: recentlyAddedSongsOf(merged),
      )
      .markSongsComplete(complete);
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
