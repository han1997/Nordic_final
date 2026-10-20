import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 一条**没报出去**的播放记录。
///
/// [at] 是**听的那一刻** —— 补报时必须带上它(`scrobble` 的 `time` 参数就是
/// 为这件事准备的)。不带的话服务器会把它记成「刚收到的时间」,于是上周离线
/// 听的那几十首全挤在同一个时刻上,「最近播放」那一栏就毁了。
class PendingScrobble {
  const PendingScrobble({required this.songId, required this.at});

  final String songId;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'id': songId,
        'at': at.millisecondsSinceEpoch,
      };

  static PendingScrobble? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final at = (json['at'] as num?)?.toInt();
    if (id is! String || id.isEmpty || at == null) return null;
    return PendingScrobble(
      songId: id,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

/// 「听过一次」的待补队列 —— 发不出去的那几笔先存在这里,下次有机会再报。
///
/// **为什么值得落盘**:离线听的那些在服务器统计里本该有份。上一轮把 scrobble
/// 接上之后,发不出去的就被丢掉了(「失败一律静默」),于是断开网络的这一趟
/// 在「最近播放」里完全不存在 —— 而那正是用户会去对照的东西。
///
/// 存储照 [LibraryCache] 的骨架:单文件 JSON、带版本号、**坏了当空**、
/// 写不进就算了(读不到待补记录不该影响听歌)。上限 [limit] 条,满了丢最老的
/// —— 它是「补报」,不是账本。
class ScrobbleStore {
  ScrobbleStore._(this._root);

  /// null = 这块存储用不了(建不出来),这时一切退化成「不落盘」。
  final Directory? _root;

  static const _fileName = 'pending_scrobbles.json';
  static const _version = 1;

  /// 最多留多少条。按一首 3 分钟算,200 条约等于连听十小时;
  /// 再多就不是「临时发不出去」,而是这台设备长期离线 —— 那时丢最老的也不亏。
  static const limit = 200;

  static Future<ScrobbleStore> open({Directory? root}) async {
    try {
      final dir = root ?? await _defaultRoot();
      return ScrobbleStore._(dir);
    } catch (_) {
      // 目录建不出来(权限 / 沙箱)不该让应用起不来 —— 与另外几个缓存同一条口径。
      return ScrobbleStore._(null);
    }
  }

  File? get _file {
    final root = _root;
    if (root == null) return null;
    return File('${root.path}${Platform.pathSeparator}$_fileName');
  }

  /// 读回待补的那几笔(按时间从早到晚)。
  Future<List<PendingScrobble>> load() async {
    final file = _file;
    if (file == null || !file.existsSync()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['version'] != _version) return const [];
      final list = raw['items'];
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map)
            ?PendingScrobble.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      // 半截 JSON / 手改坏了:当作没有待补的(比每次启动都抛好)。
      return const [];
    }
  }

  /// 整体重写。**调用方给的就是权威那份**(内存里那一份)。
  Future<void> replaceAll(List<PendingScrobble> items) async {
    final file = _file;
    if (file == null) return;
    final trimmed = items.length <= limit
        ? items
        : items.sublist(items.length - limit);
    try {
      // 临时文件 + 改名:半截 JSON 会被下次读成「坏了」而白丢一整份。
      final tmp = File('${file.path}.part');
      await tmp.writeAsString(jsonEncode({
        'version': _version,
        'items': [for (final item in trimmed) item.toJson()],
      }));
      await tmp.rename(file.path);
    } catch (_) {
      // 写不进去就算了 —— 待补记录丢了只影响统计,不该影响听歌。
    }
  }

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}scrobbles');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}