import 'package:nordic/data/models.dart';
import 'package:nordic/playback/audio_handler.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';

/// 一份「已经放着歌」的播放层。
///
/// 界面靠 `state.song != null` 决定要不要出播放坞 / 播放页,而那个判断走的是
/// just_audio 的 `currentIndex` —— 源码里自己写明了:**测试环境里没有那条平台
/// 通道,`currentIndex` 永远是 null**(见 `playback_controller.dart` 里
/// `tailDurationAfter` 那段注释)。所以 widget 测试里给它一份视图,而不是去给
/// just_audio 打平台桩 —— 要验的是界面,不是播放层。
///
/// 用法与真的一样:`playable.toggle()`、`playable.queue`、`playable.position`
/// 都还是真的,只有「现在在放什么」这一份快照是直接给的。
PlaybackController playingController(
  Song song, {
  bool playing = true,
  QualityOption? loadedQuality,
  bool? loadedLocal,
  QualityController? quality,
}) =>
    _PlayingController(
      song,
      playing,
      loadedQuality: loadedQuality,
      loadedLocal: loadedLocal,
      quality: quality,
    );

/// 一份「什么都还没放」的播放层 —— 坞 / 播放页的空态那一支用它。
///
/// 与 [playingController] 的差别只有一处:那份快照里 `song` 是 null。
IdlePlayback idleController() => IdlePlayback();

class IdlePlayback extends PlaybackController {
  IdlePlayback() : super(NordicAudioHandler(() => null, QualityController()));

  @override
  PlaybackState get state => const PlaybackState();
}

class _PlayingController extends PlaybackController {
  _PlayingController(
    Song song,
    bool playing, {
    QualityController? quality,
    this.loadedQuality,
    this.loadedLocal,
  })  : _view = PlaybackState(
          song: song,
          playing: playing,
          duration: song.duration,
        ),
        super(NordicAudioHandler(() => null, quality ?? QualityController()));

  final PlaybackState _view;

  @override
  PlaybackState get state => _view;

  /// 「这一首装载那一刻用的是哪一份」。真身由 `_emit` 里那次重读填上
  /// (见 `playback_controller.dart`),而这一份替身从不 `_emit` —— 界面要验的
  /// 「本机那份」/「不知道该说哪一份」两种情形,直接在这里给。
  @override
  final QualityOption? loadedQuality;

  @override
  final bool? loadedLocal;
}
/// 记下落点的播放层 —— 「点歌词跳到那一段」「拖进度条」都靠它断言。
///
/// 与 [_PlayingController] 一样是替身,只多两件事:记下每一次 `seek`,
/// 并把位置跟着挪过去(真的播放器就是这么动的;不挪的话高亮不会走,
/// 断言就变成断言假的了)。
RecordingPlayback recordingController(Song song, {bool playing = true}) =>
    RecordingPlayback(song, playing);

class RecordingPlayback extends _PlayingController {
  RecordingPlayback(super.song, super.playing);

  /// 界面上发出的每一次 seek,按顺序记下来。
  final seeks = <Duration>[];

  @override
  Future<void> seek(Duration target) async {
    seeks.add(target);
    position.value = target;
  }
}
