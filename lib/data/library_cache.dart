import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// 一次缓存下来的音乐库快照,连同「什么时候存的」。
class CachedLibrary {
  const CachedLibrary({required this.snapshot, required this.savedAt});

  final LibrarySnapshot snapshot;
  final DateTime savedAt;
}

/// 音乐库快照的本机缓存。
///
/// **为什么要有它**:每次启动都要从服务器重拉一整份(专辑 / 艺人 / 全部歌曲 /
/// 歌单 + 最近添加),那要等上几秒,而这份内容一分钟内不会变。有了缓存:
///
///   1. 冷启动**立刻**就能把库铺出来,随后再静默刷新;
///   2. 刷新失败(断网、服务器临时不通)时还有东西可看 —— 不再是一片空白
///      加一个「重试」。
///
/// 缓存的边界说清楚:它存的是**列表**,不存音频(那是下载的事,见
/// `download_store.dart`)。快照按 [serverKey] 分辨 —— 换了服务器就不该拿
/// 上一台的库当自己的。
class LibraryCache {
  LibraryCache._(this._root);

  /// 缓存目录。null 表示这块存储用不了(建不出来),这时一切都是空操作。
  final Directory? _root;

  static const _fileName = 'library.json';
  static const _version = 1;

  /// 打开缓存。[root] 只给测试用 —— 生产路径由平台目录决定。
  ///
  /// 缓存**不可用不该让应用起不来**:读不到就当没缓存,写不进就算了。
  static Future<LibraryCache> open({Directory? root}) async {
    try {
      final dir = root ?? await _defaultRoot();
      if (!dir.existsSync()) await dir.create(recursive: true);
      return LibraryCache._(dir);
    } catch (_) {
      return LibraryCache._(null);
    }
  }

  static Future<Directory> _defaultRoot() async {
    Directory base;
    try {
      base = await getApplicationSupportDirectory();
    } on MissingPluginException {
      // 桌面 / 测试环境没有这个插件。
      base = Directory.systemTemp;
    }
    return Directory('${base.path}${Platform.pathSeparator}cache');
  }

  bool get isAvailable => _root != null;

  File? get _file {
    final root = _root;
    if (root == null) return null;
    return File('${root.path}${Platform.pathSeparator}$_fileName');
  }

  /// 读回上次的快照。
  ///
  /// 服务器对不上、文件坏了、版本变了都当**没有缓存** —— 拿一台服务器的库
  /// 去顶另一台,比空着更糟。
  Future<CachedLibrary?> read(String serverKey) async {
    final file = _file;
    if (file == null || !file.existsSync()) return null;

    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      if (json['version'] != _version) return null;
      if (json['serverKey'] != serverKey) return null;

      final data = json['data'];
      if (data is! Map) return null;

      final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '');
      if (savedAt == null) return null;

      return CachedLibrary(
        snapshot: _snapshotFrom(data.cast<String, dynamic>()),
        savedAt: savedAt,
      );
    } catch (_) {
      // 损坏的缓存直接丢掉,下次刷新会重写一份。
      return null;
    }
  }

  /// 正在跑的那一次写。**同一时刻只许有一个写者**。
  ///
  /// 两次写撞在一起会各写各的临时文件、各自改名,谁赢不好说;而清缓存 / 换服务器
  /// 要删的正是这个文件 —— 撞上就是「删到一半又被写回来」。
  Future<void>? _writing;

  /// 写着的时候又来了新的一份:**只留最新的那一份**,中间的直接跳过。
  /// 界面要的是「最后落盘的是最新的库」,而不是把每一次都写一遍。
  (String, LibrarySnapshot)? _pending;

  /// 排队那一份落盘时完成的信号 —— 等在 [write] 上的调用者拿到的是它。
  Completer<void>? _pendingDone;

  /// 把快照落盘。
  ///
  /// **合并写**:后台补齐曲目时会连着要求写好几次(每翻一页一次),而每一次都要
  /// 把整份快照编码一遍 —— 越写越大,合起来是平方级的活。这里只保证
  /// 「最新的那一份最终落盘」,中间那几版没人要。
  ///
  /// 返回的 future 在**这次写(或排队的那一份)真的落盘之后**才完成 ——
  /// 所以 `await write(...)` 之后读同一份文件一定读得到,调用方不必改语义。
  Future<void> write(String serverKey, LibrarySnapshot snapshot) {
    if (_writing != null) {
      _pending = (serverKey, snapshot);
      return (_pendingDone ??= Completer<void>()).future;
    }
    final run = _writeOnce(serverKey, snapshot);
    _writing = run;
    return run;
  }

  Future<void> _writeOnce(String serverKey, LibrarySnapshot snapshot) async {
    await _writeAtomically(serverKey, snapshot);
    // 写的这一会儿又攒下了新的:接着写最新的那份(不是每一份)。
    while (_pending != null) {
      final (key, next) = _pending!;
      _pending = null;
      await _writeAtomically(key, next);
    }
    _writing = null;
    final done = _pendingDone;
    _pendingDone = null;
    done?.complete();
  }

  /// 等到手上这次写(以及它后面排队的那一份)落盘为止。
  ///
  /// **删除 / 清空之前必须调它**:写盘的文件句柄在这次的 await 之前不会释放,
  /// 飘着删会让紧跟其后的清理撞上「文件正被占用」。
  Future<void> settle() async {
    while (_writing != null) {
      await _writing;
    }
  }

  Future<void> _writeAtomically(
    String serverKey,
    LibrarySnapshot snapshot,
  ) async {
    final file = _file;
    if (file == null) return;

    final payload = {
      'version': _version,
      'serverKey': serverKey,
      'savedAt': DateTime.now().toIso8601String(),
      'data': _snapshotToJson(snapshot),
    };

    try {
      // 先写临时文件再改名:写到一半断电不会留下半截 JSON,
      // 下次启动读它时被判成「坏了」而白丢一份缓存。
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // 写不进就算了 —— 缓存失败不该影响这次浏览。
    }
  }

  /// 清掉缓存(用户移除服务器时调用 —— 那台机器的库不再属于这里)。
  Future<void> clear() async {
    await settle();
    final file = _file;
    if (file == null || !file.existsSync()) return;
    try {
      await file.delete();
    } catch (_) {
      // 删不掉也只是留着占地方。
    }
  }

  // ---------------- 快照的落盘形态 ----------------

  static Map<String, dynamic> _snapshotToJson(LibrarySnapshot snapshot) => {
        'albums': [for (final a in snapshot.albums) a.toJson()],
        'artists': [for (final a in snapshot.artists) a.toJson()],
        'songs': [for (final s in snapshot.songs) s.toJson()],
        'playlists': [for (final p in snapshot.playlists) p.toJson()],
        'recentlyAdded': [for (final a in snapshot.recentlyAdded) a.toJson()],
        'recentlyAddedSongs': [for (final s in snapshot.recentlyAddedSongs) s.toJson()],
        'recentlyPlayed': [for (final a in snapshot.recentlyPlayed) a.toJson()],
        'mostPlayed': [for (final a in snapshot.mostPlayed) a.toJson()],
        // 「取全了没有」跟着一起落盘:不存的话,一个已经取全的库冷启动读回来
        // 会被当成「还差一截」,页脚挂上「还有 N 首没取」,下一次翻页又从
        // offset 0 重来一遍(把第一页白拉一次)。
        'songsComplete': snapshot.songsComplete,
      };

  static LibrarySnapshot _snapshotFrom(Map<String, dynamic> json) =>
      LibrarySnapshot(
        albums: _list(json['albums'], Album.fromJson),
        artists: _list(json['artists'], Artist.fromJson),
        songs: _list(json['songs'], Song.fromJson),
        playlists: _list(json['playlists'], Playlist.fromJson),
        recentlyAdded: _list(json['recentlyAdded'], Album.fromJson),
        recentlyAddedSongs: _list(json['recentlyAddedSongs'], Song.fromJson),
        // 前一版缓存里没有这两个货架 —— 读不到就是空列表,首页那一栏不显示,
        // 不是错误(下一次刷新就补上了)。
        recentlyPlayed: _list(json['recentlyPlayed'], Album.fromJson),
        mostPlayed: _list(json['mostPlayed'], Album.fromJson),
        // 同样:前一版缓存里没有这一位,读出来是 false(当成没取全)—— 下一轮
        // 刷新会按真实情况改写它,最多多花一次请求。
        songsComplete: json['songsComplete'] == true,
      );

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) read) => [
        for (final item in (raw as List? ?? const []))
          if (item is Map) read(item.cast<String, dynamic>()),
      ];
}
