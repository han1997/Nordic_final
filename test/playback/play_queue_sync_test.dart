import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/music_source.dart';
import 'package:nordic/playback/play_queue_sync.dart';

/// 队列同步**什么时候写、写什么**。
///
/// 三条判据:
///   - 队列连着变几次(拖动重排会连发好几条通知)**只写一次**;
///   - 写出去的是**截过的那一段**(这是一条 GET 查询串),而 current 在里面;
///   - 暂停那一下**不等防抖**,立刻写(落点就是用户松手的地方)。
void main() {
  /// 只记下「写了几次、写的是哪些 id」的假音源。
  late List<({List<String> ids, String? current, Duration position})> writes;

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

  setUp(() => writes = []);

  test('队列连着变三次，防抖之后只写一次', () async {
    final sync = PlayQueueSync(
      () => _SyncSpy(writes),
      debounce: const Duration(milliseconds: 30),
    );
    final songs = songsOf(3);

    sync.schedule(songs: songs, currentId: 's0', position: Duration.zero);
    sync.schedule(songs: songs, currentId: 's1', position: const Duration(seconds: 5));
    sync.schedule(songs: songs, currentId: 's2', position: const Duration(seconds: 9));
    expect(writes, isEmpty, reason: '还没到点就先写了 —— 拖动重排会连打服务器好几趟');

    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sync.settled;

    expect(writes.length, 1);
    // 写的是**最后一次**那一份状态(前面两次被后一次取代了)。
    expect(writes.single.current, 's2');
    expect(writes.single.position, const Duration(seconds: 9));
    sync.dispose();
  });

  test('暂停那一下立刻写，不等防抖', () async {
    final sync = PlayQueueSync(
      () => _SyncSpy(writes),
      debounce: const Duration(seconds: 30),
    );

    sync.flushNow(
      songs: songsOf(2),
      currentId: 's1',
      position: const Duration(seconds: 42),
    );
    await sync.settled;

    expect(writes.single.position, const Duration(seconds: 42));
    sync.dispose();
  });

  test('长队列只写截过的那一段，current 在里面', () async {
    final sync = PlayQueueSync(
      () => _SyncSpy(writes),
      debounce: Duration.zero,
    );

    sync.schedule(songs: songsOf(3000), currentId: 's1500');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sync.settled;

    expect(writes.single.ids.length, 200);
    expect(writes.single.current, 's1500');
    expect(writes.single.ids.contains('s1500'), isTrue);
    sync.dispose();
  });

  test('心跳按间隔来 —— 间隔没到就不写', () async {
    final sync = PlayQueueSync(
      () => _SyncSpy(writes),
      progressEvery: const Duration(milliseconds: 40),
    );

    sync.progress(songs: songsOf(2), currentId: 's0', position: const Duration(seconds: 10));
    await sync.settled;
    expect(writes.length, 1, reason: '第一次该写（距上次写已经很久了）');

    // 紧接着再来一次:间隔没到,不该写。
    sync.progress(songs: songsOf(2), currentId: 's0', position: const Duration(seconds: 20));
    await sync.settled;
    expect(writes.length, 1);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    sync.progress(songs: songsOf(2), currentId: 's0', position: const Duration(seconds: 30));
    await sync.settled;
    expect(writes.length, 2);
    sync.dispose();
  });

  test('没有仓库时什么都不做', () async {
    final sync = PlayQueueSync(() => null, debounce: Duration.zero);

    sync.schedule(songs: songsOf(2), currentId: 's0');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sync.settled;

    expect(writes, isEmpty);
    sync.dispose();
  });

  test('写失败是静默的 —— 不该抛回播放事件那条路', () async {
    final sync = PlayQueueSync(
      () => _SyncSpy(writes, fail: true),
      debounce: Duration.zero,
    );

    sync.schedule(songs: songsOf(2), currentId: 's0');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // 没抛出去就是过 —— 这里只是把那一趟走完。
    await sync.settled;

    expect(writes.length, 1);
    sync.dispose();
  });

  test('写成功之后把指纹交回去（供界面判断「这是我们自己写的」)', () async {
    final marks = <String>[];
    final sync = PlayQueueSync(
      () => _SyncSpy(writes),
      onSaved: marks.add,
      debounce: Duration.zero,
    );

    sync.schedule(songs: songsOf(3), currentId: 's1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sync.settled;

    expect(marks.length, 1);
    expect(marks.single, '3:s0:s2:s1');
    sync.dispose();
  });
}

/// 只记 savePlayQueue 的假音源。
class _SyncSpy implements MusicSource {
  _SyncSpy(this.writes, {this.fail = false});

  final List<({List<String> ids, String? current, Duration position})> writes;
  final bool fail;

  @override
  Future<void> savePlayQueue({
    required List<Song> songs,
    String? currentId,
    Duration position = Duration.zero,
  }) async {
    writes.add((
      ids: [for (final s in songs) s.id],
      current: currentId,
      position: position,
    ));
    if (fail) throw const MusicSourceException('服务器不可达');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}