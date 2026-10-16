import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

/// 一张专辑。[songCount] / [duration] 是**服务器报的整张**数量,
/// 而 [Song] 列表可能只带了其中一部分 —— 列表页与详情页的差异靠这个字段解释,
/// 不要拿 songs.length 顶替(那会让「库里 30 首、详情只列了 12 首」看起来像漏数据)。
@immutable
class Album {
  const Album({
    required this.id,
    required this.name,
    required this.artist,
    required this.artistId,
    this.coverArtId,
    this.year,
    this.songCount = 0,
    this.duration = Duration.zero,
    this.genre,
    this.created,
  });

  final String id;
  final String name;
  final String artist;

  /// 专辑艺人 id。可能为空(服务器没给),此时专辑页的艺人名不可点。
  final String? artistId;

  /// Subsonic 的 coverArt 标识。为 null 表示这张专辑没有封面,
  /// 界面回退到按 [id] 派生的渐变占位。
  final String? coverArtId;

  final int? year;
  final int songCount;
  final Duration duration;
  final String? genre;
  final DateTime? created;

  bool get hasCover => coverArtId != null && coverArtId!.isNotEmpty;

  /// 落盘用(音乐库缓存,见 `data/library_cache.dart`)。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'artist': artist,
        'artistId': artistId,
        'coverArtId': coverArtId,
        'year': year,
        'songCount': songCount,
        'duration': duration.inSeconds,
        'genre': genre,
        'created': created?.toIso8601String(),
      };

  static Album fromJson(Map<String, dynamic> json) => Album(
        id: json['id'] as String,
        name: json['name'] as String? ?? '未知专辑',
        artist: json['artist'] as String? ?? '未知艺人',
        artistId: json['artistId'] as String?,
        coverArtId: json['coverArtId'] as String?,
        year: (json['year'] as num?)?.toInt(),
        songCount: (json['songCount'] as num?)?.toInt() ?? 0,
        duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
        genre: json['genre'] as String?,
        created: json['created'] is String
            ? DateTime.tryParse(json['created'] as String)
            : null,
      );

  @override
  bool operator ==(Object other) => other is Album && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 一位艺人。
@immutable
class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.albumCount = 0,
    this.coverArtId,
    this.albumIds = const [],
  });

  final String id;
  final String name;

  /// 服务器报的专辑总数。详情页本地只拉到一部分时,两者会不同 ——
  /// 和 [Album.songCount] 同一个道理,页脚要把这件事讲明。
  final int albumCount;

  /// 艺人头像。多数 Navidrome 库没有,**为空是常态**,
  /// 界面一律回退到首字色块(`.plate`),不要去拉不存在的图。
  final String? coverArtId;

  /// `getArtist` 返回的专辑列表(仅 id + 名称),
  /// 用于详情页「专辑」货架少发一轮请求。
  final List<String> albumIds;

  bool get hasCover => coverArtId != null && coverArtId!.isNotEmpty;

  /// 无头像时显示的两个字。中文取前两字,英文取首字母(与原型 `.plate` 一致)。
  String get initials => name.characters.take(2).toString();

  /// 落盘用(音乐库缓存)。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'albumCount': albumCount,
        'coverArtId': coverArtId,
        'albumIds': albumIds,
      };

  static Artist fromJson(Map<String, dynamic> json) => Artist(
        id: json['id'] as String,
        name: json['name'] as String? ?? '未知艺人',
        albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
        coverArtId: json['coverArtId'] as String?,
        albumIds: [
          for (final id in (json['albumIds'] as List? ?? const []))
            if (id is String) id,
        ],
      );

  @override
  bool operator ==(Object other) => other is Artist && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 一首歌。
@immutable
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumId,
    this.artistId,
    this.coverArtId,
    this.track,
    this.duration = Duration.zero,
    this.suffix,
    this.bitRate,
    this.contentType,
    this.sizeBytes,
    this.year,
    this.genre,
    this.created,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String albumId;
  final String? artistId;
  final String? coverArtId;

  /// 曲序。艺人页的「热门」按播放量排,序数无意义,所以可为空。
  final int? track;

  final Duration duration;

  /// 原始文件格式(flac / mp3 …),界面上显示成大写。
  final String? suffix;

  /// 原始码率 kbps。
  final int? bitRate;

  final String? contentType;
  final int? sizeBytes;
  final int? year;
  final String? genre;

  /// 这首曲子**什么时候进的库**。Navidrome 会给(`created`),
  /// 缺了就是 null —— 按添加时间排序时把它排到最后,不假装知道。
  final DateTime? created;

  bool get hasCover => coverArtId != null && coverArtId!.isNotEmpty;

  /// 曲目行的第二行:`FLAC · 780 kbps`(原型 `trackRow` 的格式)。
  String get formatLine {
    final fmt = suffix?.toUpperCase();
    if (fmt == null) return bitRate == null ? '' : '$bitRate kbps';
    return bitRate == null ? fmt : '$fmt · $bitRate kbps';
  }

  /// 落盘用 —— 下载记录里跟着存一份曲目信息。
  ///
  /// **为什么下载要自己带一份**:断网时没有任何地方能问服务器「这首叫什么」,
  /// 而下载管理里要能列出已下好的内容、点着就能播。那份清单只能随身带着,
  /// 否则「下载了也听不了」——库里刷不出来,就哪儿都进不去。
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'albumId': albumId,
        'artistId': artistId,
        'coverArtId': coverArtId,
        'track': track,
        'duration': duration.inSeconds,
        'suffix': suffix,
        'bitRate': bitRate,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        'year': year,
        'genre': genre,
        'created': created?.toIso8601String(),
      };

  static Song fromJson(Map<String, dynamic> json) => Song(
        id: json['id'] as String,
        title: json['title'] as String? ?? '未知曲目',
        artist: json['artist'] as String? ?? '未知艺人',
        album: json['album'] as String? ?? '未知专辑',
        albumId: json['albumId'] as String? ?? '',
        artistId: json['artistId'] as String?,
        coverArtId: json['coverArtId'] as String?,
        track: (json['track'] as num?)?.toInt(),
        duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
        suffix: json['suffix'] as String?,
        bitRate: (json['bitRate'] as num?)?.toInt(),
        contentType: json['contentType'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        year: (json['year'] as num?)?.toInt(),
        genre: json['genre'] as String?,
        created: json['created'] is String
            ? DateTime.tryParse(json['created'] as String)
            : null,
      );

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 歌单。Subsonic 只给条目数与时长,不在这里内联歌曲 ——
/// 详情要另外调 `getPlaylist`。
@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.songCount = 0,
    this.duration = Duration.zero,
    this.description,
    this.coverArtId,
    this.owner,
    this.readonly = false,
    this.changed,
  });

  final String id;
  final String name;
  final int songCount;
  final Duration duration;
  final String? description;
  final String? coverArtId;
  final String? owner;
  final bool readonly;
  final DateTime? changed;

  bool get hasCover => coverArtId != null && coverArtId!.isNotEmpty;

  /// 落盘用(音乐库缓存)。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songCount': songCount,
        'duration': duration.inSeconds,
        'description': description,
        'coverArtId': coverArtId,
        'owner': owner,
        'readonly': readonly,
        'changed': changed?.toIso8601String(),
      };

  static Playlist fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String? ?? '未命名歌单',
        songCount: (json['songCount'] as num?)?.toInt() ?? 0,
        duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
        description: json['description'] as String?,
        coverArtId: json['coverArtId'] as String?,
        owner: json['owner'] as String?,
        readonly: json['readonly'] as bool? ?? false,
        changed: json['changed'] is String
            ? DateTime.tryParse(json['changed'] as String)
            : null,
      );

  /// 只用于**本地快照的就地更新**:改完名字或增删曲目后,库里那一项要跟着变,
  /// 但重拉整库会打断浏览。其余字段不在这里改 —— 它们由服务器说了算。
  Playlist copyWith({String? name, int? songCount}) => Playlist(
        id: id,
        name: name ?? this.name,
        songCount: songCount ?? this.songCount,
        duration: duration,
        description: description,
        coverArtId: coverArtId,
        owner: owner,
        readonly: readonly,
        changed: changed,
      );

  @override
  bool operator ==(Object other) => other is Playlist && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 搜索的三个结果桶。
@immutable
class SearchHits {
  const SearchHits({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
  });

  final List<Song> songs;
  final List<Album> albums;
  final List<Artist> artists;

  int get total => songs.length + albums.length + artists.length;

  bool get isEmpty => total == 0;

  static const empty = SearchHits();
}

/// 一屏歌词里的一句。
@immutable
class LyricLine {
  const LyricLine({required this.text, this.start});

  final String text;

  /// 这句从第几毫秒开始。**可能为 null** —— 非时间轴歌词(LRC 缺失、
  /// 纯文本 .lrc)只有行序。此时逐句高亮要退回按行数平均分布,
  /// 而不是假装时间已知。
  final Duration? start;

  bool get isSynced => start != null;
}

/// 一首歌的歌词。
@immutable
class Lyrics {
  const Lyrics({required this.lines, this.synced = false});

  final List<LyricLine> lines;

  /// 是否带时间轴。决定歌词页走「跟真实进度」还是「按行平均」。
  final bool synced;

  bool get isEmpty => lines.isEmpty;

  static const empty = Lyrics(lines: []);
}

/// 音乐库的一屏数据 —— 五份列表一起换,界面据此一次性重绘。
///
/// 放在数据层(而不是状态层)是因为**它要落盘**:音乐库缓存存的正是这一份
/// (见 `library_cache.dart`),缓存不该反过来依赖状态层。
@immutable
class LibrarySnapshot {
  const LibrarySnapshot({
    required this.albums,
    required this.artists,
    required this.songs,
    required this.playlists,
    required this.recentlyAdded,
  });

  final List<Album> albums;
  final List<Artist> artists;
  final List<Song> songs;
  final List<Playlist> playlists;
  final List<Album> recentlyAdded;

  static const empty = LibrarySnapshot(
    albums: <Album>[],
    artists: <Artist>[],
    songs: <Song>[],
    playlists: <Playlist>[],
    recentlyAdded: <Album>[],
  );

  bool get isEmpty =>
      albums.isEmpty &&
      artists.isEmpty &&
      songs.isEmpty &&
      playlists.isEmpty;

  /// 服务器上标称的总曲目数。取专辑的 songCount 之和而不是 songs.length ——
  /// 后者受我们一次拉多少条的限制,不是库的真实规模。
  int get totalSongs =>
      albums.fold(0, (sum, a) => sum + a.songCount);

  /// 常听艺人:按专辑数取前几位。没有真实播放统计时的合理近似。
  List<Artist> get topArtists {
    final sorted = [...artists]..sort((a, b) => b.albumCount.compareTo(a.albumCount));
    return sorted.take(6).toList();
  }
}
