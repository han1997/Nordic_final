import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/play_queue.dart';
import 'package:nordic/data/subsonic_auth.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_payload.dart';
import 'package:nordic/data/subsonic_repository.dart';

/// 队列同步那两半:**解析**(服务器给的东西长什么样)与**窗口 / 指纹**
/// (我们自己拼出去的那一份)。
///
/// 解析那几条的形状是**实测过的**(2026-10-19,Navidrome 0.64.2)——
/// 空队列与从没存过时它给的就是下面第一组那几个字面量。
void main() {
  group('playQueue 解析', () {
    test('空队列：没有 entry 键，changed 是零时间', () {
      // 这是那台服务器**原样**回的(从没保存过任何队列时)。
      final queue = SubsonicPayload.playQueue({
        'subsonic-response': {
          'status': 'ok',
          'version': '1.16.1',
          'playQueue': {
            'username': 'hhy',
            'changed': '0001-01-01T00:00:00Z',
            'changedBy': '',
          },
        }
      });

      expect(queue.songs, isEmpty);
      expect(queue.currentId, isNull);
      expect(queue.position, Duration.zero);
      // **零时间不是「很久以前改过」**:它是「从没改过」。当成一个真实时刻的话,
      // 「这是不是别的设备留下的」那个判断就永远错。
      expect(queue.changed, isNull);
    });

    test('有队列：entry 映射成 Song,current / position 跟着', () {
      final queue = SubsonicPayload.playQueue({
        'subsonic-response': {
          'status': 'ok',
          'playQueue': {
            'entry': [
              {
                'id': 's1',
                'title': '一',
                'artist': '甲',
                'album': 'A',
                'albumId': 'al-1',
                'duration': 200,
                'suffix': 'flac',
              },
              {
                'id': 's2',
                'title': '二',
                'artist': '乙',
                'album': 'A',
                'albumId': 'al-1',
                'duration': 180,
              },
            ],
            'current': 's2',
            'position': 92000,
            'changed': '2026-10-19T08:31:02Z',
          },
        }
      });

      expect(queue.songs.map((s) => s.id), ['s1', 's2']);
      expect(queue.songs.first.title, '一');
      expect(queue.currentId, 's2');
      expect(queue.position, const Duration(seconds: 92));
      expect(queue.changed, isNotNull);
    });

    test('整块 playQueue 都没有时也不炸 —— 当作空队列', () {
      final queue = SubsonicPayload.playQueue({
        'subsonic-response': {'status': 'ok', 'version': '1.16.1'},
      });

      expect(queue.songs, isEmpty);
      expect(queue.changed, isNull);
    });
  });

  group('仓库那一层：不支持就返回 null', () {
    Dio responding(Map<String, dynamic> body) {
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, interceptor) => interceptor.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode(body),
        )),
      ));
      return dio;
    }

    SubsonicRepository repoOf(Map<String, dynamic> body) =>
        SubsonicRepository(SubsonicClient(
          auth: SubsonicAuth(username: 'u', password: 'p'),
          routes: const [
            ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com'),
          ],
          dio: responding(body),
        ));

    test('服务器说不支持这个端点 → null（而不是抛出去）', () async {
      // 有的实现回的就是一句失败。它是**可选能力**:抛出去只会让启动路径上
      // 多一条没人处理的错误,而界面上什么也做不了。
      final repo = repoOf({
        'subsonic-response': {
          'status': 'failed',
          'version': '1.16.1',
          'error': {'code': 70, 'message': '数据未找到'},
        }
      });

      expect(await repo.playQueue(), isNull);
    });

    test('服务器给了空队列 → 不是 null，是一份空队列', () async {
      // 两者的差别要紧:null 是「问不到」,空是「没有队列」——
      // 后者同样不该问「接着上次听?」,但界面能据此说清是哪一种。
      final repo = repoOf({
        'subsonic-response': {
          'status': 'ok',
          'version': '1.16.1',
          'playQueue': {'username': 'u', 'changed': '0001-01-01T00:00:00Z'},
        }
      });

      final queue = await repo.playQueue();
      expect(queue, isNotNull);
      expect(queue!.songs, isEmpty);
    });
  });

  group('queueWindow', () {
    List<Song> songsOf(int n) => [
          for (var i = 0; i < n; i++)
            Song(
              id: 's$i',
              title: '$i',
              artist: '甲',
              album: 'A',
              albumId: 'al-1',
            ),
        ];

    test('短队列原样带走', () {
      final songs = songsOf(20);
      final window = queueWindow(songs, 's5');

      expect(window.songs.length, 20);
      expect(window.currentId, 's5');
    });

    test('长队列截到 200，而且 current 一定在里面', () {
      // 这是一条 GET 查询串:几千个 id 拼出来的 URL 会被反向代理挡下。
      final songs = songsOf(3000);
      final window = queueWindow(songs, 's1500');

      expect(window.songs.length, 200);
      expect(window.currentId, 's1500');
      expect(window.songs.any((s) => s.id == 's1500'), isTrue,
          reason: 'current 不在名单里的话，服务器按 id 找不到它，这一份就白存了');
      // 前面留 49 首:换设备接着听,往回想几首是常事。
      expect(window.songs.first.id, 's1451');
      expect(window.songs.last.id, 's1650');
    });

    test('当前在第一首附近：窗口往右挪，不越界', () {
      final window = queueWindow(songsOf(500), 's0');

      expect(window.songs.length, 200);
      expect(window.songs.first.id, 's0');
      expect(window.currentId, 's0');
    });

    test('当前在最后一首附近：窗口往左挪，不越界', () {
      final songs = songsOf(500);
      final window = queueWindow(songs, 's499');

      expect(window.songs.length, 200);
      expect(window.songs.last.id, 's499');
      expect(window.currentId, 's499');
    });

    test('current 不在队列里：取开头一段，并把 current 让给服务器定', () {
      final window = queueWindow(songsOf(500), '不在名单里的那一首');

      expect(window.songs.length, 200);
      // 报一个不在名单里的 id 上去,服务器只会按第一首处理 —— 那还不如明说
      // 「我没定」,让它自己定。
      expect(window.currentId, isNull);
    });
  });

  group('queueMark', () {
    Song song(String id) =>
        Song(id: id, title: id, artist: '甲', album: 'A', albumId: 'al-1');

    test('同一份队列的指纹一样', () {
      final a = queueMark(songs: [song('s1'), song('s2')], currentId: 's1');
      final b = queueMark(songs: [song('s1'), song('s2')], currentId: 's1');

      expect(a, b);
    });

    test('条数 / 头 / 尾 / 当前那一首，任何一件变了就不是同一份', () {
      final base = queueMark(songs: [song('s1'), song('s2')], currentId: 's1');

      expect(queueMark(songs: [song('s1')], currentId: 's1'), isNot(base));
      expect(queueMark(songs: [song('s9'), song('s2')], currentId: 's1'), isNot(base));
      expect(queueMark(songs: [song('s1'), song('s9')], currentId: 's1'), isNot(base));
      expect(queueMark(songs: [song('s1'), song('s2')], currentId: 's2'), isNot(base));
    });

    test('空队列也有指纹（占位串）', () {
      expect(queueMark(songs: const [], currentId: null), 'empty');
    });
  });
}
