import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/models.dart';
import 'audio_handler.dart';
import 'quality.dart';

/// 界面看到的播放状态。
///
/// 把 `just_audio` 的几个流合成一份不可变快照,界面订阅一个对象即可,
/// 不必自己拼 StreamBuilder 的嵌套。
@immutable
class PlaybackState {
  const PlaybackState({
    this.song,
    this.playing = false,
    this.processing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.hasNext = false,
    this.hasPrevious = false,
    this.shuffle = false,
    this.repeatOne = false,
    this.error,
  });

  final Song? song;
  final bool playing;

  /// 正在缓冲 / 加载。界面据此显示转圈而不是「已暂停」。
  final bool processing;

  final Duration position;
  final Duration duration;
  final bool hasNext;
  final bool hasPrevious;
  final bool shuffle;
  final bool repeatOne;

  /// 播放失败的原因。非空时界面要显示错误而不是空态。
  final String? error;

  /// 进度百分比(0–100)。时长未知时返回 0 —— 不要拿 0 去画进度条,
  /// 那会看起来像「播到了开头」;界面应结合 [duration] 判断。
  double get progress {
    if (duration.inMilliseconds <= 0) return 0;
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    return (ratio.clamp(0.0, 1.0)) * 100;
  }

  PlaybackState copyWith({
    Song? song,
    bool? playing,
    bool? processing,
    Duration? position,
    Duration? duration,
    bool? hasNext,
    bool? hasPrevious,
    bool? shuffle,
    bool? repeatOne,
    String? error,
    bool clearError = false,
  }) =>
      PlaybackState(
        song: song ?? this.song,
        playing: playing ?? this.playing,
        processing: processing ?? this.processing,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        hasNext: hasNext ?? this.hasNext,
        hasPrevious: hasPrevious ?? this.hasPrevious,
        shuffle: shuffle ?? this.shuffle,
        repeatOne: repeatOne ?? this.repeatOne,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 界面与播放器之间的那层。
///
/// [NordicAudioHandler] 面向系统(通知栏 / 锁屏),这个类面向界面:
/// 把它的状态收拢成一个可监听对象,并暴露界面要用的命令。
class PlaybackController extends ChangeNotifier {
  PlaybackController(this._handler) {
    _wire();
  }

  final NordicAudioHandler _handler;

  final List<StreamSubscription<dynamic>> _subs = [];
  final List<StreamSubscription<dynamic>> _positionSubs = [];

  PlaybackState _state = const PlaybackState();
  PlaybackState get state => _state;

  NordicAudioHandler get handler => _handler;

  List<Song> get queue => _handler.songs;

  QualityOption get quality => _handler.quality;

  void _wire() {
    final player = _handler.player;

    // 位置单独走一条订阅 —— 它每秒发很多次,每次都全量重建
    // 会让整个播放页跟着重绘。
    _track(_positionSubs, player.positionStream.listen((position) {
      _emit(_state.copyWith(position: position));
    }));

    _track(_subs, player.playerStateStream.listen((ps) {
      _emit(_state.copyWith(
        song: _handler.currentSong ?? _state.song,
        playing: ps.playing,
        processing: ps.processingState == ProcessingState.loading ||
            ps.processingState == ProcessingState.buffering,
        hasNext: player.hasNext,
        hasPrevious: player.hasPrevious,
        shuffle: player.shuffleModeEnabled,
        repeatOne: player.loopMode == LoopMode.one,
        // 播放器重新跑起来就说明上一次错误过去了。
        clearError: ps.processingState != ProcessingState.idle,
      ));
    }));

    // 时长单独一条:切歌时 [PlayerState] 上的值会短暂为空,
    // 用它更新会让进度条先跳到 0 再回来。
    _track(_subs, player.durationStream.listen((duration) {
      if (duration != null) _emit(_state.copyWith(duration: duration));
    }));

    // 队列变化(追加 / 移除 / 重排)也要让界面刷新。
    _track(_subs, _handler.queue.stream.listen((_) {
      _emit(_state.copyWith(
        song: _handler.currentSong ?? _state.song,
        hasNext: player.hasNext,
        hasPrevious: player.hasPrevious,
      ));
    }));
  }

  /// 统一挂错误处理 —— 播放流的错误不该把界面拖崩,记进状态即可。
  void _track(List<StreamSubscription<dynamic>> bucket, StreamSubscription<dynamic> sub) {
    bucket.add(sub);
    sub.onError((Object e) {
      _emit(_state.copyWith(error: '$e', playing: false));
    });
  }

  void _emit(PlaybackState next) {
    _state = next;
    notifyListeners();
  }

  // ---------------- 命令 ----------------

  /// 用整个列表替换队列并从 [index] 开播。
  Future<void> playAll(List<Song> songs, {int index = 0}) async {
    try {
      await _handler.setQueue(songs, index: index);
      _emit(_state.copyWith(error: null, clearError: true));
    } catch (e) {
      _emit(_state.copyWith(error: '$e', playing: false));
    }
  }

  /// 播一首单曲 —— 队列就是它自己。
  Future<void> playSong(Song song) => playAll([song]);

  Future<void> toggle() =>
      _state.playing ? _handler.pause() : _handler.play();

  Future<void> next() => _handler.skipToNext();

  Future<void> previous() => _handler.skipToPrevious();

  Future<void> seek(Duration position) => _handler.seek(position);

  Future<void> jumpTo(int index) => _handler.jumpTo(index);

  Future<void> append(Song song) => _handler.append(song);

  Future<void> playNext(Song song) => _handler.insertNext(song);

  Future<void> removeAt(int index) => _handler.removeAt(index);

  Future<void> reorder(int oldIndex, int newIndex) =>
      _handler.reorder(oldIndex, newIndex);

  Future<void> toggleShuffle() => _handler.setShuffleMode(
        _state.shuffle
            ? AudioServiceShuffleMode.none
            : AudioServiceShuffleMode.all,
      );

  Future<void> toggleRepeat() => _handler.setRepeatMode(
        _state.repeatOne
            ? AudioServiceRepeatMode.none
            : AudioServiceRepeatMode.one,
      );

  /// 切转码档位。会以新档位重新加载当前曲目,位置尽量保住。
  Future<void> setQuality(QualityOption option) async {
    await _handler.applyQuality(option);
    _emit(_state.copyWith(error: null, clearError: true));
  }

  /// 队列里全部曲目的总时长 —— 队列面板的标题要用。
  Duration get queueDuration =>
      queue.fold(Duration.zero, (sum, s) => sum + s.duration);

  /// 当前曲目之后还剩多久。队列面板的「还有约 …」。
  Duration get remaining {
    final index = _handler.player.currentIndex;
    if (index == null || index < 0) return Duration.zero;
    final after = queue.skip(index + 1).fold(Duration.zero, (s, x) => s + x.duration);
    final currentLeft = _state.duration - _state.position;
    return after + (currentLeft.isNegative ? Duration.zero : currentLeft);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    for (final sub in _positionSubs) {
      sub.cancel();
    }
    super.dispose();
  }
}