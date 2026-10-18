import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/subsonic_auth.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_repository.dart';

import 'fake_dio.dart';

/// 播放地址的**备忘录**。
///
/// 一次 `setQueue` 会把整条队列的播放源都拼出来(见 `audio_handler.dart` 的
/// `_sourceFor`),上千首的队列就是上千次「新生成盐 + MD5」,而其中绝大多数地址
/// 到播完也不会被请求一次;同一张专辑底下的几十首歌更是共用同一个封面地址。
/// 记一份之后这些哈希只算一次。
///
/// 钉两件最容易记错的事:
///   - 输入没变时必须给出**同一条** URL(否则备忘录等于没有);
///   - 线路的地址变了必须给**新的**(只按线路 id 作键的话,「改了地址还走旧的」)。
void main() {
  const lan = ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.example.com');

  SubsonicClient clientWith(List<ServerRoute> routes) => SubsonicClient(
        auth: SubsonicAuth(username: 'u', password: 'p'),
        routes: routes,
        dio: recordingDio(
          <String>[],
          handler: (_) => {
            'subsonic-response': {'status': 'ok', 'version': '1.16.1'}
          },
        ),
      );

  test('同一张封面问两次，给的是同一条地址', () {
    final repo = SubsonicRepository(clientWith(const [lan]));

    // 没有备忘录的话这两条 URL 的 `s`(盐)不一样 —— 同一次会话里为同一张图
    // 算两遍哈希,一点好处都没有。
    expect(repo.coverUri('cover-1', size: 256),
        repo.coverUri('cover-1', size: 256));
  });

  test('尺寸不同就是两条地址 —— 备忘录不能把参数吞掉', () {
    final repo = SubsonicRepository(clientWith(const [lan]));

    final small = repo.coverUri('cover-1', size: 128);
    final big = repo.coverUri('cover-1', size: 512);

    expect(small, isNot(big));
    expect(small.queryParameters['size'], '128');
    expect(big.queryParameters['size'], '512');
  });

  test('同一首歌同一个档位，给的是同一条流地址', () {
    final repo = SubsonicRepository(clientWith(const [lan]));

    expect(repo.streamUri('s1', maxBitRate: 320, format: 'mp3'),
        repo.streamUri('s1', maxBitRate: 320, format: 'mp3'));
    // 换了档位就是另一条 —— 那是另一份音频。
    expect(repo.streamUri('s1', maxBitRate: 320, format: 'mp3'),
        isNot(repo.streamUri('s1')));
  });

  test('线路的地址改了，地址跟着换 —— 不能把旧主机一直喂回去', () {
    final client = clientWith(const [lan]);
    final repo = SubsonicRepository(client);
    expect(repo.streamUri('s1').host, 'lan.example.com');
    expect(repo.coverUri('cover-1').host, 'lan.example.com');

    // 用户在「添加线路」那一屏把地址改掉了 —— 线路 id 没变。
    client.setRoutes(const [
      ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com'),
    ]);

    expect(repo.streamUri('s1').host, 'nas.example.com');
    expect(repo.coverUri('cover-1').host, 'nas.example.com');
  });

  test('本机下过的封面直接给本机文件，而且不记进备忘录', () {
    // 下载状态是会变的(刚下好的那张封面,下一次问就该有了),
    // 所以本机那一支必须每次现问。
    var local = <String, String>{};
    final repo = SubsonicRepository(
      clientWith(const [lan]),
      localCover: (id) => local[id],
    );

    expect(repo.coverUri('cover-1').scheme, 'http');
    local = {'cover-1': '/sdcard/Nordic/Music/dl-album-1/cover.jpg'};
    expect(repo.coverUri('cover-1').scheme, 'file');
  });
}