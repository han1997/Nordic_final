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

  final Duration duration;
  final bool hasNext;
  final bool hasPrevious;
  final bool shuffle;
  final bool repeatOne;

  /// 播放失败的原因。非空时界面要显示错误而不是空态。
  final String? error;

  PlaybackState copyWith({
    Song? song,
    bool? playing,
    bool? processing,
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
        duration: duration ?? this.duration,
        hasNext: hasNext ?? this.hasNext,
        hasPrevious: hasPrevious ?? this.hasPrevious,
        shuffle: shuffle ?? this.shuffle,
        repeatOne: repeatOne ?? this.repeatOne,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 进度百分比(0–100)。时长未知时返回 0 —— 不要拿 0 去画进度条,
/// 那会看起来像「播到了开头」;界面应结合时长判断。
double playbackProgress(Duration position, Duration duration) {
  if (duration.inMilliseconds <= 0) return 0;
  final ratio = position.inMilliseconds / duration.inMilliseconds;
  return ratio.clamp(0.0, 1.0) * 100;
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

  /// 播放位置 —— **单独一条通道,不进 [state] 的通知**。
  ///
  /// 位置每秒变好几次,而 [state] 一变,所有盯着它的界面都要重建:
  /// 音乐库的货架、专辑页二十来行曲目、坞……切页面时正撞上这件事,就是顿挫。
  /// 真正要显示位置的只有三处(播放页的进度条、坞底那条细线、歌词页),
  /// 它们各自订阅这一条就够了。
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  PlaybackState _state = const PlaybackState();
  PlaybackState get state => _state;

  NordicAudioHandler get handler => _handler;

  List<Song> get queue => _handler.songs;

  /// 队列的**实际播放顺序**:第 n 位播的是原始队列里的哪一项。
  ///
  /// `queue` 是装载时的原始顺序;随机开着时它和真正会播的顺序不是一回事 ——
  /// 队列面板照 [queue] 铺,用户看到的「下一首」就是假的。界面要照这条映射来列,
  /// 点行 / 移除仍用映射出来的**原始下标**。
  List<int> get queueOrder {
    final indices = _handler.player.effectiveIndices;
    // 长度对不上(队列刚变、播放器还没跟上)就按原顺序 ——
    // 宁可显示得平淡,也别显示错位。
    if (indices.length != queue.length) {
      return List.generate(queue.length, (i) => i);
    }
    return List.of(indices);
  }

  QualityOption get quality => _handler.quality;

  void _wire() {
    final player = _handler.player;

    // 位置单独走一条订阅,而且**只更新那条通道**(见 [position] 的说明)。
    _track(_subs, player.positionStream.listen((next) {
      position.value = next;
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

    // 随机开关**单独一条**。just_audio 的 `setShuffleModeEnabled` 只改序列状态、
    // 不发 playerEvent,而 `playerStateStream` 又被 `.distinct()` 压在
    // (playing, processingState) 上 —— 于是从它派生出来的 shuffle 永远是 false:
    // 随机键不亮,而且 `toggleShuffle` 读这个假值,于是**开了就关不掉**。
    _track(_subs, player.shuffleModeEnabledStream.listen((enabled) {
      if (enabled == _state.shuffle) return;
      _emit(_state.copyWith(shuffle: enabled));
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

  /// 暂停。与 [toggle] 分开:退到后台时的暂停不该依赖界面上的状态判断。
  Future<void> pause() => _handler.pause();

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
    final currentLeft = _state.duration - position.value;
    return after + (currentLeft.isNegative ? Duration.zero : currentLeft);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    position.dispose();
    super.dispose();
  }
}

/// 应用退到后台时的处置:**开关关了就暂停,开着一律不动**。
///
/// 抽成顶层的纯函数是为了能直接单测 —— 这一句就是设置页
/// 「播放时后台运行」在代码里的全部含义。
///
/// 返回是否真的暂停了,调用方一般不用管,测试要用。
Future<bool> pauseWhenBackgrounded({
  required bool backgroundPlay,
  required Future<void> Function() pause,
}) async {
  if (backgroundPlay) return false;
  await pause();
  return true;
}
