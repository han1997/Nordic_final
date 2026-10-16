import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/network_status.dart';
import 'package:nordic/data/subsonic_auth.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_payload.dart';
import 'package:nordic/data/subsonic_repository.dart';

import 'fake_dio.dart';

/// 下载管理器:排队、门控、续传、失败。
///
/// 传输那一层是注入进来的(见 [TransferFn]),所以这些用例不碰网络 ——
/// 要验的是管理器自己的逻辑,以及「什么算完成、什么算失败」这条判断线。
void main() {
  // 网络探针走平台通道,通道要有绑定才存在 —— 测试里也得先起绑定。
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late DownloadStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nordic-dl-mgr');
    store = await DownloadStore.open(root: root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Song song(String id, {String title = '曲目', int? size}) => Song(
        id: id,
        title: title,
        artist: '艺人',
        album: '专辑',
        albumId: 'al-1',
        suffix: 'flac',
        sizeBytes: size,
      );

  final album = const Album(
    id: 'al-1',
    name: '专辑',
    artist: '艺人',
    artistId: 'ar-1',
    coverArtId: 'cover-1',
  );

  /// 单线路仓库。ping 一律成功 —— 线路相关的行为另有用例。
  SubsonicRepository repo({List<String>? hits}) => SubsonicRepository(
        SubsonicClient(
          auth: SubsonicAuth(username: 'u', password: 'p'),
          routes: const [
            ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.example.com'),
          ],
          dio: recordingDio(
            hits ?? <String>[],
            handler: (_) => {
              'subsonic-response': {'status': 'ok', 'version': '1.16.1'}
            },
          ),
        ),
      );

  /// 假传输:记下每次被请求的地址,把固定内容写进目标文件。
  /// [failWith] 返回非空表示这次调用失败。
  TransferFn transfer(
    List<Uri> calls, {
    String? Function(Uri uri)? failWith,
    bool network = false,
    int size = 2048,
  }) =>
      ({
        required Uri uri,
        required String savePath,
        void Function(int received, int total)? onProgress,
        CancelToken? cancelToken,
      }) async {
        calls.add(uri);
        final failure = failWith?.call(uri);
        if (failure != null) throw DownloadFailure(failure, network: network);

        final bytes = Uint8List(size)..fillRange(0, size, 7);
        await File(savePath).writeAsBytes(bytes, flush: true);
        onProgress?.call(size, size);
        return TransferResult(
          bytes: size,
          contentType: 'audio/flac',
        );
      };

  /// 等到队列里没有还在跑 / 还在排的任务。
  Future<void> settle(DownloadManager manager) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final busy = manager.jobs.any((j) =>
          j.isActive ||
          j.state == DownloadState.queued ||
          j.state.isWaiting);
      if (!busy) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('下载没有在预期时间内收敛:'
        '${manager.jobs.map((j) => '${j.request.name}=${j.state}').join(',')}');
  }

  DownloadManager managerWith({
    TransferFn? fn,
    SubsonicRepository? repository,
    bool wifiOnly = false,
    Dio? dio,
  }) =>
      DownloadManager(
        repository: () => repository ?? repo(),
        store: store,
        wifiOnly: () => wifiOnly,
        probe: NetworkProbe(channel: const MethodChannel(NetworkProbe.channelName)),
        transfer: fn,
        dio: dio,
        checkInterval: const Duration(milliseconds: 20),
      );

  group('下载', () {
    test('曲目真的落到本机,登记后播放层查得到', () async {
      final manager = managerWith(fn: transfer(<Uri>[]));

      final job = await manager.enqueue(
        DownloadRequest.album(album, [song('s1'), song('s2')]),
      );
      await settle(manager);

      expect(job.state, DownloadState.done);
      expect(job.pct, 100);
      final path = store.localPathFor('s1');
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      expect(store.localPathFor('s2'), isNotNull);
      expect(manager.isDownloaded('s1'), isTrue);

      // 索引落了盘:换一个 store 实例读同一块目录,记录还在。
      final reopened = await DownloadStore.open(root: root);
      expect(reopened.records.single.name, '专辑');
      expect(reopened.records.single.format, 'FLAC');
      expect(reopened.localPathFor('s2'), isNotNull);
    });

    test('封面跟着一起下,并且界面按 coverArtId 问得到', () async {
      final manager = managerWith(fn: transfer(<Uri>[]));

      await manager.enqueue(DownloadRequest.album(album, [song('s1')]));
      await settle(manager);

      final cover = manager.coverPathForArt('cover-1');
      expect(cover, isNotNull);
      expect(File(cover!).existsSync(), isTrue);

      // 有了它,仓库给的封面地址就是本机文件 —— 断网也看得见。
      final repo = SubsonicRepository(
        SubsonicClient(
          auth: SubsonicAuth(username: 'u', password: 'p'),
          routes: const [
            ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.example.com'),
          ],
        ),
        localCover: manager.coverPathForArt,
      );
      expect(repo.coverUri('cover-1').scheme, 'file');
      // 没下过的那张照旧走服务器,参数齐全。
      final remote = repo.coverUri('别的封面', size: 128);
      expect(remote.scheme, 'http');
      expect(remote.queryParameters['size'], '128');
    });

    test('下载一律取原文件,不吃转码档', () async {
      final calls = <Uri>[];
      final manager = managerWith(fn: transfer(calls));

      await manager.enqueue(DownloadRequest.song(song('s1')));
      await settle(manager);

      // 带了 maxBitRate / format 就意味着服务器要转码 —— 存下来的是
      // 「下载到本机(FLAC)」这句承诺之外的另一种文件。
      expect(calls.single.queryParameters.containsKey('maxBitRate'), isFalse);
      expect(calls.single.queryParameters.containsKey('format'), isFalse);
    });

    test('服务器没报体积时按曲目数报进度,不假装知道体积', () async {
      late DownloadManager manager;
      String? midLine;
      manager = managerWith(
        fn: ({
          required Uri uri,
          required String savePath,
          void Function(int received, int total)? onProgress,
          CancelToken? cancelToken,
        }) async {
          onProgress?.call(1024, 1024);
          midLine = manager.jobs.single.statusLine;
          await File(savePath).writeAsBytes(Uint8List(2048), flush: true);
          return TransferResult(bytes: 2048, contentType: 'audio/flac');
        },
      );

      final job = await manager.enqueue(
        DownloadRequest.album(album, [song('s1'), song('s2')]),
      );
      await settle(manager);

      // 下载途中:不知道体积就不报体积,改报「几首里的第几首」——
      // 编一个体积出来会比不报更糟(进度条会撒谎)。
      expect(midLine, contains('/2 首'));
      expect(midLine, isNot(contains('MB')));
      // 下完才知道真实体积,而且它来自磁盘上的字节数,不是猜的。
      expect(job.statusLine, contains('已完成'));
      expect(job.statusLine, contains('FLAC'));
      expect(job.record?.bytes, 4096);
    });

    test('服务器报了体积就按体积算进度,而不是按曲目数', () async {
      late DownloadManager manager;
      final marks = <double>[];
      manager = managerWith(
        fn: ({
          required Uri uri,
          required String savePath,
          void Function(int received, int total)? onProgress,
          CancelToken? cancelToken,
        }) async {
          // 第一首(4096 字节)已经收到一半。按体积算应是 40%,
          // 按曲目数摊平只有 25% —— 两者不同才说明进度用的是体积。
          onProgress?.call(2048, 4096);
          marks.add(manager.jobs.single.pct);
          await File(savePath).writeAsBytes(Uint8List(4096), flush: true);
          onProgress?.call(4096, 4096);
          return TransferResult(bytes: 4096, contentType: 'audio/flac');
        },
      );

      final job = await manager.enqueue(DownloadRequest.album(album, [
        song('s1', size: 4096),
        song('s2', size: 1024),
      ]));
      await settle(manager);

      expect(marks.first, closeTo(40, 1));
      expect(job.state, DownloadState.done);
      // 完成后报的是**实际落盘**的量:服务器报的和磁盘上的不一致时,
      // 以磁盘为准,不然进度条永远停不在 100%。
      expect(job.receivedBytes, 8192);
    });

    test('同一条任务不重复入队 —— 按钮点两下不该排出两条', () async {
      final manager = managerWith(fn: transfer(<Uri>[]));

      await manager.enqueue(DownloadRequest.album(album, [song('s1')]));
      await manager.enqueue(DownloadRequest.album(album, [song('s1')]));
      await settle(manager);

      expect(manager.jobs.length, 1);
    });

    test('删掉任务会把文件一起删掉', () async {
      final manager = managerWith(fn: transfer(<Uri>[]));
      await manager.enqueue(DownloadRequest.song(song('s1')));
      await settle(manager);
      final path = store.localPathFor('s1')!;

      await manager.remove('dl-song-s1');

      expect(manager.jobs, isEmpty);
      expect(store.localPathFor('s1'), isNull);
      expect(File(path).existsSync(), isFalse);
      expect(manager.isDownloaded('s1'), isFalse);
    });
  });

  group('失败与重试', () {
    test('失败要落到任务上,带上服务器给的原因', () async {
      final manager = managerWith(
        fn: transfer(<Uri>[], failWith: (_) => '服务器拒绝了这次下载'),
      );

      final job = await manager.enqueue(DownloadRequest.song(song('s1')));
      await settle(manager);

      expect(job.state, DownloadState.failed);
      expect(job.error, contains('服务器拒绝了这次下载'));
      // 曲名要出现 —— 一页里好几条任务,只报「失败了」等于没说。
      expect(job.error, contains('曲目'));
      expect(job.statusLine, contains('失败'));
    });

    test('重试跳过已经下好的曲子,只补没下完的那几首', () async {
      final calls = <Uri>[];
      var broken = 's2';
      final manager = managerWith(
        fn: transfer(
          calls,
          failWith: (uri) =>
              uri.queryParameters['id'] == broken ? '这首下不动' : null,
        ),
      );

      final job = await manager.enqueue(
        DownloadRequest.album(album, [song('s1'), song('s2')]),
      );
      await settle(manager);
      expect(job.state, DownloadState.failed);

      broken = '';
      await manager.retry(job.request.id);
      await settle(manager);

      expect(job.state, DownloadState.done);
      expect(store.localPathFor('s2'), isNotNull);
      // s1 已经在本机了,重试不该再拉一遍。
      final s1Calls =
          calls.where((u) => u.queryParameters['id'] == 's1').length;
      expect(s1Calls, 1);
      expect(calls.where((u) => u.queryParameters['id'] == 's2').length, 2);
    });

    test('线路不通时换一条线再试一次', () async {
      final calls = <Uri>[];
      final hits = <String>[];
      final repository = SubsonicRepository(
        SubsonicClient(
          auth: SubsonicAuth(username: 'u', password: 'p'),
          routes: const [
            ServerRoute(id: 'lan', name: '局域网', url: 'http://lan.example.com'),
            ServerRoute(id: 'wan', name: '外网', url: 'http://wan.example.com'),
          ],
          dio: recordingDio(
            hits,
            handler: (base) {
              // 局域网这条连不上,外网通 —— 与浏览时的故障切换同一套语义。
              if (base.contains('lan.')) throw const SubsonicException('连不上');
              return {
                'subsonic-response': {'status': 'ok', 'version': '1.16.1'}
              };
            },
          ),
        ),
      );

      final manager = managerWith(
        repository: repository,
        fn: transfer(
          calls,
          network: true,
          // 只有局域网那条会失败 —— 换到外网就该成。
          failWith: (uri) =>
              uri.host.startsWith('lan.') ? '连接失败,检查网络或线路' : null,
        ),
      );

      final job = await manager.enqueue(DownloadRequest.song(song('s1')));
      await settle(manager);

      expect(job.state, DownloadState.done);
      expect(calls.length, 2, reason: '第一次失败后应该再试一次');
      expect(calls.first.host, 'lan.example.com');
      // 重试前重新测速,把能用的那条线顶了上来。
      expect(calls.last.host, 'wan.example.com');
      expect(hits, contains('http://lan.example.com'));
    });
  });

  group('仅 Wi-Fi 下载', () {
    /// 换一块「当前网络是什么」的答案。用的就是真探针 ——
    /// 顺带把 Dart 侧那几个字符串到枚举的映射也验了。
    Future<void> givenNetwork(String answer) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(NetworkProbe.channelName),
        (call) async => call.method == 'status' ? answer : null,
      );
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(NetworkProbe.channelName),
        null,
      );
    });

    test('计费网络下不下,条件满足了会自己开始', () async {
      await givenNetwork('metered');
      final calls = <Uri>[];
      final manager = managerWith(fn: transfer(calls), wifiOnly: true);

      final job = await manager.enqueue(DownloadRequest.song(song('s1')));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(job.state, DownloadState.waitingWifi);
      expect(job.statusLine, contains('等待 Wi-Fi'));
      expect(calls, isEmpty, reason: '「流量下不缓存」就得真的不下');

      // 走到 Wi-Fi 底下 —— 不需要用户再点一次。
      await givenNetwork('unmetered');
      await manager.onWifiOnlyChanged();
      await settle(manager);

      expect(job.state, DownloadState.done);
      expect(calls, hasLength(1));
    });

    test('关掉仅 Wi-Fi 后,计费网络下也照下', () async {
      await givenNetwork('metered');
      final calls = <Uri>[];
      final manager = managerWith(fn: transfer(calls));

      final job = await manager.enqueue(DownloadRequest.song(song('s1')));
      await settle(manager);

      expect(job.state, DownloadState.done);
    });

    test('没网时说「等待网络」,不说「等待 Wi-Fi」', () async {
      await givenNetwork('offline');
      final manager = managerWith(fn: transfer(<Uri>[]));

      final job = await manager.enqueue(DownloadRequest.song(song('s1')));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(job.state, DownloadState.waitingNetwork);
      expect(job.statusLine, contains('等待网络'));
    });

    test('问不出网络类型时不拦着 —— 桌面端没有这条通道', () async {
      // 不设 handler:调用会抛 MissingPluginException,探针回 unknown。
      final manager = managerWith(fn: transfer(<Uri>[]));

      final job = await manager.enqueue(DownloadRequest.song(song('s1')));
      await settle(manager);

      expect(job.state, DownloadState.done);
    });
  });

  group('真传输(dio)', () {
    /// 假 Dio:回一个**流式**响应。dio 的 download 要的是 ResponseBody,
    /// 不能像别的用例那样回一个字符串。
    Dio streamingDio({
      required int status,
      required String contentType,
      required List<int> body,
    }) {
      final headers = {'content-type': [contentType]};
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, interceptor) => interceptor.resolve(
          Response<ResponseBody>(
            requestOptions: options,
            statusCode: status,
            headers: Headers.fromMap(headers),
            data: ResponseBody(
              Stream.value(Uint8List.fromList(body)),
              status,
              headers: headers,
            ),
          ),
        ),
      ));
      return dio;
    }

    test('正常响应把字节落到磁盘,不留半截文件', () async {
      final manager = managerWith(
        dio: streamingDio(
          status: 200,
          contentType: 'audio/flac',
          body: List<int>.filled(4096, 3),
        ),
      );

      final job = await manager.enqueue(DownloadRequest.song(song('s1')));
      await settle(manager);

      expect(job.state, DownloadState.done);
      final file = File(store.localPathFor('s1')!);
      expect(await file.length(), 4096);
      // 中间那层 .part 是给自己看的,完成后不该留在用户的目录里。
      expect(File('${file.path}.part').existsSync(), isFalse);
    });

    test('服务器回 200 但内容是错误 JSON —— 判为失败,不当成下好了', () async {
      // Subsonic 出错时 HTTP 状态码是 200,错在响应体里。不当心的话
      // 一个几百字节的 JSON 会被当成音频存下来,「已完成」就是假的。
      final manager = managerWith(
        dio: streamingDio(
          status: 200,
          contentType: 'application/json; charset=utf-8',
          body: utf8.encode(jsonEncode({
            'subsonic-response': {
              'status': 'failed',
              'error': {'code': 70, 'message': 'The requested data was not found'},
            }
          })),
        ),
      );

      final job = await manager.enqueue(DownloadRequest.song(song('s1')));
      await settle(manager);

      expect(job.state, DownloadState.failed);
      expect(job.error, contains('The requested data was not found'));
      expect(store.localPathFor('s1'), isNull, reason: '失败的不该进索引');
    });

    test('HTTP 错误码判为失败', () async {
      final manager = managerWith(
        dio: streamingDio(
          status: 404,
          contentType: 'text/plain',
          body: utf8.encode('not found'),
        ),
      );

      final job = await manager.enqueue(DownloadRequest.song(song('s1')));
      await settle(manager);

      expect(job.state, DownloadState.failed);
      expect(job.error, contains('404'));
    });
  });
}
