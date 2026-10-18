import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/models.dart';
import '../data/server_config.dart';
import 'audio_handler.dart';
import 'quality.dart';

/// 循环模式。
///
/// **这是本层自己的枚举** —— just_audio / audio_service 的类型不该漏进界面。
/// (名字带 `Playback` 前缀是因为 Flutter 3.44 的 `material.dart` 也导出了一个
/// `RepeatMode`(`repeating_animation_builder.dart`),裸名在界面层会撞。)
///
/// 原型只有两态(原型里「循环」就是单曲循环,图标始终是那个双箭头圈)。
/// 三态是真机上要求做宽的一处,刻意偏离原型:顺序播放 → 列表循环 → 单曲循环。
enum PlaybackRepeat {
  /// 顺序播放:队列走到头就停。
  off,

  /// 列表循环:队列走到头接着从第一首来。
  all,

  /// 单曲循环:一首放完原地重来。
  one,
}

/// 循环键点一下的下一态。抽成顶层纯函数是为了能直接测。
PlaybackRepeat nextRepeatMode(PlaybackRepeat current) => switch (current) {
      PlaybackRepeat.off => PlaybackRepeat.all,
      PlaybackRepeat.all => PlaybackRepeat.one,
      PlaybackRepeat.one => PlaybackRepeat.off,
    };

/// 盘上的名字 → 枚举。认不出来的(手改过 / 以后删过档)当**顺序播放** ——
/// 与 `QualityOption.byId` 同一条兜底口径:一个坏值不该把启动搞崩。
PlaybackRepeat repeatModeByName(String? name) => switch (name) {
      'all' => PlaybackRepeat.all,
      'one' => PlaybackRepeat.one,
      _ => PlaybackRepeat.off,
    };

/// 界面态 → `audio_service` 的重复模式。反方向在 `audio_handler.dart` 的
/// [loopModeFor] 那头,两处都是顶层纯函数,能直接测。
AudioServiceRepeatMode audioServiceRepeatModeFor(PlaybackRepeat mode) =>
    switch (mode) {
      PlaybackRepeat.off => AudioServiceRepeatMode.none,
      PlaybackRepeat.all => AudioServiceRepeatMode.all,
      PlaybackRepeat.one => AudioServiceRepeatMode.one,
    };

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
    this.repeat = PlaybackRepeat.off,
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
  final PlaybackRepeat repeat;

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
    PlaybackRepeat? repeat,
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
        repeat: repeat ?? this.repeat,
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
/// 队列里第 [index] 首**之后**的总时长(不含这一首本身,也不含它已经播掉的
/// 那一部分)。
///
/// 提成顶层函数是为了能直接测:它是 [PlaybackController.remaining] 里那段
/// 缓存值的唯一来源,而控制器要一个真的播放器才建得起来 —— 测试环境里没有
/// 那条平台通道,`currentIndex` 永远是 null。
Duration tailDurationAfter(List<Song> queue, int index) {
  if (index < 0 || index >= queue.length) return Duration.zero;
  return queue
      .skip(index + 1)
      .fold(Duration.zero, (sum, s) => sum + s.duration);
}

class PlaybackController extends ChangeNotifier {
  PlaybackController(this._handler, {this.config}) {
    _wire();
    _restoreModes();
  }

  final NordicAudioHandler _handler;

  /// 循环 / 随机的落盘处。**没传就是「不记忆」** —— 测试与假播放层照旧,
  /// 不该为一个偏好白白多出一次 prefs 访问。
  final ConfigStore? config;

  final List<StreamSubscription<dynamic>> _subs = [];

  /// 播放位置 —— **单独一条通道,不进 [state] 的通知**。
  ///
  /// 位置每秒变好几次,而 [state] 一变,所有盯着它的界面都要重建:
  /// 音乐库的货架、专辑页二十来行曲目、坞……切页面时正撞上这件事,就是顿挫。
  /// 真正要显示位置的只有三处(播放页的进度条、坞底那条细线、歌词页),
  /// 它们各自订阅这一条就够了。
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  /// 已缓冲到哪儿 —— 与 [position] **同一套待遇**:单独一条通道,不进 [state]。
  ///
  /// 它与位置同源(just_audio 的 `playbackEventStream`),远端流上一首歌缓冲的
  /// 过程中几乎每次事件都会动一下。本机 / 已下完的那一份到手之后这个值就稳住了,
  /// 于是**不会**再触发重建。
  ///
  /// 换歌时由 [_wire] 里那条下标流归零 —— 否则上一首留下的缓冲带会在新歌上闪一帧。
  final ValueNotifier<Duration> buffered = ValueNotifier(Duration.zero);

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

    // 缓冲位置走**同一套**:一条自己的通道。`ValueNotifier` 自带相等判断,
    // 值没动就不播报 —— 本机文件整首到手之后这条流等于静止。
    _track(_subs, player.bufferedPositionStream.listen((next) {
      buffered.value = next;
    }));

    _track(_subs, player.playerStateStream.listen((ps) {
      final song = _handler.currentSong ?? _state.song;
      // 换了一首就把元数据里的时长先铺上:转码流的响应没有 Content-Length,
      // 平台报不出时长(ExoPlayer 给 TIME_UNSET),而进度条拿不到时长会**结构性**
      // 卡在 0 —— 滑块最左、还禁用拖动。平台一旦报出真值,durationStream 那条会覆盖。
      // 顺带修掉「换歌后残留上一首时长」。
      final trackChanged = song?.id != _state.song?.id;
      _emit(_state.copyWith(
        song: song,
        duration: trackChanged ? (song?.duration ?? Duration.zero) : null,
        playing: ps.playing,
        processing: ps.processingState == ProcessingState.loading ||
            ps.processingState == ProcessingState.buffering,
        hasNext: player.hasNext,
        hasPrevious: player.hasPrevious,
        shuffle: player.shuffleModeEnabled,
        // 播放器重新跑起来就说明上一次错误过去了。
        clearError: ps.processingState != ProcessingState.idle,
      ));
    }));

    // 曲目下标 —— 切歌(自动接下一首 / 手动跳)真正发生的信号。
    // `playerStateStream` 只对 (playing, processingState) 去重,同一组合下切歌
    // 不会再发事件,界面于是停在上一首(坞、通知栏、播放页)。下标变一律重发。
    _track(_subs, player.currentIndexStream.listen((_) {
      final song = _handler.currentSong ?? _state.song;
      final trackChanged = song?.id != _state.song?.id;
      // 换歌先把缓冲归零:否则上一首缓冲到哪儿会以新歌的时长画一遍,
      // 屏幕上闪出一条不属于这一首的缓冲带(下一批事件就把它纠正过来,
      // 但那一帧是看得见的)。
      if (trackChanged) buffered.value = Duration.zero;
      _emit(_state.copyWith(
        song: song,
        duration: trackChanged ? (song?.duration ?? Duration.zero) : null,
        hasNext: _handler.player.hasNext,
        hasPrevious: _handler.player.hasPrevious,
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

    // 循环模式**同样单独一条**,理由一模一样:`setLoopMode` 也只改序列状态、
    // 不发 playerEvent,而 `playerStateStream` 被 `.distinct()` 压在
    // (playing, processingState) 上 —— 从它派生出来的循环态于是永远停在旧值。
    // 症状:灯不亮;而且 `cycleRepeat` 读这个假值,于是**开了关不掉**。
    _track(_subs, player.loopModeStream.listen((mode) {
      final next = switch (mode) {
        LoopMode.off => PlaybackRepeat.off,
        LoopMode.all => PlaybackRepeat.all,
        LoopMode.one => PlaybackRepeat.one,
      };
      if (next == _state.repeat) return;
      _emit(_state.copyWith(repeat: next));
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

  /// 冷启动把上次的循环 / 随机摆回**播放器**。
  ///
  /// 此刻队列还是空的,但这两个都是**播放器级**开关(不是队列级)——
  /// `setQueue` 从不碰它们,摆上去之后第一次装载队列就照着生效。
  /// 默认值(顺序播放 / 不随机)不调:省一次平台往返,也省一次没人要的通知栏播报。
  void _restoreModes() {
    final repeat = repeatModeByName(config?.loadRepeatModeName());
    if (repeat != PlaybackRepeat.off) {
      unawaited(_handler.setRepeatMode(audioServiceRepeatModeFor(repeat)));
    }
    if (config?.loadShuffle() ?? false) {
      unawaited(_handler.setShuffleMode(AudioServiceShuffleMode.all));
    }
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

  /// 随机开关。**记进盘里**:下次冷启动要还是它。
  ///
  /// 落盘的是**意图值**(`!state.shuffle`)而不是回读:回读要等一个微任务,
  /// 连点两下会把上一态记进盘。平台那一头成功了才写 —— 抛异常时不留脏值。
  Future<void> toggleShuffle() async {
    final enabled = !_state.shuffle;
    await _handler.setShuffleMode(
      enabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
    await config?.saveShuffle(enabled);
  }

  /// 循环键点一下:**顺序播放 → 列表循环 → 单曲循环 → 顺序播放**。
  ///
  /// 落成哪一态由界面从 [state] 上读(图标 + 选中底色),这里不返回值 ——
  /// 早先返回过,是为了让界面弹一句文案说「刚才那下生效了」,那句已移除。
  /// 同样记进盘里(存的是枚举的**名字**)。
  Future<void> cycleRepeat() async {
    final next = nextRepeatMode(_state.repeat);
    await _handler.setRepeatMode(audioServiceRepeatModeFor(next));
    await config?.saveRepeatModeName(next.name);
  }

  /// 切转码档位。会以新档位重新加载当前曲目,位置尽量保住。
  Future<void> setQuality(QualityOption option) async {
    await _handler.applyQuality(option);
    _emit(_state.copyWith(error: null, clearError: true));
  }

  /// 线路换了 —— 正在放的这一首用新线路重新加载,位置尽量保住。
  ///
  /// 由**换线路的那一处**调用(线路面板 / 服务器页锁定与增删线路)。不在这里
  /// 监听服务器配置:播放层与状态层互不认识,硬连起来只会多一条隐式依赖。
  Future<void> retargetRoute() async {
    await _handler.retargetCurrentRoute();
    _emit(_state.copyWith(error: null, clearError: true));
  }

  /// 队列里全部曲目的总时长 —— 队列面板的标题要用。
  Duration get queueDuration =>
      queue.fold(Duration.zero, (sum, s) => sum + s.duration);

  /// 当前曲目之后还剩多久。队列面板的「还有约 …」。
  Duration get remaining {
    final index = _handler.player.currentIndex;
    if (index == null || index < 0) return Duration.zero;
    final list = queue;
    final currentId = index < list.length ? list[index].id : null;
    if (_tailIndex != index ||
        _tailLength != list.length ||
        _tailId != currentId) {
      // 先落到局部变量再存 —— 直接赋给 `Duration?` 字段的话,类型推断会
      // 把 `fold` 的累加器也推成可空,`s + x.duration` 就编译不过了。
      final after = tailDurationAfter(list, index);
      _tail = after;
      _tailIndex = index;
      _tailLength = list.length;
      _tailId = currentId;
    }
    final currentLeft = _state.duration - position.value;
    return _tail! + (currentLeft.isNegative ? Duration.zero : currentLeft);
  }

  /// [remaining] 的缓存。
  ///
  /// 尾部那段时长只跟「当前第几首、队列多长、那一首是谁」有关,与播放位置无关,
  /// 而队列面板每次 build 都会来问一次 —— 长队列上那就是白 fold 几百项。
  /// 位置那部分(一行减法)照旧实时算,所以结果与逐项相加完全一致。
  Duration? _tail;
  int? _tailIndex;
  int? _tailLength;
  String? _tailId;

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    position.dispose();
    buffered.dispose();
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
