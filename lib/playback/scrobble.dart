import 'dart:async';

import '../data/music_source.dart';
import '../data/scrobble_store.dart';

/// 播放状态回报的**判据** —— 纯逻辑,不碰网络、不碰播放器。
///
/// 抽出来是因为它有三条边界条件(同一首各只报一次、够一半才算听过、时长未知
/// 就不猜),而那三条正是最容易写错的地方;接在播放层里靠集成测试碰它们太贵。
///
/// 口径与 Subsonic / Navidrome 的客户端一致:
///
///   - **正在播放**(`submission=false`):切到某一首在放的那一刻报一次。
///     队列重排、换档重装、切线路都会再走一遍「拼播放源」,但**同一个 id 只报一次**。
///   - **听过一次**(`submission=true`):位置越过 `min(时长的一半, 4 分钟)` 报一次。
///     「一半」是防止快进到结尾那一秒也算数,4 分钟是给长曲子封顶
///     (一首 20 分钟的现场,不听完两遍才记一次)。
///   - **时长未知(0)时一条都不报**:判不出「一半」,就别猜 —— 报了就是假数据。
class ScrobbleTracker {
  ScrobbleTracker({Duration? cap}) : cap = cap ?? const Duration(minutes: 4);

  /// 「听过」那条的封顶时长。默认 4 分钟。
  final Duration cap;

  String? _nowPlayingFor;
  String? _submittedFor;

  /// 切到某一首在放:要不要报「正在播放」。
  ///
  /// **键是曲目 id**:换歌天然重置(下一首的 id 不一样),而重排 / 重装
  /// 同一首不会重复报。
  bool noteNowPlaying(String songId) {
    if (_nowPlayingFor == songId) return false;
    _nowPlayingFor = songId;
    return true;
  }

  /// 位置走到了 [position](总时长 [duration]):要不要报「听过一次」。
  bool notePosition(
    String songId, {
    required Duration position,
    required Duration duration,
  }) {
    if (_submittedFor == songId) return false;
    // 时长未知就别判 —— 见上面那条。
    if (duration <= Duration.zero) return false;
    final half = duration ~/ 2;
    final threshold = half < cap ? half : cap;
    if (position < threshold) return false;
    _submittedFor = songId;
    return true;
  }

  /// 清空(播放层被重建 / 队列被换掉时用得上)。
  void reset() {
    _nowPlayingFor = null;
    _submittedFor = null;
  }
}

/// 把 [ScrobbleTracker] 的判据落成真请求,并把**发不出去的**那几笔排起来。
///
/// **一律静默**:这是后台动作,失败弹一条错误没有意义(离线、服务器不可达、
/// 对面不认这个端点都会失败)。
///
/// 但「静默」不等于「丢掉」—— 上一版就是丢掉的,于是**断开网络听的这一趟在
/// 服务器统计里完全不存在**,而「最近播放」正是用户会去对照的东西。
/// 现在「听过一次」发不出去时进 [ScrobbleStore],下一次有机会(下一条 scrobble
/// 或下一次启动)连着 `time` 一起补报。
///
/// **「正在播放」永不入队**:它说的是「此刻」,而此刻已经过去了 ——
/// 补报一条过期的「正在播放」只会让服务器显示错误的东西。
///
/// 一条说清楚的边界:请求**超时但服务器其实收到了**的话,补报会让它计两次
/// (Subsonic 没有幂等键)。宁可偶尔多一次,也别整趟丢掉。
class PlaybackReporter {
  PlaybackReporter(
    this._repo, {
    ScrobbleTracker? tracker,
    ScrobbleStore? store,
    DateTime Function()? now,
  })  : _tracker = tracker ?? ScrobbleTracker(),
        _now = now ?? DateTime.now {
    // 在体里赋值而不是初始化列表:`_store` 是私有字段,而命名参数不能以下划线
    // 开头 —— 初始化列表那条写法会撞上 `prefer_initializing_formals`,
    // 而它建议的 `this._store` 在这里是非法的。
    _store = store;
  }

  final MusicSource? Function() _repo;
  final ScrobbleTracker _tracker;

  /// 待补队列的落盘处。null = 不落盘(测试 / 存储建不出来),那时行为退回
  /// 「发不出去就算了」—— 与上一版一样,只是不会更坏。
  late final ScrobbleStore? _store;

  final DateTime Function() _now;

  /// 待补的那几笔,按时间从早到晚。第一次用到时从盘上读一次。
  List<PendingScrobble>? _pending;

  /// 串起来做:几条 scrobble 可能前后脚到(换歌 + 位置),而补报与去重都要讲顺序。
  Future<void> _chain = Future<void>.value();

  /// 把这一串后台动作串成一件事。测试要等它落地才能断言。
  Future<void> get settled => _chain;

  /// 切到某一首在放。
  void nowPlaying(String songId) {
    if (!_tracker.noteNowPlaying(songId)) return;
    _enqueue(() async {
      // 「正在播放」**不入队**:它说的是此刻,补报没有意义。
      await _trySend(songId, submission: false);
      // 顺手把积压的补掉 —— 「正在播放」也是个机会。
      await _flush();
    });
  }

  /// 位置报到了 [position]。
  void position(
    String songId, {
    required Duration position,
    required Duration duration,
  }) {
    if (!_tracker.notePosition(
      songId,
      position: position,
      duration: duration,
    )) {
      return;
    }
    final at = _now();
    _enqueue(() async {
      await _flush();
      if (!await _trySend(songId, submission: true, at: at)) {
        _pendingItems.add(PendingScrobble(songId: songId, at: at));
        await _persist();
      }
    });
  }

  void _enqueue(Future<void> Function() work) {
    _chain = _chain.then((_) => work()).catchError((_) {});
  }

  /// 发一条。**成功返回 true,失败(含没有仓库)返回 false** —— 不抛。
  Future<bool> _trySend(
    String songId, {
    required bool submission,
    DateTime? at,
  }) async {
    final repo = _repo();
    if (repo == null) return false;
    try {
      await repo.reportPlayback(songId, submission: submission, at: at);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 把积压的补报掉,**从最早的开始**。
  ///
  /// 第一条发不出去就停(网络不通,后面几条也别白试一遍);成功的逐条落盘。
  Future<void> _flush() async {
    await _ensureLoaded();
    final pending = _pendingItems;
    if (pending.isEmpty || _repo() == null) return;

    var sent = 0;
    for (final item in pending) {
      if (!await _trySend(item.songId, submission: true, at: item.at)) break;
      sent++;
    }
    if (sent == 0) return;
    pending.removeRange(0, sent);
    await _persist();
  }

  List<PendingScrobble> get _pendingItems => _pending ??= <PendingScrobble>[];

  Future<void> _ensureLoaded() async {
    if (_pending != null) return;
    _pending = List<PendingScrobble>.of(await _store?.load() ?? const []);
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null) return;
    await store.replaceAll(_pendingItems);
  }
}