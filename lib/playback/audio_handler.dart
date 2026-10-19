import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/download_store.dart';
import '../data/media_cache.dart';
import '../data/models.dart';
import '../data/music_source.dart';
import '../data/network_status.dart';
import 'quality.dart';

/// 一首歌该从哪里播 —— 本机有下载就用本机,否则走服务器的流。
///
/// 抽成顶层的纯函数是为了能直接单测:「有下载就走本地」是**离线能不能播**
/// 的全部逻辑,它不该藏在播放器对象里靠集成测试碰。
///
/// [remote] 只在需要网络时才会被调用 —— 离线且没有本机文件时,连地址都拼不出来
/// (没有服务器),这里的短路正好避免了那种情况下的抛错。
///
/// 三个来源有**先后**:下载 > 缓存 > 网络。
/// 下载那份永远优先:它是用户点名要的原文件,而缓存那份可能是转码档的音频
/// (缓存的键里带着档位,见 [MediaCache])。
/// [pathExists] 是**存在性判据**,缺省是真身 [File.existsSync]。
/// 传进来的那个只该把它换成一层备忘录(见 `MediaCache.existsAt`)——
/// 一次整队拼源要在几千个路径上问一遍「在不在」,而那是**同步**盘操作;
/// 判据本身(在才算数)不变,坏文件 / 被删掉的文件照旧回退网络。
({Uri uri, bool local}) playbackOriginFor(
  Song song, {
  required Uri Function() remote,
  String? localPath,
  String? cachedPath,
  bool Function(String path)? pathExists,
}) {
  bool exists(String path) =>
      pathExists != null ? pathExists(path) : File(path).existsSync();

  if (localPath != null && exists(localPath)) {
    return (uri: Uri.file(localPath), local: true);
  }
  // 缓存其次:**听过的**那一首。它也是本机文件,于是顺带离线可听 ——
  // 不需要网络地址,离线时也就不会走到下面那句 remote()。
  if (cachedPath != null && exists(cachedPath)) {
    return (uri: Uri.file(cachedPath), local: true);
  }
  return (uri: remote(), local: false);
}

/// 这一趟要不要往磁盘上写**新的**缓存。
///
/// 判据是设置页那个「仅 Wi-Fi 下载」开关 —— 它右边那句就是「流量下不缓存」,
/// 而留缓存同样在花流量:一整首歌会在后台被拉完,用户以为省了却并没有。
/// 开关关着时永远允许。
///
/// 抽成顶层纯函数是为了能直接单测:这一条判错的代价是**用户的钱**
/// (以为没在流量上下东西,其实下了)。[NetworkStatus.metered] 之外一律放行,
/// 包括「问不出来」—— 门控是为了省流量,不是为了在问不出来的地方锁死功能
/// (同 [NetworkStatus] 里那条约定)。
bool shouldWriteCache({required bool wifiOnly, required NetworkStatus status}) =>
    !wifiOnly || status != NetworkStatus.metered;

/// 平台是不是「自己把这一首倒回开头」了 —— 那是它**该切下一首**的地方。
///
/// 真机实测(2026-10-17):多首队列里放一首**还没转码过**的曲子(源是
/// `Accept-Ranges: none` + chunked 的冷流,**没有长度**),一首放完时平台没有切
/// 下一首,而是把这一首从 0 秒又放了一遍;同一首换成**本机文件**再放,末尾就
/// 老老实实停住了。Dart 侧全程既没收到 `completed` 也没收到暂停 —— 平台那一支
/// 在无长度的源上不成立。所以这一条护栏自己盯位置。
///
/// 判据缺一不可(每条都对应一种**不该管**的情况):
/// - `previous - next >= threshold`:往回跳得够多才算(正常插值抖动不算);
/// - `previous >= floor`:跳之前确实在曲子中后段(在开头附近来回不算);
/// - `!seekRequested`:是我们自己请求的 seek(拖进度条 / 点歌词 / 换线路重载)
///   —— 用户想回到开头就让他回去;
/// - `!indexChanged`:换歌本来就会把位置归零;
/// - `!loopsOne`:单曲循环本来就该回到开头。
///
/// 两条门槛**按曲长收**(见 [_capByTrackLength]):写死 10 秒 / 5 秒的话,十秒
/// 以内的曲子(间奏、试听片段)重放时位置根本够不着门槛 —— 护栏在最需要它的
/// 那一类曲子上等于不存在,结果是一直单曲循环下去。曲长本来就有(元数据,
/// 装载时已经拿它当 `declared`),没有理由不拿它当尺子。
///
/// 抽成顶层纯函数是为了能直接测:这几条判据只要漏一条,就会在正常的拖动 / 切歌 /
/// 单曲循环上误切下一首,而那比原来的 bug 更烦人。
bool didPlatformRewind({
  required Duration previous,
  required Duration next,
  required Duration trackDuration,
  required bool seekRequested,
  required bool loopsOne,
  required bool indexChanged,
  Duration fallbackFloor = const Duration(seconds: 10),
  Duration fallbackThreshold = const Duration(seconds: 5),
}) {
  if (seekRequested || loopsOne || indexChanged) return false;
  final floor = _capByTrackLength(trackDuration, 2, fallbackFloor);
  final threshold = _capByTrackLength(trackDuration, 4, fallbackThreshold);
  if (previous < floor) return false;
  return previous - next >= threshold;
}

/// 按曲长把一条绝对值门槛收小:[part] 是分母(半首、四分之一首),[cap] 是上限。
/// 长曲子仍是老的那一档,短曲子跟着曲长一起变小;曲长未知就原样给 [cap]。
Duration _capByTrackLength(Duration trackDuration, int part, Duration cap) {
  if (trackDuration <= Duration.zero) return cap;
  final scaled = Duration(microseconds: trackDuration.inMicroseconds ~/ part);
  return scaled < cap ? scaled : cap;
}

/// `audio_service` 的重复模式 → `just_audio` 的循环模式。
///
/// 三态是照搬的(顺序播放 / 列表循环 / 单曲循环),只有 `group` 例外 ——
/// 那是 Android 的「分组循环」,`just_audio` 与 audio_service 都还没实现
/// (见 audio_service 里那条注释),落到这里按顺序播放处理,不要假装支持。
///
/// 抽成顶层纯函数是为了能直接单测:这一次的 bug 里有一半就是
/// 「除 none 外全映射成 one」的三元把列表循环整个吞掉了。
LoopMode loopModeFor(AudioServiceRepeatMode repeatMode) => switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.all => LoopMode.all,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.group => LoopMode.off,
    };

/// 启动后台播放服务并返回它的处理器。
///
/// 必须用 [AudioService.init] 而不是直接 new —— 它在平台侧注册
/// 媒体会话与前台服务,通知栏控件就靠这个建立。`androidNotificationChannel*`
/// 决定通知的渠道与优先级:`lowImportance` 让媒体通知不出横幅、不发声,
/// 这是播放器的惯例(正在放歌时再弹一条横幅很吵)。
///
/// [repository] 是一个**取值函数**而不是实例:服务器配置可以在运行时变
/// (用户改地址、换账号),处理器必须每次都拿到最新的那一个,
/// 否则改完配置还得重启应用才能播。
///
/// [downloads] 同理给的是下载内容的索引 —— 播放时先问它这首歌在不在本地。
///
/// [cache] 是「听过的歌留一份」的缓存(见 `data/media_cache.dart`):
/// 走网络的那一首会边听边落盘,下一次直接读本机。给了它,播放层还会顺手
/// 按用户设的上限淘汰。为 null / 关掉时一切照旧走网络。
Future<NordicAudioHandler> startAudioService({
  required MusicSource? Function() repository,
  required QualityController quality,
  DownloadStore? downloads,
  MediaCache? cache,
  bool Function()? wifiOnly,
}) =>
    AudioService.init(
      builder: () => NordicAudioHandler(
        repository,
        quality,
        downloads: downloads,
        cache: cache,
        wifiOnly: wifiOnly,
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'fun.han1997.nordic.playback',
        androidNotificationChannelName: '播放控制',
        androidNotificationChannelDescription: '通知栏与锁屏上的播放控制',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
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
  NordicAudioHandler(
    this._repository,
    this._quality, {
    this._downloads,
    this._cache,
    bool Function()? wifiOnly,
    NetworkProbe? probe,
    AudioPlayer? player,
  })  : _wifiOnly = wifiOnly ?? (() => false),
        _probe = probe ?? NetworkProbe() {

    // 播放器可以从外面递进来 —— 位置监察那条护栏(见 [didPlatformRewind])是冷流上
    // **唯一在切歌的那一支**,不接一个可摆布的播放器就测不到它,只能测那个纯函数。
    _player = player ?? AudioPlayer();

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

    // 平台放完一首后**自己倒回开头**的护栏 —— 见 [didPlatformRewind]。
    //
    // 真机实测(2026-10-17,多首队列 + 一首**没转码过**的曲子):一首放完时,
    // 平台没有切下一首,而是把**这一首**从 0 秒又放了一遍。Dart 侧既没看到
    // `completed`、也没看到暂停 —— 「正常那一支」(切下一首)压根没走到。
    // 同一首曲子换成**本机文件**再放,末尾就老老实实停住了 —— 差别在源上:
    // 冷转码流的响应是 `Accept-Ranges: none` + chunked(**没有长度**),而本机文件
    // 有长度。
    //
    // 平台**为什么**这么干只是推测(时长未知时那条末尾恢复分支?媒体期重新预备?),
    // 证据只到「它把这一首原地重放了」这一步,别在注释和文档里升级成定论。
    // 要紧的是后果:冷流上**没有第二支在切歌**,这条护栏就是那一支 ——
    // 所以它的判据每一条都要站得住(见 [didPlatformRewind],以及 `playback_test`
    // 里「平台倒回开头」与「位置监察」两组测试)。
    //
    // 于是这里自己盯位置:位置**没来由地往回跳一大截**(同一首、也不是我们自己
    // 请求的 seek)就说明它又回到开头了 —— 直接切下一首。
    _player.positionStream.listen((position) {
      final index = _player.currentIndex;
      if (index == null) return;
      final rewind = didPlatformRewind(
        previous: _watchedPosition,
        next: position,
        trackDuration: _durationAt(index),
        seekRequested: DateTime.now().isBefore(_seekGraceUntil),
        loopsOne: _player.loopMode == LoopMode.one,
        indexChanged: _watchedIndex != index,
      );
      // 暂停期间**两个基线都不动**:平台要是趁暂停把这一首倒回开头(耳机 / 焦点
      // 丢失本来就会让我们暂停),提前把基线改掉就等于把这一跳抹掉了 ——
      // 用户一按播放,还是同一首从 0 开始,原来的 bug 换个场景原样复发,而这里
      // 看不见。留到恢复播放后再判。
      // (`_watchedIndex` 也一样不动:暂停期间换过歌、基线跟着走了的话,
      //  恢复播放时会读出「位置跳了但下标没变」的假阳性,反而多切一首。)
      if (!_player.playing) return;
      _watchedPosition = position;
      _watchedIndex = index;
      if (!rewind) return;
      unawaited(_advancePastRewind(index));
    });

    // 播放器状态 → 系统 UI。
    _player.playbackEventStream.listen(
      (event) {
        _broadcastState();
        // 换歌了:缓存那一头要知道**正在听的是哪一份**(淘汰时跳过它,
        // 并刷新它的「最近听过」)。
        _noteCurrentTrack(event.currentIndex);
        // 通知栏与锁屏要靠 `mediaItem` 这条流才会更新标题 / 封面 ——
        // 它只在装载动作(setQueue / append / jumpTo …)时被 add 过,
        // 自动切歌不重发的话,通知栏会一直挂着**上一首**。
        // 这里在下标真的变了时补发一份,让系统 UI 跟上当前曲目。
        _publishMediaItem(event.currentIndex);
      },
      onError: (Object e, StackTrace st) {
        // 播放出错也播报出去,免得界面上的按钮停在「正在播放」。
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
        ));
      },
    );
  }

  /// 取值函数而非实例 —— 见 startAudioService 的说明。
  final MusicSource? Function() _repository;
  final QualityController _quality;

  /// 本机下载内容。为 null 表示这块存储用不了,一切照旧走网络。
  final DownloadStore? _downloads;

  /// 听过的歌留的那一份。为 null / 关着表示不缓存,一切照旧走网络。
  final MediaCache? _cache;

  /// 设置页那个「仅 Wi-Fi 下载」开关。**它同时管着新缓存**:
  /// 开关右边那句就是「流量下不缓存」,而留缓存也是在花流量。
  final bool Function() _wifiOnly;

  final NetworkProbe _probe;

  /// 这一趟要不要往磁盘上留新缓存。由 [_syncCachePolicy] 在重建播放源之前定下。
  bool _cacheWanted = true;

  /// 上一次跟缓存打过招呼的「曲目 + 档位」。播放事件来得很密,
  /// 同一份不必反复说。
  String? _notedTrack;

  /// 上一次发布给系统 UI 的 `mediaItem` 对应的曲目 id。播放事件来得很密,用
  /// id 而非下标判断要不要重发:队列可能被拖动重排 / 插播,那时下标不是同一份。
  String? _publishedMediaItemId;

  /// 「这一首**装载那一刻**」装的是哪一份:是不是本机文件、实际用的是哪一档、
/// 以及那个文件的路径。
  ///
  /// 为什么是「装载那一刻」而不是「此刻磁盘上有没有」:边听边缓存的那一份会在
  /// 播到一半时下完(磁盘上从无到有),而**正在放的播放源没有换** —— 它还是那条
  /// 流。「本机文件」是平台唯一能 seek 的东西(见 [_seekRemote]),
  /// 记错了就会出现「明明缓存好了却还是跳不动」。
  ///
  /// 「实际用的是哪一档」也是同一回事:本机已经有更高档那一份时,[_sourceFor]
  /// 会直接拿它播 —— 这时照**所选档**去算缓存路径会指到一个不存在的文件,
  /// 缓存那边记「正在听的是哪一份」就会记错(淘汰时可能删掉正在解码的那份)。
  ///
  /// 覆盖写:每次拼播放源都会把那一首的实况记一遍。
  ///
  /// **有上限**:键是「曲目 @ 所选档」,而一次 `setQueue` 会把整条队列都拼
  /// 一遍 —— 几千首的库、来回换档,它就会一直涨(每条都不大,涨起来却是
  /// 没有尽头的)。记的是「装载那一刻」的实况,清掉只会让下一次查询退回
  /// 保守判断(见 [retargetCurrentRoute]),不会算错。
  static const _localLoadedLimit = 512;
  final Map<String, ({bool local, QualityOption quality, String? path})> _localLoaded = {};

  /// 这一首**装载那一刻**用的是哪一份 —— 是不是本机文件、实际用的是哪一档。
  ///
  /// 界面要的正是这两件:播放页那枚档位徽标、歌曲信息里的「实际播放」。
  /// 注意问的是「装载那一刻」而不是「此刻磁盘上有没有」(理由见 [_localLoaded]):
  /// 边听边缓存的那一份会在播到一半时下完,而播放源没有换过。
  ///
  /// **查不到就给 null**:那次装载的记录可能已经被清掉(见 [_localLoadedLimit]),
  /// 也可能这一首根本没被装载过。界面那时只报所选档,不猜来源。
  ({bool local, QualityOption quality})? loadedOriginOf(Song song) {
    final entry = _localLoaded['${song.id}@${_quality.value.id}'];
    if (entry == null) return null;
    return (local: entry.local, quality: entry.quality);
  }

  /// 第几次 seek。等待期间用户又拖了一次的话,先前那一次作废 ——
  /// 否则两次重载会前后脚打起来。
  int _seekToken = 0;

  /// 等「本机那一份」下完的上限。局域网上一首 3 分钟的歌不到 5 秒;
  /// 等不到就别再让用户干等(见 [_seekRemote])。
  static const _seekWait = Duration(seconds: 8);

  /// 位置监察用的两个值([didPlatformRewind] 的判据要靠它们看「有没有跳回去」)。
  Duration _watchedPosition = Duration.zero;
  int? _watchedIndex;

  /// 我们自己请求过 seek 的那一小段时间里,位置往回跳是应当的 —— 别把用户的
  /// 拖动读成「平台又倒回了开头」。
  DateTime _seekGraceUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// 位置监察的宽限期。just_audio 的位置流是**内插**出来的,一次 seek 之后要过
  /// 一两个采样才落到新位置,那期间读到的还是旧值。
  static const _seekGrace = Duration(milliseconds: 1500);

  /// 决定切下一首之前,位置必须仍然落在这个窗口里 —— 见 [_advancePastRewind]。
  static const _rewindConfirmWindow = Duration(seconds: 3);

  /// 记一次「接下来位置会跳」—— 我们自己的 seek / 重载 / 切歌前都该叫一声。
  void _expectPositionJump() {
    _seekGraceUntil = DateTime.now().add(_seekGrace);
  }

  /// 队列里第 [index] 首的时长(元数据)。拿不到就是零 —— 判据会退回绝对值底线。
  Duration _durationAt(int index) {
    if (index < 0 || index >= _queue.length) return Duration.zero;
    return _queue[index].duration;
  }

  /// 平台放完一首后自己倒回开头(见 [didPlatformRewind])—— 自己切下一首。
  ///
  /// 判据只在位置流上看,所以这里再确认一次真的还有下一首:队列走到头就按
  /// 「这一轮放完了」处理(与 `processingStateStream` 那一支同一条路),
  /// 而且**要把播放器真的按住** —— 平台还在重放,只播报状态是拦不住声音的。
  ///
  /// [index] 是判据成立那一刻的下标。真切之前再核一遍它没变、位置也还在开头
  /// 附近:判据到这一刀之间隔着一次异步,平台自己也可能已经切了。
  Future<void> _advancePastRewind(int index) async {
    _expectPositionJump();
    if (!_player.hasNext) {
      await _player.pause();
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.completed,
        playing: false,
      ));
      return;
    }
    if (_player.currentIndex != index) return;
    if (_player.position > _rewindConfirmWindow) return;
    // 常驻的一行:冷流上这条护栏是唯一在切歌的那一支,真机排障要看它有没有响。
    debugPrint('[Nordic] 平台倒回开头 → 自己切下一首 idx=$index');
    await _player.seekToNext();
    await play();
  }

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

  /// 已经缓冲到哪儿。与位置同源(`playbackEventStream`),噪声量级也一样 ——
  /// 界面那边照位置的待遇,单开一条通道,别混进 [playbackState]。
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

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
  ///
  /// 给的是**视图**而不是拷贝:`List.unmodifiable` 每次访问都要复制一遍整条队列,
  /// 而上千首的队列每次重建队列面板、每次读「还有多久」都会被读一次。
  /// 队列本身只整体替换、从不原地改(见 [setQueue] / [append] 各处),
  /// 所以视图拿到的永远是一致的快照。
  List<Song> get songs => UnmodifiableListView(_queue);

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

    await _syncCachePolicy();

    final start = index.clamp(0, songs.length - 1);
    final items = songs.map(_mediaItemFor).toList();
    mediaItem.add(items[start]);
    queue.add(items);

    // 上面那份 `items` 既给 `queue` / 通知栏,也当播放源的 tag ——
    // 每首只造一个 `MediaItem`(两条路的封面推导本来就落在同一个值上)。
    await _player.setAudioSources(
      [
        for (var i = 0; i < songs.length; i++)
          _sourceFor(songs[i], item: items[i]),
      ],
      initialIndex: start,
      initialPosition: Duration.zero,
    );
    await play();
  }

  /// 追加到队列末尾。
  Future<void> append(Song song) async {
    if (_queue.isEmpty) return setQueue([song]);
    await _syncCachePolicy();
    _queue = [..._queue, song];
    final item = _mediaItemFor(song);
    await _player.addAudioSource(_sourceFor(song, item: item));
    queue.add([...queue.value, item]);
  }

  /// 「下一首播放」:插到当前曲目之后。
  Future<void> insertNext(Song song) async {
    if (_queue.isEmpty) return setQueue([song]);
    await _syncCachePolicy();
    final at = ((_player.currentIndex ?? 0) + 1).clamp(0, _queue.length);
    _queue = [..._queue]..insert(at, song);
    final item = _mediaItemFor(song);
    await _player.insertAudioSource(at, _sourceFor(song, item: item));
    queue.add([...queue.value]..insert(at, item));
  }

  /// 跳转到队列中的第 [index] 首并开始播放。
  Future<void> jumpTo(int index) async {
    _expectPositionJump();
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
  ///
  /// [newIndex] 已经由 `ReorderableListView.onReorderItem` 算成
  /// 「移除 oldIndex 之后」的插入下标,这里**不要再减一**。
  Future<void> reorder(int oldIndex, int newIndex) async {
    _expectPositionJump();
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    await _syncCachePolicy();

    final target = newIndex.clamp(0, _queue.length - 1);
    final next = [..._queue];
    next.insert(target, next.removeAt(oldIndex));
    _queue = next;

    // **就地挪一位,不重建整队。** 重建等于把每一首的播放源重拼一遍(整队一次
    // 盘查询),再从 0 装载、seek 回原处 —— 正在听的那一份(位置、缓冲、边听边
    // 写的那半截缓存)全部作废。`moveAudioSource` 的下标语义与上面那句
    // `insert(target, removeAt(oldIndex))` 逐字相同(just_audio 的 `move` 就是
    // 这么实现的),当前这一份不动,位置与缓冲都交给平台自己搬。
    await _player.moveAudioSource(oldIndex, target);
    // 通知栏 / 队列流拿到的那份也照同一套下标挪(队列流与 `_queue` 一直是同步的,
    // 别处几处改动也都是这么从 `queue.value` 派生的)。
    final nextItems = [...queue.value];
    nextItems.insert(target, nextItems.removeAt(oldIndex));
    queue.add(nextItems);
  }

  /// 切换转码档位。当前这首会以新档位重新加载;**位置尽量保住** ——
  /// 用户切档时多半正听着,从头开始会很难受。
  Future<void> applyQuality(QualityOption option) async {
    _expectPositionJump();
    final index = _player.currentIndex;
    if (index == null || index >= _queue.length) {
      // 队列空也要把选择记下来,下次播放按新档走。
      _quality.set(option);
      return;
    }

    final position = _player.position;
    final wasPlaying = _player.playing;

    _quality.set(option);
    await _syncCachePolicy();
    await _player.setAudioSources(
      _queue.map(_sourceFor).toList(),
      initialIndex: index,
      initialPosition: position,
    );
    // 换档之后「正在听的那一份」换成了另一个文件(缓存的键里带着档位)——
    // 上面的键换了,下一次播放事件会重新标记它。
    if (wasPlaying) await play();
  }

  /// 线路换了(用户手动锁定 / 增删线路)。**正在放的这一首要跟着换过去** ——
  /// 「播放中可随时切换线路」那句话说的是现在这一首,而不是下一首。
  ///
  /// 与 [applyQuality] 同一套做法:整批重新装载,位置保住。差别只在
  /// 两处**不必重载**的情况:队列空(没有在放的),以及这首走的是本机文件
  /// (下载过 / 缓存过的与线路无关,重载只是白等一次缓冲)。
  Future<void> retargetCurrentRoute() async {
    _expectPositionJump();
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= _queue.length) return;

    final song = _queue[index];
    // 本机那一份:下载过的、缓存过的,或者**更高档那份缓存**(见 [_sourceFor])——
    // 它与线路无关,重载只是白等一次缓冲。
    final local = _localLoaded['${song.id}@${_quality.value.id}']?.local ?? false;
    if (local || _localFileFor(song) != null) return;
    // 没有仓库就拼不出新地址 —— 与 [setQueue] 一样,由那一头提前拦下。
    if (_repo == null) return;

    final position = _player.position;
    final wasPlaying = _player.playing;

    await _syncCachePolicy();
    await _player.setAudioSources(
      _queue.map(_sourceFor).toList(),
      initialIndex: index,
      initialPosition: position,
    );
    if (wasPlaying) await play();
  }

  // ---------------- AudioHandler 接口 ----------------

  @override
  Future<void> play() {
    return _player.play();
  }

  @override
  Future<void> pause() {
    return _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    // 位置要跳了 —— 别让位置监察把这一下读成「平台又倒回了开头」(见 [didPlatformRewind])。
    _expectPositionJump();
    // 远端那一首要先「落地」才跳得动 —— 见 [_seekRemote]。
    if (await _seekRemote(position)) return;
    return _player.seek(position);
  }

  /// 远端流那一半的跳转。**落地了返回 true**(调用点就不必再动平台)。
  ///
  /// **冷转码流根本不能 seek** —— 真机实测:Navidrome 对一首**还没转码过**的
  /// 曲子回的是 `Accept-Ranges: none` + `Transfer-Encoding: chunked`:既没有
  /// 长度、也不支持 Range。just_audio 的流式源于是交给平台一个「没有长度、
  /// 不可 seek」的源,`_player.seek()` **静默不做** —— 用户看到的就是
  /// 「拖了进度条,进度纹丝不动」。同一个 URL 一旦转码结果落成静态文件,
  /// 回的就是 `206 + Content-Range + Accept-Ranges: bytes`,那才是能 seek 的。
  ///
  /// 能 seek 的只有**有长度的那一份**:下载过的、或边听边缓存已经下完的
  /// (那时它就是本机文件)。所以这里等它下完(局域网上一首 3 分钟的歌不到
  /// 5 秒),再整批重载到目标位置 —— 重载会解析成本机文件,落点精确。
  ///
  /// 等不到(缓存关着 / 网络太慢)就退回平台的原生 seek:那一下在冷流上不作数,
  /// 但**不会把歌从头重放**,也不假报进度 —— 比「假装跳了」干净。
  Future<bool> _seekRemote(Duration position) async {
    final cache = _cache;
    final index = _player.currentIndex;
    if (cache == null || !cache.enabled) return false;
    if (index == null || index < 0 || index >= _queue.length) return false;

    final song = _queue[index];
    final quality = _quality.value;
    // 正在放的已经是本机那一份 —— 平台自己就能 seek,不必绕这一圈。
    if (_localLoaded['${song.id}@${quality.id}']?.local ?? false) return false;

    final token = ++_seekToken;
    final ready = await _waitForLocalCopy(song, quality);
    // 等待期间可能又拖了一次 / 换了歌 / 这一首已经放完 —— 后来那一次说了算。
    if (!ready || token != _seekToken) return false;
    if (_player.currentIndex != index) return false;
    if (_localLoaded['${song.id}@${quality.id}']?.local ?? false) return false;

    await _reloadAt(index, position);
    return true;
  }

  /// 等这一份**完整**落到本机(下载完 / 边听边缓存下完)。上限 [_seekWait]。
  Future<bool> _waitForLocalCopy(Song song, QualityOption quality) async {
    final cache = _cache;
    if (cache == null) return false;
    final deadline = DateTime.now().add(_seekWait);
    while (DateTime.now().isBefore(deadline)) {
      if (cache.isComplete(
        song,
        qualityId: quality.id,
        format: quality.format,
      )) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// 整批重新装载,停在 [position] —— 与 [applyQuality] 同一套做法。
  Future<void> _reloadAt(int index, Duration position) async {
    final wasPlaying = _player.playing;
    _expectPositionJump();
    await _syncCachePolicy();
    await _player.setAudioSources(
      _queue.map(_sourceFor).toList(),
      initialIndex: index,
      initialPosition: position,
    );
    if (wasPlaying) await play();
  }

  @override
  Future<void> skipToNext() {
    _expectPositionJump();
    return _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() {
    // 「上一首」在放到 3 秒以后是**把这一首倒回开头**(不是换歌)—— 同样是位置
    // 往回跳,同样不该被位置监察当成平台的锅。
    _expectPositionJump();
    return _player.seekToPrevious();
  }

  @override
  Future<void> skipToQueueItem(int index) => jumpTo(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(loopModeFor(repeatMode));
    // `setLoopMode` 不发 playbackEvent,通知栏那个循环图标不会自己更新 ——
    // 主动播报一次。模式**传进去**而不是回头读 `_player.loopMode`:后者是经
    // `addStream` 派生出来的,要等一个微任务才落地,这里读回来可能是上一态。
    _broadcastState(repeat: repeatMode);
    return super.setRepeatMode(repeatMode);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(
      shuffleMode == AudioServiceShuffleMode.all,
    );
    _broadcastState(shuffle: shuffleMode);
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

  /// 当前生效的仓库。没配服务器时为 null —— 调用点要自己判,
  /// 不要在这里造一个连不上任何东西的假仓库。
  MusicSource? get _repo => _repository();

  /// 域模型 → 播放源。**先看本机有没有下载,再看有没有缓存,最后才谈转码档位。**
  ///
  /// 下载过的那首无论当前档位是什么都走本机文件:它已经在磁盘上了,
  /// 质量还比转码档高(下的是原文件),再打一次网络请求没有任何好处。
  /// 缓存过的那首同理 —— 它是**听过的**那一份,连离线都省了。
  ///
  /// 走网络时**边听边留一份**(缓存开着的话):下一次听同一首直接读本机。
  /// 用的是 just_audio 的 `LockCachingAudioSource` —— 它一边把流喂给解码器
  /// 一边写缓存文件,下完再改名为正式的那一份。于是听一首歌**不会**多花一份
  /// 流量(不像「先下完再播」或者「播完再下一遍」)。
  ///
  /// 拿不到仓库说明配置在播放途中被清掉了(用户移除了服务器)。
  /// 那种情况下没有本机文件的曲子给不出地址 —— 由 [setQueue] 提前拦下。
  ///
  /// [item] 是**已经算好的**那一份 `MediaItem`(`setQueue` / `reorder` / 追加
  /// 那几处已经把同一份交给 `queue` 与通知栏了)。不传就自己算一份 —— 一次装载
  /// 里每首歌只该有一个 MediaItem,两处各算一遍就是每首白造一个对象。
  AudioSource _sourceFor(Song song, {MediaItem? item}) {
    final quality = _quality.value;
    final cached = _cache?.cachedPathFor(
      song,
      qualityId: quality.id,
      format: quality.format,
    );

    // 本机要是有**更高**一档的完整缓存,直接拿它播:白拿的音质,而且不花流量
    // (与「已经留着的照旧读本机」同一条口径)。命中时这一首根本不会再写一份
    // 缓存 —— 同一首两台并存的那件事,从源头上就不发生了。
    //
    // **与所选档自己有没有缓存无关**:低档那份只是「当初那样听过」留下的痕迹,
    // 手上有更好的就不该再拿它播,更不该让两份长期并存。早先这一句只在
    // `cached == null` 时才去找更高档 —— 于是「先按高档听过、后来又有了原音档」
    // 这种曲子会一直播着低档那份,而更高档的原音躺在盘上吃灰,正是要治的那件事。
    final better =
        _cache?.completeCopyAmong(song, _tierSpecs(betterTiersThan(quality)));
    // 实际用的是哪一档 —— 下面要按它记账(见 [_localLoaded])。
    final resolved = better == null ? quality : QualityOption.byId(better.qualityId);

    final origin = playbackOriginFor(
      song,
      localPath: _downloads?.localPathFor(song.id),
      // 更高档那一份**优先**:两份都在盘上时(先按高档听过、又落了原音档),
      // 播的该是更好的那一份。
      cachedPath: better?.path ?? cached,
      // 缓存那一份的「在不在」走缓存自己的备忘录(上面那两个查询刚问过它);
      // **下载那一份永远真查** —— 它可能被用户在系统里删掉。
      pathExists: _cache?.existsAt,
      remote: () {
        final repo = _repo;
        if (repo == null) {
          throw StateError('还没有配置服务器，无法构建播放源');
        }
        return repo.streamUri(
          song.id,
          maxBitRate: quality.maxBitRate,
          format: quality.format,
        );
      },
    );

    // 把元数据里的时长**声明**给播放源。转码流的响应没有 Content-Length,
    // 平台报不出时长(ExoPlayer 给 TIME_UNSET → null),进度条于是结构性卡在 0;
    // just_audio 在平台报 null 时会退到这里的声明值,而平台一旦报出真值又会覆盖它
    // (`sequence[index].duration = duration`),两头发力不会互相打架。
    final duration = song.duration;
    final declared = duration > Duration.zero ? duration : null;
    // 记下这一首**装载的是哪一份** —— 只有本机文件 seek 得动(见 [_seekRemote])。
    // 键是「所选档」(`_seekRemote` 就按这个键查),值里带着**实际用的那一档**。
    _localLoaded['${song.id}@${quality.id}'] = (
      local: origin.local,
      quality: resolved,
      path: origin.local ? origin.uri.toFilePath() : null,
    );
    // 装完整条队列之后会攒下成千上万条(每次 setQueue 都会重记一遍)——
    // 满了整体清掉,下一次查询退回保守判断即可(见 [_localLoadedLimit])。
    if (_localLoaded.length > _localLoadedLimit) _localLoaded.clear();
    final mediaItem = item ??
        _mediaItemFor(
          song,
          // 本机文件配本机的封面 —— 离线时通知栏不该只剩一块灰。
          localCover: origin.local
              ? _downloads?.coverPathForArt(song.coverArtId)
              : null,
        );

    // 我们只可能是 progressive:`/rest/stream.view` 永远不会命中 mpd / m3u8,
    // 而 `AudioSource.uri` 对这两种之外本来就是返回 `ProgressiveAudioSource` ——
    // 直接构造同一个类型,只是为了能把 `duration` 传进去。
    if (origin.local) {
      return ProgressiveAudioSource(origin.uri,
          tag: mediaItem, duration: declared);
    }

    final slot = _cacheWanted
        ? _cache?.fileFor(song, qualityId: quality.id, format: quality.format)
        : null;
    if (slot != null) {
      // 这是 just_audio 自带的「边听边缓存」源:它把流同时喂给解码器与缓存
      // 文件,下完改名 —— 于是听一首歌**不会**多花一份流量(不像「先下完再播」
      // 或「播完再下一遍」)。标着 experimental,但它是唯一一个能在不改字节流
      // 的前提下做到这件事的东西;换成自己写 StreamAudioSource 反而要把
      // Range 请求、边下边放、失败重试这一整套重实现一遍。
      // ignore: experimental_member_use
      final source = LockCachingAudioSource(
        origin.uri,
        cacheFile: slot,
        tag: mediaItem,
      );
      // 与 [ProgressiveAudioSource] 同一个理由 —— 而且**更要紧**:
      // 第一次听的那一首正是走这条路,进度条不能没有时长。
      source.duration = declared;
      return source;
    }

    return ProgressiveAudioSource(origin.uri,
        tag: mediaItem, duration: declared);
  }

  /// 换歌了(真的换到某一首在放,而不是「拼出了某首歌的播放源」)。
  ///
  /// 缓存那一头要知道**正在听的是哪一份** —— 淘汰时跳过它,并刷新它的
  /// 「最近听过」(LRU 靠文件时间)。挂在播放事件上而不是 [_sourceFor] 里:
  /// 一次 `setQueue` 会把整个队列的播放源都拼出来,在那一头打标记的话,
  /// 最后被记成「正在听」的会是队列的最后一首。
  ///
  /// 淘汰也搭在这里 —— 一直放下去不会重建播放源,这里是会话中途唯一的算账时刻。
  void _noteCurrentTrack(int? index) {
    if (index == null || index < 0 || index >= _queue.length) return;

    final cache = _cache;
    if (cache == null) return;

    final song = _queue[index];
    final quality = _quality.value;

    // **实际用的那一档**与**那个文件**:本机已经有更高档那一份时,
    // 上面拼播放源的那一步拿的是它 —— 照所选档去报,缓存那边会记错
    // (淘汰时可能删掉正在解码的那份,而低档那几份反倒留着)。
    final loaded = _localLoaded['${song.id}@${quality.id}'];
    final playing = loaded?.quality ?? quality;

    // 记账的键把**实际用的那一份**也算进去(不只是「曲目 + 所选档」):
    // 播放途中换了源、而所选档没变的情形是有的 —— 更高档那份刚下完被接管、
    // 缓存刚写完从流切到本机文件(见 [_waitForLocalCopy])。那一刻要做的三件
    // 事(记「正在听的是哪一份」、刷它的 LRU、让更低档那几份让位)一件都不该
    // 等到用户换歌或换档才发生;只按「曲目 + 所选档」去重就正好把它们全挡掉。
    //
    // 记键而不是下标:队列会被拖动重排、会被插播,那时下标不是同一份了。
    final noteKey = '${song.id}@${playing.id}@${loaded?.path ?? '-'}';
    if (noteKey == _notedTrack) return;
    _notedTrack = noteKey;

    unawaited(cache.markPlaying(
      song,
      qualityId: playing.id,
      format: playing.format,
      playingPath: loaded?.path,
      // 更高档那份**完整落到本机之后**,同曲更低档那几份就该让位了。
      lowerTiers: _tierSpecs(lowerTiersThan(playing)),
    ));
  }

  /// 档位 → 缓存那边要的「(档位 id, 格式)」列表。
  static List<({String qualityId, String? format})> _tierSpecs(
    List<QualityOption> tiers,
  ) =>
      [for (final q in tiers) (qualityId: q.id, format: q.format)];

  /// 系统 UI (通知栏 / 锁屏) 用的 `mediaItem` 跟随当前曲目。
  ///
  /// 队列装载动作那几处已经各发过一次;这里只补「自动切歌」这类**原地换下标**
  /// 的场景 —— 那时没有对应的装载调用,不重发通知栏就停在上一首。
  void _publishMediaItem(int? index) {
    if (index == null || index < 0 || index >= _queue.length) return;
    final song = _queue[index];
    if (song.id == _publishedMediaItemId) return;
    _publishedMediaItemId = song.id;
    mediaItem.add(_mediaItemFor(song));
  }

  /// 这一首在本机的文件(下载的或缓存的),没有就是 null。
  String? _localFileFor(Song song) {
    final downloaded = _downloads?.localPathFor(song.id);
    if (downloaded != null) return downloaded;
    final quality = _quality.value;
    return _cache?.cachedPathFor(
      song,
      qualityId: quality.id,
      format: quality.format,
    );
  }

  /// 重建播放源之前问一次网络,定下「这一趟要不要留新缓存」(判据见
  /// [shouldWriteCache])。**已经缓存过的照旧读本机** —— 那是白拿的,不花流量。
  ///
  /// 播放源是**同步**拼出来的(见 [_sourceFor]),没法在里面 await 网络,
  /// 所以挪到这儿先问好。开关关着时这句是零成本的空操作。
  Future<void> _syncCachePolicy() async {
    if (!_wifiOnly()) {
      _cacheWanted = true;
      return;
    }
    _cacheWanted = shouldWriteCache(
      wifiOnly: true,
      status: await _probe.status(),
    );
  }

  /// 封面一律用专辑封面:Subsonic 里单曲通常没有独立的图。
  ///
  /// **下过的那一首优先用本机封面** —— 离线时通知栏不该只剩一块灰。判据收在
  /// 这里一处:发 mediaItem 的地方有好几处(拼播放源、装载队列、自动切歌),
  /// 只有拼播放源那一处记得传 [localCover] 的话,同一首歌的封面就会时有时无。
  MediaItem _mediaItemFor(Song song, {String? localCover}) {
    final repo = _repo;
    // 表查询,不必碰盘(见 `DownloadStore.coverPathForArt`)—— 整条队列装进来
    // 时这里会被叫上千次,不能是个线性扫描。
    final local = localCover ?? _downloads?.coverPathForArt(song.coverArtId);
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      artUri: switch ((local, song.hasCover, repo)) {
        (final String path, _, _) => Uri.file(path),
        (_, true, final MusicSource r) =>
          r.coverUri(song.coverArtId!, size: 512),
        _ => null,
      },
    );
  }

  /// 把播放器状态翻成 [playbackState] 供系统 UI 使用。
  ///
  /// 循环 / 随机这两个模式**不产生** playbackEvent(`setLoopMode` /
  /// `setShuffleModeEnabled` 只改序列状态),改完要主动播报一次,否则通知栏上的
  /// 图标永远停在默认值 —— 那种时候把新值直接从参数递进来([repeat] / [shuffle]),
  /// 不要回头读播放器(读回来可能还是上一态,见 [setRepeatMode])。
  void _broadcastState({
    AudioServiceRepeatMode? repeat,
    AudioServiceShuffleMode? shuffle,
  }) {
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
      queueIndex: _player.currentIndex,
      repeatMode: repeat ??
          switch (_player.loopMode) {
            LoopMode.off => AudioServiceRepeatMode.none,
            LoopMode.all => AudioServiceRepeatMode.all,
            LoopMode.one => AudioServiceRepeatMode.one,
          },
      shuffleMode: shuffle ??
          (_player.shuffleModeEnabled
              ? AudioServiceShuffleMode.all
              : AudioServiceShuffleMode.none),
    ));
  }
}