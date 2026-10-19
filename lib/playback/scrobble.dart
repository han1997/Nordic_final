import 'dart:async';

import '../data/music_source.dart';

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

/// 把 [ScrobbleTracker] 的判据落成真请求。
///
/// **一律静默**:这是后台动作,失败弹一条错误没有意义(离线、服务器不可达、
/// 对面不认这个端点都会失败)。代价是离线听的那些不计入服务器统计 ——
/// 与「本机不另存一份播放记录」是同一件事的两面:这条记录的去处只有服务器。
class PlaybackReporter {
  PlaybackReporter(this._repo, {ScrobbleTracker? tracker})
      : _tracker = tracker ?? ScrobbleTracker();

  final MusicSource? Function() _repo;
  final ScrobbleTracker _tracker;

  /// 有没有一个能说话的仓库 —— 没有就什么都不做(还没连服务器)。
  bool get _canReport => _repo() != null;

  /// 切到某一首在放。
  void nowPlaying(String songId) {
    if (!_tracker.noteNowPlaying(songId)) return;
    _send(songId, submission: false);
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
    _send(songId, submission: true);
  }

  void _send(String songId, {required bool submission}) {
    if (!_canReport) return;
    // **不 await**:回报是后台动作,不该让播放事件、位置流等它一个网络往返。
    unawaited(_repo()!.reportPlayback(songId, submission: submission).catchError(
          // 静默失败 —— `catchError` 要有返回值,而这里是 `Future<void>`。
          (_) {},
        ));
  }
}