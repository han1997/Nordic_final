/// `Iterable.firstOrNull`。
///
/// **Dart 核心库里没有它** —— `package:collection` 有,但为这一句引一条直接依赖
/// 不值当(本仓库对依赖的账算得很细,见 pubspec 里那几段)。所以自己写。
///
/// 收成一份是因为它原先在五个文件里各写了一遍,逐字相同:`media_cache`(缓存槽位)、
/// `download_manager`(任务查找)、`subsonic_client`(线路择优)、`sorting`(排序口径)、
/// `quality`(档位查表)。五份私有 extension 改一次要记着改五处 —— 与
/// `json_list.dart` 的 `mapList` 是同一类事。
///
/// 放在 `data/` 而不是某一层内部:数据层与播放层都要用,而它只依赖核心库。
library;

extension IterableFirstOrNull<T> on Iterable<T> {
  /// 第一项,空列表给 null。
  ///
  /// 不用 `.first`(空的时候抛)、也不用 `firstWhere(...orElse: () => null)`
  /// (要求元素可空,类型上绕不过去)。
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
