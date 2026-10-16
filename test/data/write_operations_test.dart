import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/subsonic_auth.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_payload.dart';
import 'package:nordic/data/subsonic_repository.dart';

/// 写操作的**线上形态**:发的是哪个端点、参数叫什么。
///
/// 这几个参数名(尤其 `songIdToAdd` / `songIndexToRemove`、以及收藏三个 id
/// 各归各的参数)是照协议写的。写错了服务器只会回一句「失败」,
/// 不打到线上形态上,就得等真机上才发现。
void main() {
  /// 记下每个请求的完整 Uri(含查询参数),并按 [response] 应答。
  Dio recordingRequests(List<Uri> seen, {Map<String, dynamic>? response}) {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        seen.add(options.uri);
        interceptor.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode(response ??
              {
                'subsonic-response': {'status': 'ok', 'version': '1.16.1'}
              }),
        ));
      },
    ));
    return dio;
  }

  late List<Uri> seen;
  late SubsonicRepository repo;

  setUp(() {
    seen = [];
    repo = SubsonicRepository(SubsonicClient(
      auth: SubsonicAuth(username: 'u', password: 'p'),
      routes: const [
        ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com'),
      ],
      dio: recordingRequests(seen),
    ));
  });

  test('加一首进歌单:updatePlaylist + songIdToAdd', () async {
    await repo.addToPlaylist('pl-1', 'song-9');

    final uri = seen.single;
    expect(uri.path, '/rest/updatePlaylist.view');
    expect(uri.queryParameters['playlistId'], 'pl-1');
    expect(uri.queryParameters['songIdToAdd'], 'song-9');
  });

  test('从歌单移除:**按位置**发 songIndexToRemove', () async {
    // 按 id 移除在协议里没有对应参数;同一首歌在歌单里出现两次时,
    // 也只有位置说得清要移掉哪一次。
    await repo.removeFromPlaylist('pl-1', 2);

    final uri = seen.single;
    expect(uri.path, '/rest/updatePlaylist.view');
    expect(uri.queryParameters['playlistId'], 'pl-1');
    expect(uri.queryParameters['songIndexToRemove'], '2');
  });

  test('重命名走同一个端点,name 参数', () async {
    await repo.renamePlaylist('pl-1', '夜间驾驶');

    final uri = seen.single;
    expect(uri.path, '/rest/updatePlaylist.view');
    expect(uri.queryParameters['name'], '夜间驾驶');
    // 重命名不该顺手把曲目也改了 —— 不同时带其它写参数。
    expect(uri.queryParameters.containsKey('songIdToAdd'), isFalse);
  });

  test('删除歌单:deletePlaylist + id', () async {
    await repo.deletePlaylist('pl-1');

    final uri = seen.single;
    expect(uri.path, '/rest/deletePlaylist.view');
    expect(uri.queryParameters['id'], 'pl-1');
  });

  test('服务器说失败就抛出来,不当作写成功', () async {
    final failing = SubsonicRepository(SubsonicClient(
      auth: SubsonicAuth(username: 'u', password: 'p'),
      routes: const [
        ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com'),
      ],
      dio: recordingRequests(
        <Uri>[],
        response: {
          'subsonic-response': {
            'status': 'failed',
            'version': '1.16.1',
            'error': {'code': 50, 'message': 'Not allowed'},
          }
        },
      ),
    ));

    await expectLater(
      failing.addToPlaylist('pl-1', 'song-9'),
      throwsA(isA<SubsonicException>()
          .having((e) => e.message, 'message', contains('Not allowed'))),
    );
  });

  group('收藏写操作', () {
    test('收藏一首歌:star + id', () async {
      await repo.setStarred(songId: 'song-9', starred: true);

      final uri = seen.single;
      expect(uri.path, '/rest/star.view');
      expect(uri.queryParameters['id'], 'song-9');
      // 三个 id 各归各的参数,别把歌曲 id 塞进 albumId。
      expect(uri.queryParameters.containsKey('albumId'), isFalse);
      expect(uri.queryParameters.containsKey('artistId'), isFalse);
    });

    test('取消收藏一张专辑:unstar + albumId', () async {
      await repo.setStarred(albumId: 'al-1', starred: false);

      final uri = seen.single;
      expect(uri.path, '/rest/unstar.view');
      expect(uri.queryParameters['albumId'], 'al-1');
      expect(uri.queryParameters.containsKey('id'), isFalse);
    });

    test('收藏一位艺人:artistId', () async {
      await repo.setStarred(artistId: 'ar-1', starred: true);

      expect(seen.single.queryParameters['artistId'], 'ar-1');
    });
  });
}
