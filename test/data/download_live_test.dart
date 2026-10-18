import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_repository.dart';

import 'live_server.dart';

/// 真下载 —— 拿真服务器上的一首歌走完「拉流 → 落盘 → 登记」全程。
///
/// 前面那些下载用例用的是假传输(验的是排队 / 门控 / 续传这些逻辑),
/// 这一条验的是**协议那一半**:鉴权参数、流地址、Content-Type,
/// 以及文件头是不是真的音频。这些在假 Dio 上永远测不出偏差。
///
/// **凭据从环境变量读**(见 `live_server.dart`):仓库是公开的,密码不能跟着代码走。
/// 没配环境变量时退回一个够不着的地址,整组照旧跳过,不让离线开发平白失败。
final _serverUrl = liveServerUrl;
final _username = liveServerUser;
final _password = liveServerPassword;

void main() {
  late SubsonicRepository repo;

  setUp(() {
    repo = SubsonicRepository(clientFor(
      config: ServerConfig(
        id: 's1',
        name: '客厅 Navidrome',
        kind: ServerKind.navidrome,
        username: _username,
        routes: [ServerRoute(id: 'lan', name: '局域网直连', url: _serverUrl)],
      ),
      password: _password,
    ));
  });

  Future<bool> reachable() async {
    try {
      final ping = await repo.client.pingRoute(
        ServerRoute(id: 'lan', name: '局域网直连', url: _serverUrl),
      );
      return ping.isOk;
    } catch (_) {
      return false;
    }
  }

  Future<void> settle(DownloadManager manager) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final busy = manager.jobs.any((j) =>
          j.isActive ||
          j.state == DownloadState.queued ||
          j.state.isWaiting);
      if (!busy) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('下载没在预期时间内完成：${manager.jobs.first.state}'
        '${manager.jobs.first.error ?? ''}');
  }

  test('下载一首真歌：音频字节真的落盘，索引记得住', () async {
    if (!await reachable()) {
      markTestSkipped('Navidrome 不可达，跳过');
      return;
    }

    // 挑一首**小**的。这组用例是给开发随手跑的,不该顺手拉几十 MB 的无损。
    final songs = await repo.allSongs(size: 200);
    final small = songs
        .where((s) => (s.sizeBytes ?? 1 << 30) < 2 * 1024 * 1024)
        .toList();
    if (small.isEmpty) {
      markTestSkipped('库里前 200 首没有小于 2 MB 的曲目，跳过');
      return;
    }
    final song = small.first;

    final root = await Directory.systemTemp.createTemp('nordic-dl-live');
    addTearDown(() => root.delete(recursive: true));

    final store = await DownloadStore.open(root: root);
    final manager = DownloadManager(
      repository: () => repo,
      store: store,
      wifiOnly: () => false,
    );

    final job = await manager.enqueue(DownloadRequest.song(song));
    await settle(manager);

    expect(job.state, DownloadState.done, reason: job.error ?? '没给出原因');

    final path = store.localPathFor(song.id);
    expect(path, isNotNull, reason: '下完了就该登记进索引');
    final file = File(path!);
    expect(file.existsSync(), isTrue);
    expect(await file.length(), greaterThan(1024));

    // 文件头得像音频。服务器回错误体(HTTP 200 + JSON)的话,
    // 落盘的会是一个几百字节的 JSON —— 那正是最该被挡住的情况。
    final head = await file.openRead(0, 12).first;
    final fourCC = String.fromCharCodes(head.take(4));
    // 常见容器:`fLaC` / `RIFF`(wav)/ `OggS` / `ftyp`(m4a);
    // mp3 则带 `ID3` 标签,或者直接以帧同步字 0xFF 开头。
    final looksLikeAudio =
        const ['fLaC', 'RIFF', 'OggS', 'ftyp'].contains(fourCC) ||
            fourCC.startsWith('ID3') ||
            head[0] == 0xFF;
    expect(looksLikeAudio, isTrue, reason: '文件头应该像音频，实际=$fourCC');

    // 重开一次索引:重启之后这份下载还在,播放层还能查到它。
    final reopened = await DownloadStore.open(root: root);
    expect(reopened.localPathFor(song.id), path);
    expect(reopened.records.single.files.length, 1);

    // 收尾:删掉这条应当把文件一起带走 —— 真机上用户按「删掉」就是这个动作。
    await manager.remove(DownloadRequest.song(song).id);
    expect(file.existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
