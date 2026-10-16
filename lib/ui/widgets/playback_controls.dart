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
    final durationMs = widget.playable.state.duration.inMilliseconds;
    final hasDuration = durationMs > 0;
    final positionMs = position.inMilliseconds.toDouble();

    // 时长未知时(还在读流)滑块停在最左,但不显示百分比 ——
    // 给一个凭空的进度比空着更误导。
    final value = _dragValue ??
        (hasDuration ? positionMs.clamp(0, durationMs.toDouble()) : 0.0);
    final dragging = _dragValue != null;

    final shownPosition = Duration(milliseconds: value.round());
    final remaining = hasDuration
        ? Duration(milliseconds: (durationMs - value).round().clamp(0, durationMs))
        : Duration.zero;

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
              value: value,
              max: hasDuration ? durationMs.toDouble() : 1,
              // 时长未知时禁用拖动 —— 拖一个没有长度的轴没有意义。
              onChanged: hasDuration
                  ? (next) => setState(() => _dragValue = next)
                  : null,
              onChangeStart: hasDuration
                  ? (next) => setState(() => _dragValue = next)
                  : null,
              onChangeEnd: hasDuration
                  ? (next) {
                      widget.playable.seek(Duration(milliseconds: next.round()));
                      setState(() => _dragValue = null);
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
                  formatDuration(shownPosition),
                  style: _timeStyle(context),
                ),
                Text(
                  hasDuration ? '-${formatDuration(remaining)}' : '--:--',
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

/// 传输控制 —— 随机 / 上一首 / 播放 / 下一首 / 循环。
class MediaControls extends StatelessWidget {
  const MediaControls({super.key, required this.playable});

  final PlaybackController playable;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = playable.state;
    final accent = context.accent.accent;

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
          GestureDetector(
            onTap: playable.toggle,
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
            icon: Icons.repeat,
            size: 48,
            iconSize: 23,
            color: state.repeatOne ? context.accentSafe : t.fg2,
            onPressed: playable.toggleRepeat,
          ),
        ],
      ),
    );
  }
}
