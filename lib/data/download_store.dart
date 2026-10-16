import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// 一次下载(一张专辑 / 一位艺人的歌 / 单曲)在磁盘上的记录。
///
/// [files] 是**曲目 id → 相对路径**,离线播放就查它 ——
/// 下载的全部意义在这个映射里:有它,播放时才知道哪首歌不用走网络。
/// 路径存相对值,根目录变了(重装、换设备路径)记录还作数。
class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.name,
    required this.detail,
    required this.format,
    required this.bytes,
    required this.files,
    required this.completedAt,
    this.tracks = const [],
    this.cover,
    this.coverArtId,
  });

  /// 任务 id,同时也是它在根目录下的子目录名。
  final String id;

  final String name;

  /// 界面第二行的来源,如「12 首 · 整张」。
  final String detail;

  /// 容器格式,如 `FLAC`。取首曲的后缀 —— 整张专辑极少混格式。
  final String format;

  /// 落盘总字节数。
  final int bytes;

  /// 曲目 id → 相对根目录的路径。
  final Map<String, String> files;

  /// 下下来的曲目本身的信息。
  ///
  /// [files] 只答「在哪」,不答「是什么」—— 断网时没有任何地方能问服务器
  /// 这首叫什么,而下载管理里要能列出来点着播。所以清单随身带一份。
  final List<Song> tracks;

  /// 封面图在磁盘上的相对路径。没下到就是 null。
  final String? cover;

  /// 那张封面对应的 `coverArtId`。
  ///
  /// 记它是因为界面上的封面是**按 coverArtId 找**的(专辑、艺人、歌单都是),
  /// 有了这个映射,「这张图本机有没有」才答得上来 —— 否则离线时只能眼看
  /// 一块渐变铺在那里。
  final String? coverArtId;

  final DateTime completedAt;

  /// 界面上的体积文案。小数位没有意义,四舍五入到整 MB。
  String get sizeLabel => '${(bytes / (1024 * 1024)).round()} MB';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'detail': detail,
        'format': format,
        'bytes': bytes,
        'files': files,
        'tracks': [for (final t in tracks) t.toJson()],
        'cover': cover,
        'coverArtId': coverArtId,
        'completedAt': completedAt.toIso8601String(),
      };

  static DownloadRecord? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) return null;
    return DownloadRecord(
      id: id,
      name: json['name'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      format: json['format'] as String? ?? '',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      files: {
        for (final e in (json['files'] as Map? ?? const {}).entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      },
      tracks: [
        for (final t in (json['tracks'] as List? ?? const []))
          if (t is Map) Song.fromJson(t.cast<String, dynamic>()),
      ],
      cover: json['cover'] as String?,
      coverArtId: json['coverArtId'] as String?,
      completedAt:
          DateTime.tryParse(json['completedAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 下载内容的落盘处。
///
/// 布局:
/// ```
/// <根>/index.json                 记录清单(哪些曲目下过、在哪)
/// <根>/<任务 id>/01 - 曲名.flac    音频,一首一个文件
/// <根>/<任务 id>/cover.jpg         封面,任务里共用一张
/// ```
///
/// **根目录选在外部私有目录**(Android:`Android/data/包名/files/Nordic/Music`)。
/// 挑它是因为它同时满足三件事:不用申请任何权限就能写、在文件管理器里
/// 看得到(界面上承诺的「存到本机的 Nordic/Music 目录」是真的)、
/// 卸载应用时随应用一起清掉 —— 不至于在用户手机上留下一堆无主的音乐。
///
/// 拿不到外部目录(桌面 / iOS / 外部存储被卸载)就退到应用支持目录:
/// 位置不那么好看,但下载功能不因此消失。
class DownloadStore {
  DownloadStore._(this._root, this._records);

  /// 根目录。为 null 表示这块存储用不了 —— 见 [isAvailable]。
  final Directory? _root;

  final List<DownloadRecord> _records;

  /// 曲目 id → 绝对路径。播放层每次构建播放源都查它,预先摊平。
  final Map<String, String> _bySongId = {};

  static const _indexName = 'index.json';
  static const _version = 1;

  /// 界面与文案里出现的目录名。
  static const label = 'Nordic/Music';

  bool get isAvailable => _root != null;

  /// 本机存下载内容的位置(绝对路径),给界面显示用。
  String get rootPath => _root?.path ?? '';

  /// 已完成的下载记录,新的在前。
  List<DownloadRecord> get records => List.unmodifiable(_records);

  /// 打开存储。[root] 只给测试用 —— 生产路径一律由平台目录决定。
  static Future<DownloadStore> open({Directory? root}) async {
    try {
      final dir = root ?? await _resolveRoot();
      // 拿到目录先确认它真的能用(存在、可写)。这一步放在这里而不是
      // 第一次下载时,是因为「这块存储用不了」要在开界面之前就知道。
      if (!dir.existsSync()) await dir.create(recursive: true);
      final store = DownloadStore._(dir, []);
      await store._load();
      return store;
    } catch (_) {
      // 目录建不出来(存储满 / 权限诡异)不该让应用起不来 ——
      // 退化成一块「不可用」的存储,下载入口给出人话,别的地方照常用。
      return DownloadStore._(null, []);
    }
  }

  static Future<Directory> _resolveRoot() async {
    Directory base;
    try {
      final external = await getExternalStorageDirectory();
      base = external ?? await getApplicationSupportDirectory();
    } on MissingPluginException {
      // 平台没有这个插件(测试 / 不支持的平台)。
      base = await getApplicationSupportDirectory();
    }
    return Directory('${base.path}${Platform.pathSeparator}Nordic'
        '${Platform.pathSeparator}Music');
  }

  Future<void> _load() async {
    final root = _root;
    if (root == null) return;
    final index = File('${root.path}${Platform.pathSeparator}$_indexName');
    if (!index.existsSync()) return;

    try {
      final json = jsonDecode(await index.readAsString());
      final list = (json as Map<String, dynamic>)['records'];
      for (final raw in (list as List? ?? const [])) {
        if (raw is! Map) continue;
        final record = DownloadRecord.fromJson(raw.cast<String, dynamic>());
        if (record != null) _records.add(record);
      }
    } catch (_) {
      // 索引坏了就当作没下过东西。**不动磁盘上的文件** ——
      // 记录可以重建,删错的文件回不来。
      _records.clear();
    }
    _reindex();
  }

  void _reindex() {
    _bySongId.clear();
    for (final record in _records) {
      for (final entry in record.files.entries) {
        _bySongId[entry.key] = _absolute(entry.value);
      }
    }
  }

  String _absolute(String relative) => '${_root!.path}'
      '${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';

  /// 这首歌是不是已经在本地。返回绝对路径,没有就是 null。
  String? localPathFor(String songId) => _bySongId[songId];

  /// 这张封面在本机的路径。没下过就是 null。
  ///
  /// 界面与通知栏都用它:封面是按 `coverArtId` 找的(专辑、艺人、歌单同一套),
  /// 所以这里也按 artId 找 —— 下过哪张就认哪张,不会把艺人的图当专辑的图。
  String? coverPathForArt(String? coverArtId) {
    if (coverArtId == null || coverArtId.isEmpty) return null;
    for (final record in _records) {
      if (record.coverArtId == coverArtId) {
        final cover = record.cover;
        return cover == null ? null : _absolute(cover);
      }
    }
    return null;
  }

  // ---- 任务 id 的命名 ----
  // 落盘目录名就是任务 id,而「某张专辑下过没有」要靠同一套命名回答,
  // 所以命名只有这一处,下载器与查询方都用它。

  static String albumTaskId(String albumId) => 'dl-album-$albumId';

  static String artistTaskId(String artistId) => 'dl-artist-$artistId';

  static String songTaskId(String songId) => 'dl-song-$songId';

  /// 任务自己的目录(不存在则建)。
  Future<Directory> directoryFor(String taskId) async {
    final dir = Directory('${_root!.path}${Platform.pathSeparator}$taskId');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// 登记一条完成的下载。同 id 覆盖旧的 —— 重试就是同一个 id。
  Future<void> add(DownloadRecord record) async {
    _records.removeWhere((r) => r.id == record.id);
    _records.insert(0, record);
    _reindex();
    await _save();
  }

  /// 删掉一条记录**连同它的文件**。
  ///
  /// 删文件是这一步的实质:下载管理里抹掉一行却留着几百 MB 占用空间,
  /// 用户是按「删掉」理解的,不是按「隐藏」。
  Future<void> remove(String id) async {
    _records.removeWhere((r) => r.id == id);
    _reindex();
    await _save();

    final root = _root;
    if (root == null) return;
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  Future<void> _save() async {
    final root = _root;
    if (root == null) return;
    final index = File('${root.path}${Platform.pathSeparator}$_indexName');
    final payload = {
      'version': _version,
      'records': [for (final r in _records) r.toJson()],
    };
    // 先写临时文件再改名:中途断电不会留下一个半截的索引。
    final temp = File('${index.path}.tmp');
    await temp.writeAsString(jsonEncode(payload), flush: true);
    await temp.rename(index.path);
  }

  /// 一首曲子在磁盘上的文件名。
  ///
  /// 带序号是因为同专辑重名曲目真存在(不同版本的同一首),
  /// 也为了让文件管理器里的顺序就是专辑里的顺序。
  /// 标题里的分隔符必须清掉 —— 一个 `/` 就能把路径指到别的目录去。
  static String trackFileName(int index, Song song) {
    final number = (index + 1).toString().padLeft(2, '0');
    final title = _sanitize(song.title);
    final ext = _extensionOf(song.suffix);
    // 不知道格式就**不要扩展名** —— 安一个错的(比如把 aac 写成 mp3)
    // 会让解码器按错的格式去解,交给它自己嗅探反而稳。
    return ext.isEmpty ? '$number - $title' : '$number - $title.$ext';
  }

  /// 后缀只留字母数字。取值来自服务器,但它通向文件名 ——
  /// 一个斜杠或者一个点就能把文件指到别的地方去。
  static String _extensionOf(String? raw) {
    if (raw == null) return '';
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
    return cleaned.length <= 8 ? cleaned : '';
  }

  static String _sanitize(String raw) {
    // Windows 上非法的那几个字符一并挡掉 —— 同一份代码要能在桌面上跑。
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '未命名';
    return cleaned.length <= 60 ? cleaned : cleaned.substring(0, 60);
  }
}
