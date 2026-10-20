import 'dart:async';

import '../data/models.dart';
import '../data/music_source.dart';
import '../data/play_queue.dart';

/// 把队列与进度写回服务器(Subsonic 的 `savePlayQueue`)。
///
/// 用途只有一个:**换设备接着听**。写在三种时刻:
///
///   - **队列变 / 切歌** → 防抖 1.5 秒写一次。拖动重排会连发好几条队列通知,
///     每条都写就是白打服务器好几趟。
///   - **播放中每 30 秒** → 补一次进度(用户听到一半直接锁屏时,落点才准)。
///   - **暂停** → 立刻写(那一瞬间的位置就是用户松手的地方)。
///
/// 失败**一律静默**:与 scrobble 同一条口径 —— 这是后台动作。
/// 代价是断网期间那一份队列没同步过去(`savePlayQueue` 没有补报一说:
/// 队列是**状态**,过期的状态补上去反而是错的)。
class PlayQueueSync {
  PlayQueueSync(
    this._repo, {
    void Function(String mark)? onSaved,
    Duration debounce = const Duration(milliseconds: 1500),
    Duration progressEvery = const Duration(seconds: 30),
  }) {
    // 体里赋值而不是初始化列表:这三个字段都是私有的,而命名参数不能以下划线
    // 开头 —— 初始化列表那条写法会撞上 `prefer_initializing_formals`,
    // 而它建议的 `this._x` 在这里是非法的。
    _onSaved = onSaved;
    _debounce = debounce;
    _progressEvery = progressEvery;
  }

  final MusicSource? Function() _repo;

  /// 保存成功之后把这一次的指纹交回去(由调用方落盘,见 [queueMark])。
  late final void Function(String mark)? _onSaved;

  late final Duration _debounce;
  late final Duration _progressEvery;

  Timer? _timer;
  DateTime _lastWriteAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _chain = Future<void>.value();

  /// 队列 / 切歌都走它。
  void schedule({
    required List<Song> songs,
    String? currentId,
    Duration position = Duration.zero,
  }) {
    if (songs.isEmpty) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      _write(songs: songs, currentId: currentId, position: position);
    });
  }

  /// 播放中的心跳:距上一次写超过 [_progressEvery] 就补一次进度。
  void progress({
    required List<Song> songs,
    String? currentId,
    required Duration position,
  }) {
    if (songs.isEmpty) return;
    if (DateTime.now().difference(_lastWriteAt) < _progressEvery) return;
    _timer?.cancel();
    _write(songs: songs, currentId: currentId, position: position);
  }

  /// 暂停 / 停止的那一刻:别等防抖,立刻写一次。
  void flushNow({
    required List<Song> songs,
    String? currentId,
    required Duration position,
  }) {
    if (songs.isEmpty) return;
    _timer?.cancel();
    _write(songs: songs, currentId: currentId, position: position);
  }

  /// 排在前面的那几趟写完没有 —— 测试用它。
  Future<void> get settled => _chain;

  void dispose() {
    _timer?.cancel();
  }

  void _write({
    required List<Song> songs,
    required String? currentId,
    required Duration position,
  }) {
    final repo = _repo();
    if (repo == null) return;
    final window = queueWindow(songs, currentId);
    final mark = queueMark(songs: window.songs, currentId: window.currentId);
    _lastWriteAt = DateTime.now();
    // 串起来:防抖那一趟与暂停那一趟可能前后脚到,并发写同一份状态没有意义。
    _chain = _chain.then((_) async {
      try {
        await repo.savePlayQueue(
          songs: window.songs,
          currentId: window.currentId,
          position: position,
        );
        _onSaved?.call(mark);
      } catch (_) {
        // 静默 —— 见类注释。
      }
    });
  }
}