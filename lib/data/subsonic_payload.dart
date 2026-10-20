import 'package:meta/meta.dart';

import 'json_list.dart';
import 'models.dart';
import 'music_source.dart';
import 'subsonic_mapper.dart';

/// Subsonic / OpenSubsonic 响应外壳。
///
/// 所有端点都返回 `{"subsonic-response": {...}}`,失败时里面带 `error`。
/// 用泛型 [dataOf] 取具体载荷,避免每个端点各写一份外壳解析。
@immutable
class SubsonicEnvelope {
  const SubsonicEnvelope({
    required this.status,
    required this.version,
    this.error,
    this.serverType,
  });

  final String status;
  final String version;
  final SubsonicError? error;

  /// 服务器自称的类型(navidrome / subsonic …),用于界面显示。
  final String? serverType;

  bool get isOk => status == 'ok';

  static SubsonicEnvelope parse(Map<String, dynamic> body) {
    final envelope = body['subsonic-response'];
    if (envelope is! Map) {
      // **带上 statusCode**:这是「服务器答了,但答的不是 Subsonic」——
      // 协议不对,不是这条线路不通。不标的话 `isNetworkFailure` 为真,客户端会把
      // 剩下的每一条线路都试一遍(每条都要等到超时),最后才把真正的原因报出来。
      // 隔壁「JSON 都解析不了」那一条就是这么标的。
      throw const SubsonicException(
        '响应里没有 subsonic-response，可能不是 Subsonic 服务',
        statusCode: 200,
      );
    }
    final errorJson = envelope['error'];
    return SubsonicEnvelope(
      status: envelope['status'] as String? ?? 'failed',
      version: envelope['version'] as String? ?? '',
      serverType: envelope['type'] as String?,
      error: errorJson is Map
          ? SubsonicError(
              code: (errorJson['code'] as num?)?.toInt() ?? 0,
              message: errorJson['message'] as String? ?? '未知错误',
            )
          : null,
    );
  }
}

/// 服务器返回的业务错误。
@immutable
class SubsonicError {
  const SubsonicError({required this.code, required this.message});

  final int code;
  final String message;

  /// 40 = 用户名或密码错误;50 = 权限不足;70 = 数据未找到。
  /// 认证类错误要单独识别 —— 它们意味着「该让用户去改凭据」,
  /// 而不是「重试一下可能就好了」。
  bool get isAuthFailure => code == 40 || code == 44 || code == 50;
}

/// 与服务器对话过程中的失败。[isAuthFailure] 供界面决定是否引导去设置页。
///
/// 继承 [MusicSourceException] —— 界面与状态层只认那个中立基类,所以换一个
/// 音源之后那些 catch 仍然成立。这个类自己只在 `lib/data/` 内部被抛与接。
class SubsonicException extends MusicSourceException {
  const SubsonicException(super.message, {this.code, this.statusCode});

  final int? code;
  final int? statusCode;

  @override
  bool get isAuthFailure => code != null && (code == 40 || code == 44 || code == 50);

  /// 网络层失败(超时、DNS、连接被拒)——调用方据此判断「这条线路不行,换一条」。
  @override
  bool get isNetworkFailure => code == null && statusCode == null;

  @override
  String toString() => 'SubsonicException($code): $message';
}

/// `subsonic-response` 里各端点的载荷。
abstract final class SubsonicPayload {
  /// `getArtists` → `artists.index[].artist[]`
  static List<Map<String, dynamic>> artists(Map<String, dynamic> body) {
    final root = _root(body);
    final indexes = (root['artists'] as Map?)?['index'];
    if (indexes is! List) return const [];
    return [
      for (final index in indexes)
        if (index is Map && index['artist'] is List)
          ...(index['artist'] as List).whereType<Map>(),
    ].map((e) => e.cast<String, dynamic>()).toList();
  }

  /// `getAlbumList2` / `getAlbumList` → `albumList2.album[]`(退回 `albumList`)
  static List<Map<String, dynamic>> albums(Map<String, dynamic> body) {
    final root = _root(body);
    final list = (root['albumList2'] ?? root['albumList']) as Map?;
    return mapList(list?['album']);
  }

  /// `getAlbum` → `album`
  static Map<String, dynamic> album(Map<String, dynamic> body) {
    final album = _root(body)['album'];
    if (album is! Map) {
      throw const SubsonicException('专辑详情响应里没有 album');
    }
    return album.cast<String, dynamic>();
  }

  /// `getArtist` → `artist`(含 `album[]` 与 `song[]`)
  static Map<String, dynamic> artist(Map<String, dynamic> body) {
    final artist = _root(body)['artist'];
    if (artist is! Map) {
      throw const SubsonicException('艺人详情响应里没有 artist');
    }
    return artist.cast<String, dynamic>();
  }

  /// `getPlaylists` → `playlists.playlist[]`
  static List<Map<String, dynamic>> playlists(Map<String, dynamic> body) {
    final root = _root(body);
    return mapList((root['playlists'] as Map?)?['playlist']);
  }

  /// `getPlaylist` → `playlist`(含 `entry[]`)
  static Map<String, dynamic> playlist(Map<String, dynamic> body) {
    final playlist = _root(body)['playlist'];
    if (playlist is! Map) {
      throw const SubsonicException('歌单详情响应里没有 playlist');
    }
    return playlist.cast<String, dynamic>();
  }

  /// 响应里是否带了 `playlist`。
  ///
  /// `createPlaylist` 在只传 `name` 时,部分实现会返回**没有 playlist 字段**
  /// 的空壳 —— 直接让 [playlist] 抛异常会误判成「创建失败」。
  static bool hasPlaylist(Map<String, dynamic> body) =>
      _root(body)['playlist'] is Map;

  /// `search3` → `searchResult3` 的三个桶
  static Map<String, dynamic> searchResult(Map<String, dynamic> body) {
    final result = _root(body)['searchResult3'] ?? _root(body)['searchResult2'];
    return result is Map ? result.cast<String, dynamic>() : const {};
  }

  /// `getRandomSongs` / `getSongsByGenre` … → `<bucket>.song[]`
  static List<Map<String, dynamic>> songs(
    Map<String, dynamic> body, {
    required String bucket,
  }) =>
      mapList((_root(body)[bucket] as Map?)?['song']);

  /// `getStarred2` → `starred2`(三个桶:album / song / artist)
  static Map<String, dynamic> starred(Map<String, dynamic> body) {
    final starred = _root(body)['starred2'] ?? _root(body)['starred'];
    return starred is Map ? starred.cast<String, dynamic>() : const {};
  }

  /// `getLyricsBySongId` → 结构化歌词(OpenSubsonic 扩展)。
  /// 返回 `structuredLyrics[]`,每个含 `line[]`(value + start)。
  static List<Map<String, dynamic>> structuredLyrics(Map<String, dynamic> body) {
    final root = _root(body);
    return mapList((root['lyricsList'] as Map?)?['structuredLyrics']);
  }

  /// `getLyrics` → `lyrics`(老接口,纯文本 + 可选 artist/title)
  static Map<String, dynamic> lyrics(Map<String, dynamic> body) {
    final lyrics = _root(body)['lyrics'];
    return lyrics is Map ? lyrics.cast<String, dynamic>() : const {};
  }

  /// `getPlayQueue` → 队列与落点。
  ///
  /// 三条**实测过**的边界(2026-10-19,Navidrome 0.64.2):
  ///
  ///   - 空队列时**根本没有 `entry` 键**(整块 `playQueue` 只有 username/changed
  ///     那几项)—— 缺失就是空,不是「解析失败」;
  ///   - 从没存过时 `changed` 是**零时间**(`0001-01-01T00:00:00Z`)——
  ///     那不是「很久以前改过」,是「从没改过」,一律当 null:界面拿它判断
  ///     「这是不是别的设备留下的」,把它当成一个真实时刻就永远判错;
  ///   - 不支持这个端点的实现会回一个错误(仓库那一层已经吞掉,返回 null)。
  static ({
    List<Song> songs,
    String? currentId,
    Duration position,
    DateTime? changed,
  }) playQueue(Map<String, dynamic> body) {
    final queue = _root(body)['playQueue'];
    final map = queue is Map ? queue.cast<String, dynamic>() : const <String, dynamic>{};
    final changed = map['changed'] is String
        ? DateTime.tryParse(map['changed'] as String)
        : null;
    return (
      songs: SubsonicMapper.songs(mapList(map['entry'])),
      currentId: map['current'] as String?,
      // 毫秒。给了负数 / 没给都当 0(从这一刻开头)。
      position: Duration(milliseconds: (map['position'] as num?)?.toInt() ?? 0),
      // **零时间不是「很久以前改过」,是「从没改过」** —— 一律当 null,
      // 否则界面拿它判断「这是不是别的设备留下的」时会永远判错。
      //
      // 判据不能写成「毫秒数为 0」:`0001-01-01T00:00:00Z` 的毫秒数是个
      // **负数**(公历 1 年在 1970 之前),那个等式永远不成立 ——
      // 实测踩过(用例里钉着)。
      changed: (changed == null || changed.year <= 1) ? null : changed,
    );
  }

  /// `getScanStatus` / `startScan` → 扫描状态。
  ///
  /// `scanning` 缺省按 false:`startScan` 有的实现只回一个空载荷(那意味着
  /// 「收下了,开始扫了」,但这一刻它还没报状态)—— 那时界面照实说「未在扫描」,
  /// 下一秒轮询就会拿到真值。**不编一个 true 出来**。
  static ScanStatus scanStatus(Map<String, dynamic> body) {
    final root = _root(body);
    final status = root['scanStatus'];
    final map = status is Map ? status.cast<String, dynamic>() : const <String, dynamic>{};
    final lastScan = map['lastScan'] is String
        ? DateTime.tryParse(map['lastScan'] as String)
        : null;
    return (
      scanning: map['scanning'] == true,
      count: (map['count'] as num?)?.toInt(),
      lastScan: lastScan,
    );
  }

  static Map<String, dynamic> _root(Map<String, dynamic> body) {
    final envelope = body['subsonic-response'];
    if (envelope is! Map) {
      throw const SubsonicException('响应里没有 subsonic-response，可能不是 Subsonic 服务');
    }
    return envelope.cast<String, dynamic>();
  }

}