import 'models.dart';

/// Subsonic 响应 → 域模型。
///
/// 界面上不出现 DTO,也不在此处出现 HTTP —— 这里是唯一做映射的地方。
/// 所有字段都按「缺了也能用」写:Subsonic 实现之间字段有无不一,
/// 某个实现少给一个 `bitRate` 不该让整个列表崩掉。
abstract final class SubsonicMapper {
  static Album album(Map<String, dynamic> json) => Album(
        id: json['id'] as String,
        name: _string(json['name']) ?? _string(json['album']) ?? '未知专辑',
        artist: _string(json['artist']) ?? _string(json['displayArtist']) ?? '未知艺人',
        // 有些实现只在 artists[] 里给 id,顶层的 artistId 可能缺。
        artistId: _string(json['artistId']) ?? _firstArtistId(json['artists']),
        coverArtId: _string(json['coverArt']),
        year: _int(json['year']),
        songCount: _int(json['songCount']) ?? 0,
        duration: _duration(json['duration']),
        genre: _string(json['genre']) ?? _firstGenreName(json['genres']),
        created: _date(json['created']),
      );

  static Artist artist(Map<String, dynamic> json) => Artist(
        id: json['id'] as String,
        name: _string(json['name']) ?? '未知艺人',
        albumCount: _int(json['albumCount']) ?? 0,
        coverArtId: _string(json['coverArt']),
        albumIds: [
          for (final a in _mapList(json['album']))
            if (a['id'] is String) a['id'] as String,
        ],
      );

  static Song song(Map<String, dynamic> json) => Song(
        id: json['id'] as String,
        title: _string(json['title']) ?? _string(json['name']) ?? '未知曲目',
        artist: _string(json['artist']) ?? _string(json['displayArtist']) ?? '未知艺人',
        album: _string(json['album']) ?? '未知专辑',
        albumId: _string(json['albumId']) ?? '',
        artistId: _string(json['artistId']) ?? _firstArtistId(json['artists']),
        coverArtId: _string(json['coverArt']),
        track: _int(json['track']),
        duration: _duration(json['duration']),
        suffix: _string(json['suffix']),
        bitRate: _int(json['bitRate']),
        contentType: _string(json['contentType']),
        sizeBytes: _int(json['size']),
        year: _int(json['year']),
        genre: _string(json['genre']),
        // `created` 是「什么时候进的库」—— Navidrome 会给,别的实现可能不给。
        created: _date(json['created']),
      );

  static Playlist playlist(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: _string(json['name']) ?? '未命名歌单',
        songCount: _int(json['songCount']) ?? 0,
        duration: _duration(json['duration']),
        description: _string(json['comment']) ?? _string(json['description']),
        coverArtId: _string(json['coverArt']),
        owner: _string(json['owner']),
        readonly: json['readonly'] as bool? ?? false,
        changed: _date(json['changed']),
      );

  /// `getAlbumList2` 等的批量映射。
  static List<Album> albums(List<Map<String, dynamic>> json) =>
      json.map(album).toList();

  static List<Artist> artists(List<Map<String, dynamic>> json) =>
      json.map(artist).toList();

  static List<Song> songs(List<Map<String, dynamic>> json) =>
      json.map(song).toList();

  static List<Playlist> playlists(List<Map<String, dynamic>> json) =>
      json.map(playlist).toList();

  /// 搜索结果的三个桶。
  static SearchHits search(Map<String, dynamic> result) => SearchHits(
        songs: songs(_mapList(result['song'])),
        albums: albums(_mapList(result['album'])),
        artists: artists(_mapList(result['artist'])),
      );

  /// 结构化歌词(需要 OpenSubsonic 的 `getLyricsBySongId`)。
  ///
  /// 服务器可能给多份(原文 / 翻译 / 罗马音),取第一份带时间轴的;
  /// 都没有时间轴就取第一份,按无时间轴处理 —— 白底黑字也比空屏强。
  static Lyrics lyrics(List<Map<String, dynamic>> structured) {
    if (structured.isEmpty) return Lyrics.empty;

    List<Map<String, dynamic>> linesOf(Map<String, dynamic> block) =>
        _mapList(block['line']);

    final synced = structured.firstWhere(
      (block) => linesOf(block).any((l) => _int(l['start']) != null),
      orElse: () => structured.first,
    );

    final raw = linesOf(synced);
    if (raw.isEmpty) return Lyrics.empty;

    final lines = <LyricLine>[];
    for (final line in raw) {
      final text = _string(line['value']) ?? '';
      // 空行在 LRC 里常用来分段,原样保留会让高亮停在什么都没有的一行上。
      if (text.trim().isEmpty) continue;
      final start = _int(line['start']);
      lines.add(LyricLine(
        text: text,
        start: start == null ? null : Duration(milliseconds: start),
      ));
    }
    if (lines.isEmpty) return Lyrics.empty;

    return Lyrics(
      lines: lines,
      synced: lines.every((l) => l.isSynced),
    );
  }

  /// 老接口 `getLyrics` 的纯文本歌词 —— 没有时间轴。
  /// 有些服务器只实现了它(OpenSubsonic 扩展缺失),此时歌词仍可显示,
  /// 只是无法逐句跟随。
  static Lyrics plainLyrics(Map<String, dynamic> lyrics) {
    final text = _string(lyrics['value']) ?? _string(lyrics['lyrics']);
    if (text == null || text.trim().isEmpty) return Lyrics.empty;
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => LyricLine(text: _stripLrcTimestamps(l)))
        .toList();
    return lines.isEmpty ? Lyrics.empty : Lyrics(lines: lines);
  }

  /// 纯文本里若混着 `[00:12.34]` 这类时间戳,显示时要去掉。
  /// 不移除的话,歌词页会顶着一排方括号数字,像是渲染坏了。
  static String _stripLrcTimestamps(String line) =>
      line.replaceAll(RegExp(r'^(\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\])+\s*'), '');

  // ---- 取值的容错助手。Subsonic 各家实现的字段类型时有出入。 ----

  static String? _string(Object? value) {
    if (value is String) return value.isEmpty ? null : value;
    if (value is num) return '$value';
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Duration _duration(Object? seconds) =>
      Duration(seconds: _int(seconds) ?? 0);

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static String? _firstArtistId(Object? artists) {
    final list = _mapList(artists);
    if (list.isEmpty) return null;
    return _string(list.first['id']);
  }

  static String? _firstGenreName(Object? genres) {
    final list = _mapList(genres);
    if (list.isEmpty) return null;
    return _string(list.first['name']);
  }

  static List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
}