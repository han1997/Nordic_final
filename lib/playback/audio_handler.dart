import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../data/models.dart';
import '../data/subsonic_repository.dart';
import 'quality.dart';

/// 启动后台播放服务并返回它的处理器。
///
/// 必须用 [AudioService.init] 而不是直接 new —— 它在平台侧注册
/// 媒体会话与前台服务,通知栏控件就靠这个建立。`androidNotificationChannel*`
/// 决定通知的渠道与优先级:`lowImportance` 让媒体通知不出横幅、不发声,
/// 这是播放器的惯例(正在放歌时再弹一条横幅很吵)。
Future<NordicAudioHandler> startAudioService({
  required SubsonicRepository repository,
  required QualityController quality,
}) =>
    AudioService.init(
      builder: () => NordicAudioHandler(repository, quality),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'fun.han1997.nordic.playback',
        androidNotificationChannelName: '播放控制',
        androidNotificationChannelDescription: '通知栏与锁屏上的播放控制',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        // 播放页与通知栏的返回行为交给应用自己处理。
        androidNotificationClickStartsActivity: true,
      ),
    );

/// 后台播放服务。
///
/// 用 [AudioHandler] 而不是裸 `just_audio`,是为了拿到通知栏 / 锁屏 /
/// 耳机按键那一层 —— 原型设置页里「播放时后台运行:通知栏与锁屏可控制」
/// 说的就是这件事。
///
/// 职责:持有 [AudioPlayer]、维护队列、把域模型 [Song] 翻成 [MediaItem]
/// 供系统 UI 显示、把转码档位落成流地址参数。**不碰界面** ——
/// 界面通过 [PlaybackController] 订阅它。
class NordicAudioHandler extends BaseAudioHandler with SeekHandler {
  // 位置参数 + 私有字段的初始化形参:命名参数不能是私有的,
  // 而这两个字段不该暴露出去(界面一律经 PlaybackController 说话)。
  NordicAudioHandler(this._repository, this._quality) {

    _player = AudioPlayer();

    // 队列播完(走到最后一首的结尾)就停下,并把系统 UI 的状态
    // 从「播放中」改掉 —— 否则通知栏会一直挂着播放按钮。
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.completed,
          playing: false,
        ));
      }
    });

    // 播放器状态 → 系统 UI。
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        // 播放出错也播报出去,免得界面上的按钮停在「正在播放」。
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
        ));
      },
    );
  }

  final SubsonicRepository _repository;
  final QualityController _quality;

  late final AudioPlayer _player;

  /// 当前队列对应的域模型。`just_audio` 的队列里只有 URL,
  /// 界面要显示标题与封面,所以另存一份。
  List<Song> _queue = const [];

  /// 当前在播的那首歌。队列空时返回 null。
  Song? get currentSong {
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= _queue.length) return null;
    return _queue[index];
  }

  /// 播放位置与时长。单独两条流给界面用 —— 位置每秒变很多次,
  /// 混进 [playbackState] 会让通知栏跟着频繁重建。
  Stream<Duration> get positionStream => _player.positionStream;

  Stream<Duration?> get durationStream => _player.durationStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// 音频会话状态(耳机拔出、被其他应用打断等)。界面可选订阅。
  Stream<AudioProcessingState> get processingStateStream =>
      playbackState.map((s) => s.processingState);

  /// 当前转码档位(与设置页、播放页共享同一个真值)。
  QualityOption get quality => _quality.value;

  /// 裸露的播放器。界面要直接订阅位置 / 时长流([PlaybackController] 之外的
  /// 少见场景),这里给出口子而不是把 `just_audio` 的类型漏到界面层。
  AudioPlayer get player => _player;

  /// 当前队列(域模型)。注意与 [AudioHandler.queue] 区分 ——
  /// 后者是给系统 UI 看的 [MediaItem] 列表,这个是界面要显示的歌曲信息。
  List<Song> get songs => List.unmodifiable(_queue);

  /// 配置音频会话。不做这一步,Android 不会为播放建立媒体会话,
  /// 通知栏也就不会出现可控的媒体控件。
  Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  /// 换一整个队列并从 [index] 开始放。
  ///
  /// 整批交给 just_audio 装载(而不是逐首 setUrl),它才能预加载下一首,
  /// 切歌没有空档。
  Future<void> setQueue(List<Song> songs, {int index = 0}) async {
    if (songs.isEmpty) return;
    _queue = List.of(songs);

    final start = index.clamp(0, songs.length - 1);
    final items = songs.map(_mediaItemFor).toList();
    mediaItem.add(items[start]);
    queue.add(items);

    await _player.setAudioSources(
      songs.map(_sourceFor).toList(),
      initialIndex: start,
      initialPosition: Duration.zero,
    );
    await play();
  }

  /// 追加到队列末尾。
  Future<void> append(Song song) async {
    if (_queue.isEmpty) return setQueue([song]);
    _queue = [..._queue, song];
    await _player.addAudioSource(_sourceFor(song));
    queue.add([...queue.value, _mediaItemFor(song)]);
  }

  /// 「下一首播放」:插到当前曲目之后。
  Future<void> insertNext(Song song) async {
    if (_queue.isEmpty) return setQueue([song]);
    final at = ((_player.currentIndex ?? 0) + 1).clamp(0, _queue.length);
    _queue = [..._queue]..insert(at, song);
    await _player.insertAudioSource(at, _sourceFor(song));
    queue.add([...queue.value]..insert(at, _mediaItemFor(song)));
  }

  /// 跳转到队列中的第 [index] 首并开始播放。
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queue.length) return;
    if (index < queue.value.length) mediaItem.add(queue.value[index]);
    await _player.seek(Duration.zero, index: index);
    await play();
  }

  /// 移除队列中的某一首。**正在播放的那首不给移** —— 移掉它播放器会停,
  /// 用户会以为「点一下把歌停了」。要换掉它请用 [jumpTo]。
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    if (index == _player.currentIndex) return;

    _queue = [..._queue]..removeAt(index);
    await _player.removeAudioSourceAt(index);
    queue.add([...queue.value]..removeAt(index));
  }

  /// 重排队列。拖动排序后调用 —— 位置要保住,不能让正在听的歌跳回开头。
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _queue.length) return;

    final playingSong = currentSong;
    final position = _player.position;
    final wasPlaying = _player.playing;

    // ReorderableListView 给的 newIndex 是「插入到该位置之前」的口径,
    // 往下拖时要减一,否则会差一位。
    final target = (newIndex > oldIndex ? newIndex - 1 : newIndex)
        .clamp(0, _queue.length - 1);
    final next = [..._queue];
    final moved = next.removeAt(oldIndex);
    next.insert(target, moved);
    _queue = next;

    await _player.setAudioSources(
      _queue.map(_sourceFor).toList(),
      initialIndex: 0,
      initialPosition: position,
    );
    queue.add(_queue.map(_mediaItemFor).toList());

    final resumeAt = playingSong == null
        ? 0
        : _queue.indexWhere((s) => s.id == playingSong.id);
    await _player.seek(position, index: resumeAt < 0 ? 0 : resumeAt);
    if (wasPlaying) await play();
  }

  /// 切换转码档位。当前这首会以新档位重新加载;**位置尽量保住** ——
  /// 用户切档时多半正听着,从头开始会很难受。
  Future<void> applyQuality(QualityOption option) async {
    final index = _player.currentIndex;
    if (index == null || index >= _queue.length) {
      // 队列空也要把选择记下来,下次播放按新档走。
      _quality.set(option);
      return;
    }

    final position = _player.position;
    final wasPlaying = _player.playing;

    _quality.set(option);
    await _player.setAudioSources(
      _queue.map(_sourceFor).toList(),
      initialIndex: index,
      initialPosition: position,
    );
    if (wasPlaying) await play();
  }

  // ---------------- AudioHandler 接口 ----------------

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) => jumpTo(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) {
    // 原型的「循环」是单曲循环(图标是一个圈),不是列表循环。
    _player.setLoopMode(
      repeatMode == AudioServiceRepeatMode.none ? LoopMode.off : LoopMode.one,
    );
    return super.setRepeatMode(repeatMode);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) {
    _player.setShuffleModeEnabled(shuffleMode == AudioServiceShuffleMode.all);
    return super.setShuffleMode(shuffleMode);
  }

  @override
  Future<void> onTaskRemoved() async {
    // 从最近任务里划掉应用就停掉播放,并把队列释放掉。
    await stop();
    _queue = const [];
    queue.add(const <MediaItem>[]);
    await super.onTaskRemoved();
  }

  // ---------------- 内部 ----------------

  /// 域模型 → 播放源。转码档位在这里落成查询参数。
  AudioSource _sourceFor(Song song) => AudioSource.uri(
        _repository.streamUri(
          song.id,
          maxBitRate: _quality.value.maxBitRate,
          format: _quality.value.format,
        ),
        tag: _mediaItemFor(song),
      );

  /// 封面一律用专辑封面:Subsonic 里单曲通常没有独立的图。
  MediaItem _mediaItemFor(Song song) => MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
        artUri: song.hasCover
            ? _repository.coverUri(song.coverArtId!, size: 512)
            : null,
      );

  /// 把播放器状态翻成 [playbackState] 供系统 UI 使用。
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }
}