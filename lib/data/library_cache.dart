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

  Future<void> write(String serverKey, LibrarySnapshot snapshot) async {
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
      };

  static LibrarySnapshot _snapshotFrom(Map<String, dynamic> json) =>
      LibrarySnapshot(
        albums: _list(json['albums'], Album.fromJson),
        artists: _list(json['artists'], Artist.fromJson),
        songs: _list(json['songs'], Song.fromJson),
        playlists: _list(json['playlists'], Playlist.fromJson),
        recentlyAdded: _list(json['recentlyAdded'], Album.fromJson),
      );

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) read) => [
        for (final item in (raw as List? ?? const []))
          if (item is Map) read(item.cast<String, dynamic>()),
      ];
}
