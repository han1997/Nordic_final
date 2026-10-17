import 'package:flutter/material.dart';

import '../../playback/playback_controller.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/rows.dart';

/// 播放控制区 —— 进度条 + 一排控制键,**播放页与歌词页共用一份**。
///
/// 两个页面是同一件东西的两面(点封面来回翻),控制区要是各长一个样子,
/// 翻过去就像换了台设备。原型里也是同一份(`scrubBar()` + `mediaControls()`)。
///
/// 进度条自己订阅位置通道(见 [PlaybackController.position])—— 位置每秒变
/// 好几次,不该把整屏都拉进「每秒重建几次」的名单里。

/// 进度条该画成什么样。抽成顶层纯函数是为了能直接测 ——
/// 「歌在放、进度条却写 0:00」那个真机报的 bug 的护栏就钉在这里。
///
/// 三条口径:
/// - 时长未知(转码流平台报不出、元数据里也没有)时滑块停最左、量程给 1,
///   而且**不给拖** —— 拖一个没有长度的轴没有意义;
/// - 但左端仍然写**真实位置**:写 0 就成了「歌在放、进度条说还在开头」;
/// - 位置越界(比如拖动中途换了档位)一律夹回 `[0, duration]`。
({
  double value,
  double max,
  Duration shownPosition,
  Duration remaining,
  bool hasDuration,
}) scrubberFrame({
  required Duration position,
  required Duration duration,
  double? dragValue,
}) {
  final durationMs = duration.inMilliseconds;
  final hasDuration = durationMs > 0;
  final value = dragValue ??
      (hasDuration
          ? position.inMilliseconds.clamp(0, durationMs).toDouble()
          : 0.0);

  return (
    value: value,
    max: hasDuration ? durationMs.toDouble() : 1,
    shownPosition:
        hasDuration ? Duration(milliseconds: value.round()) : position,
    remaining: hasDuration
        ? Duration(
            milliseconds: (durationMs - value).round().clamp(0, durationMs))
        : Duration.zero,
    hasDuration: hasDuration,
  );
}

/// 松手之后拇指停哪儿。
///
/// 真机上「拖动进度条改变不了进度」有一半是**错觉**:远端曲目那一下 seek 不是
/// 立刻就能落地的 —— 冷转码流压根不能 seek,得等本机缓存下完再重载
/// (见 `audio_handler` 的 `seek`)。这期间位置还是旧的,拇指一松就弹回原处,
/// 看着就像白拖了。所以:**位置没落地之前停在手指放开的地方**,落地了再交回
/// 真实进度。
///
/// 两条退出口都必要 ——
/// - 「落地」(`settle` 以内):正常情况,下一批位置就追上来了;
/// - 「认命」(`giveUp`):那一下 seek 没生效(冷流跳不动 / 缓存关着),
///   再停着就是撒谎了 —— 说好按住不放的那只手要松开。
///
/// 抽成顶层纯函数是为了能直接测:两条退出口都会让拇指「永远停在那儿」或
/// 「立刻弹回去」,那是真机上最难复现的一类错。
Duration? scrubberHold({
  required Duration? held,
  required DateTime? heldAt,
  required Duration position,
  required DateTime now,
  Duration settle = const Duration(milliseconds: 1500),
  Duration giveUp = const Duration(seconds: 8),
}) {
  if (held == null || heldAt == null) return null;
  if ((position - held).abs() <= settle) return null;
  if (now.difference(heldAt) >= giveUp) return null;
  return held;
}

class PlaybackScrubber extends StatefulWidget {
  const PlaybackScrubber({super.key, required this.playable});

  final PlaybackController playable;

  @override
  State<PlaybackScrubber> createState() => _PlaybackScrubberState();
}

class _PlaybackScrubberState extends State<PlaybackScrubber> {
  /// 拖动中的位置。非空即表示用户正按着 —— 这期间**不跟播放进度走**,
  /// 否则手指还没松,滑块已经被播放器的位置拽回去了。
  double? _dragValue;

  /// 松手之后落点停在哪(见 [scrubberHold])。
  Duration? _dropped;
  DateTime? _droppedAt;

  @override
  Widget build(BuildContext context) {
    // 位置单独订阅(见 PlaybackController.position):只让这个滑块跟着走,
    // 不必把整屏拉进「每秒重建几次」的名单里。
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.playable.position,
      builder: (context, position, _) => _build(context, position),
    );
  }

  Widget _build(BuildContext context, Duration position) {
    // 落点还该不该停着 —— 位置追上了、或者等够久了就交回去。
    final hold = scrubberHold(
      held: _dropped,
      heldAt: _droppedAt,
      position: position,
      now: DateTime.now(),
    );
    if (hold == null && _dropped != null) {
      _dropped = null;
      _droppedAt = null;
    }

    final frame = scrubberFrame(
      position: position,
      duration: widget.playable.state.duration,
      dragValue: _dragValue ?? hold?.inMilliseconds.toDouble(),
    );
    final dragging = _dragValue != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s6, NordicSpace.s2, NordicSpace.s6, 0),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: context.accent.accent,
              inactiveTrackColor: context.nordic.fill2,
              thumbColor: Colors.white,
              overlayColor: context.accent.accent.withValues(alpha: 0.18),
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: dragging ? 10 : 7,
                elevation: 2,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              value: frame.value,
              max: frame.max,
              // 时长未知时禁用拖动 —— 拖一个没有长度的轴没有意义。
              onChanged: frame.hasDuration
                  ? (next) => setState(() => _dragValue = next)
                  : null,
              onChangeStart: frame.hasDuration
                  ? (next) => setState(() => _dragValue = next)
                  : null,
              onChangeEnd: frame.hasDuration
                  ? (next) {
                      final target = Duration(milliseconds: next.round());
                      // 先记下落点再松手:seek 是异步的,远端那一首还要等本机
                      // 缓存下完才真的跳得过去(见 [scrubberHold])。
                      setState(() {
                        _dragValue = null;
                        _dropped = target;
                        _droppedAt = DateTime.now();
                      });
                      widget.playable.seek(target);
                    }
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatDuration(frame.shownPosition),
                  style: _timeStyle(context),
                ),
                Text(
                  frame.hasDuration
                      ? '-${formatDuration(frame.remaining)}'
                      : '--:--',
                  style: _timeStyle(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle? _timeStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall
      ?.copyWith(
        color: context.nordic.fg3,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// 循环键长什么样。抽成顶层纯函数是为了能直接测。
///
/// **「列表循环」与「顺序播放」用的是同一个图标**,只靠图标这两态分不开 ——
/// `on` 那一层底色因此不能省。上一轮这里报过「点了没反应」,当时是靠一句
/// SnackBar 文案兜的;那句已按用户要求移除,状态就只剩这层表现。
({IconData icon, bool on}) repeatKeyAppearance(PlaybackRepeat mode) => (
      icon: mode == PlaybackRepeat.one ? Icons.repeat_one : Icons.repeat,
      on: mode != PlaybackRepeat.off,
    );

/// 传输控制 —— 随机 / 上一首 / 播放 / 下一首 / 循环。
class MediaControls extends StatelessWidget {
  const MediaControls({super.key, required this.playable});

  final PlaybackController playable;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = playable.state;
    final accent = context.accent.accent;
    // 「开着」的键(随机 / 循环)亮色图标 + 一层同色底 —— 光靠换颜色认不出来。
    final on = selectFill(accent);
    final repeat = repeatKeyAppearance(state.repeat);

    // 底边留得比上边多一点(原型 `--s4 --s6 --s6`),并让开系统指示条 ——
    // 这一排是整屏的落点,贴着底边会显得「掉出去了」。
    return Padding(
      padding: EdgeInsets.fromLTRB(
        NordicSpace.s6,
        NordicSpace.s4,
        NordicSpace.s6,
        NordicSpace.s6 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButtonRound(
            icon: Icons.shuffle,
            size: 48,
            iconSize: 23,
            color: state.shuffle ? context.accentSafe : t.fg2,
            background: state.shuffle ? on : null,
            onPressed: playable.toggleShuffle,
          ),
          IconButtonRound(
            icon: Icons.skip_previous,
            size: 48,
            iconSize: 30,
            color: t.fg2,
            onPressed: state.hasPrevious ? playable.previous : null,
          ),
          // 主播放键:实心强调色渐变 + 外层光晕。
          // 按下去缩 0.93 —— 原型的 `.play-btn:active`。整屏最显眼的一颗键,
          // 少了这一下就属它「点了没反应」最刺眼。
          Pressable(
            onTap: playable.toggle,
            scale: 0.93,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: const Alignment(-0.7, -1),
                  end: const Alignment(0.7, 1),
                  colors: [
                    Color.lerp(accent, Colors.white, 0.12)!,
                    accent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.78),
                    blurRadius: 36,
                    offset: const Offset(0, 18),
                    spreadRadius: -12,
                  ),
                ],
              ),
              child: state.processing
                  ? Padding(
                      padding: const EdgeInsets.all(26),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        // 进度未知时用不确定态转圈,而不是假装有个百分比。
                        color: t.bg,
                        backgroundColor: t.bg.withValues(alpha: 0.25),
                      ),
                    )
                  : Icon(
                      state.playing ? Icons.pause : Icons.play_arrow,
                      size: 34,
                      color: t.bg,
                    ),
            ),
          ),
          IconButtonRound(
            icon: Icons.skip_next,
            size: 48,
            iconSize: 30,
            color: t.fg2,
            onPressed: state.hasNext ? playable.next : null,
          ),
          IconButtonRound(
            // 循环:三态轮转(顺序播放 → 列表循环 → 单曲循环)。
            // 原型只有「开 / 关」两态(开着就是单曲循环),这里是刻意做宽的一处 ——
            // 真机上要求列表循环也能选。别按原型把它改回去。
            //
            // **只换图标与底色,不弹文案**:上一轮加过一句 SnackBar 报
            // 「顺序播放 / 列表循环 / 单曲循环」,连点三下就是三条横幅,
            // 已按用户要求移除。两态分不分得开是底色的事(见 [repeatKeyAppearance])。
            icon: repeat.icon,
            size: 48,
            iconSize: 23,
            color: repeat.on ? context.accentSafe : t.fg2,
            background: repeat.on ? on : null,
            onPressed: playable.cycleRepeat,
          ),
        ],
      ),
    );
  }
}
