import 'package:meta/meta.dart';

import 'json_list.dart';

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
      throw const SubsonicException('响应里没有 subsonic-response,可能不是 Subsonic 服务');
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
class SubsonicException implements Exception {
  const SubsonicException(this.message, {this.code, this.statusCode});

  final String message;
  final int? code;
  final int? statusCode;

  bool get isAuthFailure => code != null && (code == 40 || code == 44 || code == 50);

  /// 网络层失败(超时、DNS、连接被拒)——调用方据此判断「这条线路不行,换一条」。
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

  static Map<String, dynamic> _root(Map<String, dynamic> body) {
    final envelope = body['subsonic-response'];
    if (envelope is! Map) {
      throw const SubsonicException('响应里没有 subsonic-response,可能不是 Subsonic 服务');
    }
    return envelope.cast<String, dynamic>();
  }

}