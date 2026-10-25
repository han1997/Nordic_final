// 这条用例守的是 third_party/just_audio 里那处 **Nordic 补丁**(见
// third_party/README.md 与 docs/CHANGELOG.md 第三十四轮)。
//
// `LockCachingAudioSource` 边播边把流写进 `<缓存文件>.part`,下完再改名成
// 正式的那一份。上游 0.10.6 里那个写句柄从来没关过(原注释:TODO: Should
// close sink after done, but it throws an error)—— 在 Android / iOS / Linux 上
// 「对打开着的文件改名」是合法的,所以这个 TODO 一直没被发现;Windows 上是
// ERROR_SHARING_VIOLATION(errno 32),于是**每一首**放完都抛
// PathAccessException,`.part` 永远变不成正式文件。
//
// 所以这里验的不是「有没有抛异常」,而是**那一份完不完整、能不能直接用**:
// 下载收尾之后正式文件必须在、字节逐字相同、`.part` 没了,再要一次时读的是
// 本机这一份而不是重新下一遍。在 Windows 上跑这条才验得到东西(POSIX 上改
// 名本来就不受句柄影响);升级 third_party 时忘了重放补丁,它会红。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  final body = List<int>.generate(64 * 1024, (i) => i % 251);

  late Directory dir;
  late File cacheFile;
  late HttpServer server;
  late int hits;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nordic_lock_cache_');
    cacheFile = File('${dir.path}${Platform.pathSeparator}track.mp3');
    hits = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      hits++;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.contentLength = body.length;
      request.response.add(body);
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // 补丁没了的时候句柄还开着,连临时目录都删不掉 —— 那是这条用例
      // 本来就要报的那一件事,别让清理动作把断言的话盖过去。
    }
  });

  test('下完之后 .part 变成正式文件，且那一份是完整的', () async {
    // 标着 experimental,但应用真的在用它(见 audio_handler 里那处说明)。
    // ignore: experimental_member_use
    final source = LockCachingAudioSource(
      Uri.parse('http://127.0.0.1:${server.port}/track.mp3'),
      cacheFile: cacheFile,
    );

    // 播放器此时读的就是这条流:拉一遍到结尾。
    final response = await source.request();
    await response.stream.drain<void>();

    // 收尾(flush / close / rename)排在下载那条流结束之后,与上面的消费
    // 不同步 —— 这里等「正式文件出现」,而不是假设它已经在了。
    await _waitUntil(() => cacheFile.existsSync());

    final part = File('${cacheFile.path}.part');
    expect(
      cacheFile.existsSync(),
      isTrue,
      reason: '半截的那一份没能改名：写句柄还开着（Windows 上是 errno 32）',
    );
    expect(part.existsSync(), isFalse, reason: '.part 应当已经变成了正式文件');
    expect(await cacheFile.readAsBytes(), body);

    // 「缓存生效」真正的判据:再要一次读的是本机这一份,不再问服务器。
    final again = await source.request();
    await again.stream.drain<void>();
    expect(hits, 1, reason: '第二次不该再打服务器');
    expect(await source.resolve(), isNot(same(source)));
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
