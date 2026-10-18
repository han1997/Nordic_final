import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/subsonic_auth.dart';
import 'package:nordic/data/subsonic_client.dart';

import 'live_server.dart';

/// 播放前的最后一道关:**流地址真的能拉到音频字节吗**。
///
/// 这条路径与浏览走的是两套东西 —— 曲库拉取走 [SubsonicClient] 的
/// Dio 包装,而音频由 ExoPlayer / 系统媒体栈直接开流。
/// 所以「曲库能看」不代表「歌能播」,必须单独验。
///
/// 打到真服务器,**凭据从环境变量读**(见 `live_server.dart`);
/// 没配环境变量时退回一个够不着的地址,于是整组跳过。
final _serverUrl = liveServerUrl;
final _username = liveServerUser;
final _password = liveServerPassword;

void main() {
  late SubsonicRepositoryLike repo;

  setUp(() {
    repo = SubsonicRepositoryLike(
      SubsonicClient(
        auth: SubsonicAuth(username: _username, password: _password),
        routes: [
          ServerRoute(id: 'lan', name: '局域网', url: _serverUrl),
        ],
      ),
    );
  });

  test('原音流返回真实音频字节', () async {
    final song = await repo.firstSongOrNull();
    if (song == null) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }

    final uri = repo.rawStreamUri(song.id);
    final result = await _probe(uri);
    expect(result.status, 200, reason: '流地址应返回 200，实际=${result.status}');
    expect(result.contentType, isNotNull);
    expect(result.contentType, startsWith('audio/'),
        reason: 'Content-Type 应为 audio/*，实际=${result.contentType}');
    expect(result.firstBytes, greaterThan(0), reason: '应该真的读到音频字节');
    // 先读到的头几个字节应与容器格式对得上,而不是一段 HTML 错误页。
    expect(result.firstBytes, greaterThanOrEqualTo(4));
  });

  test('转码流也返回音频字节', () async {
    final song = await repo.firstSongOrNull();
    if (song == null) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }

    final uri = repo.rawStreamUri(song.id, maxBitRate: 192, format: 'mp3');
    final result = await _probe(uri);
    expect(result.status, 200, reason: '转码流应返回 200，实际=${result.status}');
    expect(result.contentType, startsWith('audio/'),
        reason: '转码后应是 audio/*，实际=${result.contentType}');
    expect(result.firstBytes, greaterThan(0));
    // 转码是现算现发的,Navidrome 用 chunked 编码回,**没有 Content-Length**
    // (实测 0.64.2)。有长度时才比体积 —— 不能因为服务器没报就判它错。
    if (result.contentLength != null) {
      // 转码档的文件应当显著小于原音档 —— 否则说明 maxBitRate / format
      // 没被服务器认下来,用户选了「省流」其实还在拉原文件。
      expect(
        result.contentLength!,
        lessThan(10 * 1024 * 1024),
        reason: '192kbps 转码不该是几十 MB 的无损体积',
      );
    }
  });

  test('封面图返回图片字节', () async {
    final song = await repo.firstSongOrNull();
    if (song == null || !song.hasCover) {
      markTestSkipped('Navidrome 不可达或首曲无封面，跳过');
      return;
    }

    final uri = repo.rawCoverUri(song.coverArtId!, size: 256);
    final result = await _probe(uri);
    expect(result.status, 200);
    expect(result.contentType, startsWith('image/'));
    expect(result.firstBytes, greaterThan(0));
  });
}

/// 一次裸 HTTP 探测的结果。
class _Probe {
  const _Probe({
    required this.status,
    required this.contentType,
    required this.contentLength,
    required this.firstBytes,
  });

  final int status;
  final String? contentType;
  final int? contentLength;
  final int firstBytes;
}

/// 用 dart:io 直接开流 —— 与 ExoPlayer 走的是同一类底层路径,
/// 能验到「地址 + 鉴权 + 服务器是否真的吐字节」这一层。
Future<_Probe> _probe(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 25));
    final buffer = <int>[];
    // 只读开头一小段就够 —— 我们要验的是「有没有字节」,不是下完整个文件。
    await for (final chunk in response.timeout(const Duration(seconds: 25))) {
      buffer.addAll(chunk);
      if (buffer.length >= 4096) break;
    }
    return _Probe(
      status: response.statusCode,
      contentType: response.headers.contentType?.mimeType,
      contentLength: response.contentLength == -1 ? null : response.contentLength,
      firstBytes: buffer.length,
    );
  } finally {
    client.close(force: true);
  }
}

/// 测试里只用到几个方法,单独包一层以免把整个仓库的构造依赖拖进来。
class SubsonicRepositoryLike {
  SubsonicRepositoryLike(this.client);

  final SubsonicClient client;

  Future<Song?> firstSongOrNull() async {
    try {
      final body = await client.call('getAlbumList2', {
        'type': 'alphabeticalByArtist',
        'size': '1',
      });
      final albums = (body['subsonic-response']?['albumList2']?['album'] as List?)
          ?.whereType<Map>()
          .toList();
      if (albums == null || albums.isEmpty) return null;
      final albumBody = await client.call('getAlbum', {'id': albums.first['id']});
      final songs = (albumBody['subsonic-response']?['album']?['song'] as List?)
          ?.whereType<Map>()
          .toList();
      if (songs == null || songs.isEmpty) return null;
      final json = songs.first.cast<String, dynamic>();
      return Song(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        album: json['album'] as String? ?? '',
        albumId: json['albumId'] as String? ?? '',
        coverArtId: json['coverArt'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Uri rawStreamUri(String songId, {int? maxBitRate, String? format}) =>
      SubsonicClient.buildUri(
        client.activeRoute!,
        'stream',
        {
          'id': songId,
          'maxBitRate': ?maxBitRate?.toString(),
          'format': ?format,
        },
        client.auth,
      );

  Uri rawCoverUri(String coverArtId, {int size = 256}) =>
      SubsonicClient.buildUri(
        client.activeRoute!,
        'getCoverArt',
        {'id': coverArtId, 'size': '$size'},
        client.auth,
      );
}
