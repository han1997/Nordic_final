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

  bool get hasCover => coverArtId != null && coverArtId!.isNotEmpty;

  /// 曲目行的第二行:`FLAC · 780 kbps`(原型 `trackRow` 的格式)。
  String get formatLine {
    final fmt = suffix?.toUpperCase();
    if (fmt == null) return bitRate == null ? '' : '$bitRate kbps';
    return bitRate == null ? fmt : '$fmt · $bitRate kbps';
  }

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