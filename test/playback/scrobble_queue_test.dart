import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/music_source.dart';
import 'package:nordic/data/scrobble_store.dart';
import 'package:nordic/playback/scrobble.dart';

/// 「离线听的那些也算数」—— 发不出去的「听过一次」排起来,下次有机会补报。
///
/// 上一版是直接丢掉的(「失败一律静默」),于是断网那一趟在服务器的「最近播放」
/// 里完全不存在。这里钉四件:
///
///   1. 发不出去 → 进队列(**带上那时的时间**);
///   2. 下次要发新的一条之前,先把积压的按时间顺序补掉;
///   3. **「正在播放」永不入队**(它说的是「此刻」,补报没有意义);
///   4. 队列有上限,满了丢最老的。
void main() {
  late Directory root;
  late ScrobbleStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nordic-scrobbles');
    store = await ScrobbleStore.open(root: root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// 记下每一条请求(含时间),可以按需失败。
  late List<({String id, bool submission, DateTime? at})> sent;
  late _Source source;

  setUp(() {
    sent = [];
    source = _Source(sent);
  });

  /// 一首两分钟的歌听到一半 —— 刚好越过报「听过」的门槛。
  void listened(PlaybackReporter r, String id) => r.position(
        id,
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 2),
      );

  test('离线时报不出去 → 进队列，带着那时的时间', () async {
    final at = DateTime(2026, 10, 19, 21, 30);
    final r = PlaybackReporter(
      () => _Source(sent, fail: true),
      store: store,
      now: () => at,
    );

    listened(r, 's1');
    await r.settled;

    final pending = await store.load();
    expect(pending.length, 1);
    expect(pending.single.songId, 's1');
    // **是听的那一刻**,不是「什么时候补报的」—— 补报时给服务器的是它。
    expect(pending.single.at, at);
  });

  test('下次联网：先把积压的补掉（带原来的时间），再报当前这条', () async {
    // 离线那一趟单独记:假音源是**先记再抛**的,两趟混在一个列表里会看到
    // 同一个 id 报两次(一次失败、一次补报成功)。
    final offlineSent = <({String id, bool submission, DateTime? at})>[];
    final offlineAt = DateTime(2026, 10, 19, 21, 30);
    final offline = PlaybackReporter(
      () => _Source(offlineSent, fail: true),
      store: store,
      now: () => offlineAt,
    );
    listened(offline, 's1');
    await offline.settled;
    expect(await store.load(), hasLength(1));

    final onlineAt = DateTime(2026, 10, 19, 22, 0);
    final online = PlaybackReporter(() => source, store: store, now: () => onlineAt);
    listened(online, 's2');
    await online.settled;

    expect(sent.map((e) => e.id), ['s1', 's2']);
    expect(sent.first.at, offlineAt, reason: '补报要带**当时**的时间，不然「最近播放」全挤在一起');
    expect(sent.last.at, onlineAt);
    // 补出去的从队列里删掉。
    expect(await store.load(), isEmpty);
  });

  test('「正在播放」失败时不入队 —— 它说的是此刻，补报没有意义', () async {
    final r = PlaybackReporter(() => _Source(sent, fail: true), store: store);

    r.nowPlaying('s1');
    await r.settled;

    expect(await store.load(), isEmpty);
  });

  test('队列上限：超出丢最老的', () async {
    // 250 条(上限 200)—— 那个上限是「临时发不出去」的边界,不是账本。
    await store.replaceAll([
      for (var i = 0; i < 250; i++)
        PendingScrobble(
          songId: 's$i',
          at: DateTime(2026, 10, 19).add(Duration(minutes: i)),
        ),
    ]);

    final pending = await store.load();
    expect(pending.length, ScrobbleStore.limit);
    expect(pending.first.songId, 's50', reason: '丢的是最老的那几条');
    expect(pending.last.songId, 's249');
  });

  test('坏文件当空 —— 读不到待补的记录不该影响听歌', () async {
    final file = File('${root.path}${Platform.pathSeparator}pending_scrobbles.json');
    await file.writeAsString('{ 这不是 JSON');

    expect(await store.load(), isEmpty);
  });

  test('补报成功之后队列清空，不会重复补第二遍', () async {
    final offlineSent = <({String id, bool submission, DateTime? at})>[];
    final r = PlaybackReporter(
      () => _Source(offlineSent, fail: true),
      store: store,
      now: () => DateTime(2026, 10, 19, 21, 30),
    );
    listened(r, 's1');
    await r.settled;

    final online = PlaybackReporter(() => source, store: store);
    listened(online, 's2');
    await online.settled;
    // 再听一首:这一趟该只剩它自己,不该把 s1 再补一遍。
    listened(online, 's3');
    await online.settled;

    expect(sent.map((e) => e.id).toList(), ['s1', 's2', 's3']);
    expect(await store.load(), isEmpty);
  });
}

/// 只记 reportPlayback 的假音源;`fail` 为真时永远抛。
class _Source implements MusicSource {
  _Source(this.sent, {this.fail = false});

  final List<({String id, bool submission, DateTime? at})> sent;
  final bool fail;

  @override
  Future<void> reportPlayback(
    String songId, {
    required bool submission,
    DateTime? at,
  }) async {
    sent.add((id: songId, submission: submission, at: at));
    if (fail) throw const MusicSourceException('服务器不可达');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 让分析器知道 [Song] 在这个文件里不是必需的(只做类型占位)。
// ignore: unused_element
