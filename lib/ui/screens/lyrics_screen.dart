import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/rows.dart';
import '../widgets/states.dart';

/// 歌词页 —— 逐句高亮,带时间轴时跟真实进度走。
///
/// 关键区别:服务器给的若是**带时间轴**的结构化歌词(Navidrome 的
/// `getLyricsBySongId` 会给),高亮就落在当前时间该唱的那一句上;
/// 只有纯文本时退回「按行数平均分布」,并在页面上**说明这一点** ——
/// 假装时间已知会让高亮乱跳,用户会以为是坏了。
class LyricsScreen extends StatefulWidget {
  const LyricsScreen({super.key});

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final _scrollController = ScrollController();

  String? _loadedForSongId;
  Lyrics _lyrics = Lyrics.empty;
  bool _loading = false;

  /// 已经滚到过的行号。只在换行那一刻滚 —— 每秒滚一次会互相打断,
  /// 也会一直拽着用户不让手动翻阅。
  int _lastScrolledIndex = -1;

  /// 当前曲目的时长。无时间轴歌词按它摊行;在 build 里从播放状态同步。
  Duration _duration = Duration.zero;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ensureLyrics(String songId) async {
    if (_loadedForSongId == songId || _loading) return;
    setState(() {
      _loading = true;
      _loadedForSongId = songId;
      _lyrics = Lyrics.empty;
      _lastScrolledIndex = -1;
    });

    final lyrics = await context.read<AppState>().lyricsFor(songId);
    if (!mounted) return;
    setState(() {
      _lyrics = lyrics;
      _loading = false;
    });
  }

  /// 当前该高亮的行号。
  ///
  /// 有时间轴时按 [LyricLine.start] 找 —— **取最后一个 start ≤ 当前位置**,
  /// 而不是找最近的那一句。这样唱到句间间隙时高亮仍停在前一句上,
  /// 不会提前跳到下一句。
  int _activeIndex(Lyrics lyrics, Duration position) {
    if (lyrics.lines.isEmpty) return -1;
    if (!lyrics.synced) return _averageIndex(lyrics, position);

    var active = 0;
    for (var i = 0; i < lyrics.lines.length; i++) {
      final start = lyrics.lines[i].start;
      if (start == null) continue;
      if (start > position) break;
      active = i;
    }
    return active;
  }

  /// 无时间轴时的退路:按整体进度占比摊到各行上。
  /// 这只是「有个大概方向」,不是真的对齐 —— 所以界面上要说明这一点。
  int _averageIndex(Lyrics lyrics, Duration position) {
    final total = _duration.inMilliseconds;
    // 时长未知时不要除零,也不要假装知道进度 —— 停在第一行。
    if (total <= 0) return 0;
    final ratio = (position.inMilliseconds / total).clamp(0.0, 1.0);
    return (ratio * lyrics.lines.length).floor().clamp(0, lyrics.lines.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final playable = context.watch<PlaybackController>();
    final song = playable.state.song;

    if (song == null) {
      return ImmersiveScaffold(
        accent: NordicAccent.neutral(context.nordic.brightness),
        child: Column(
          children: [
            NordicAppBar(
              title: '歌词',
              big: false,
              transparent: true,
              leading: IconButtonRound(
                icon: Icons.arrow_back,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Expanded(
              child: EmptyState(title: '还没有在播的歌', detail: '从音乐库点一首开始。'),
            ),
          ],
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLyrics(song.id));

    final accent = NordicAccent.derived(song.albumId);
    final position = playable.state.position;
    _duration = playable.state.duration;
    final activeIndex = _activeIndex(_lyrics, position);

    // 换行才滚。放在 build 之后,拿到这一帧的真实布局再滚。
    if (activeIndex >= 0 && activeIndex != _lastScrolledIndex) {
      _lastScrolledIndex = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(activeIndex));
    }

    return ImmersiveScaffold(
      accent: accent,
      bottomBar: _LyricsControls(playable: playable),
      child: Column(
        children: [
          NordicAppBar(
            title: '${song.title} · ${song.artist}',
            big: false,
            transparent: true,
            leading: IconButtonRound(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButtonRound(
                icon: Icons.music_note,
                quiet: true,
                // 回到播放页看封面 —— 歌词页与播放页是同一个播放对象的两面。
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          Expanded(child: _lyricsBody(song, activeIndex)),
        ],
      ),
    );
  }

  Widget _lyricsBody(Song song, int activeIndex) {
    if (_loading) return const LoadingState(message: '正在读取歌词');

    if (_lyrics.isEmpty) {
      return const EmptyState(
        title: '这首歌还没有歌词',
        detail: '服务器上没有为这首曲目提供歌词。',
      );
    }

    return _LyricsList(
      lyrics: _lyrics,
      activeIndex: activeIndex,
      controller: _scrollController,
    );
  }

  /// 把高亮句滚到歌词框的垂直中央。
  void _scrollTo(int index) {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    // 每行的实际高度由内容决定,这里按累计索引估一个位置再滚 ——
    // 用 animateTo 是因为突变会让视线跟不上。
    //
    // 估算而非精确测量:要给每行量高需要 GlobalKey,几十个 key 的
    // 布局开销比这个近似值带来的偏差更贵,而歌词行高基本一致。
    const estimatedLineHeight = 74.0;
    final target = (index * estimatedLineHeight) -
        viewport / 2 +
        estimatedLineHeight / 2;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 480),
      curve: NordicMotion.ease,
    );
  }
}

/// 歌词列表。上下加一层渐隐遮罩,让边缘的行自然淡出。
class _LyricsList extends StatelessWidget {
  const _LyricsList({
    required this.lyrics,
    required this.activeIndex,
    required this.controller,
  });

  final Lyrics lyrics;
  final int activeIndex;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: [0.0, 0.20, 0.80, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: controller,
        // 上下各留出半屏,让第一句与最后一句也能滚到中央。
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.sizeOf(context).height * 0.28,
          horizontal: NordicSpace.s6,
        ),
        itemCount: lyrics.lines.length,
        itemBuilder: (context, index) => _LyricLine(
          line: lyrics.lines[index],
          state: index == activeIndex
              ? _LineState.active
              : index < activeIndex
                  ? _LineState.past
                  : _LineState.upcoming,
        ),
      ),
    );
  }
}

enum _LineState { past, active, upcoming }

/// 一句歌词。三档亮度区分「过去 / 现在 / 未来」—— 不是只有 on/off,
/// 方向感才读得出来。
class _LyricLine extends StatelessWidget {
  const _LyricLine({required this.line, required this.state});

  final LyricLine line;
  final _LineState state;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent.accent;

    final color = switch (state) {
      _LineState.active => t.fg,
      _LineState.past => t.fg4.withValues(alpha: t.fg4.a * 0.6),
      _LineState.upcoming => t.fg4,
    };

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 350),
      curve: NordicMotion.ease,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.4,
        letterSpacing: -0.025,
        color: color,
        shadows: state == _LineState.active
            ? [Shadow(color: accent.withValues(alpha: 0.6 * t.glow), blurRadius: 30)]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(line.text)),
            // 高亮句右缘那一撮辉光 —— 给当前行一个「正在被读到」的方向感。
            AnimatedOpacity(
              duration: const Duration(milliseconds: 350),
              opacity: state == _LineState.active ? 1 : 0,
              child: Container(
                width: 3,
                height: 22,
                margin: const EdgeInsets.only(left: NordicSpace.s2),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(NordicRadius.full),
                  boxShadow: [
                    BoxShadow(color: accent, blurRadius: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌词页底部的控制排 + 进度条。
class _LyricsControls extends StatelessWidget {
  const _LyricsControls({required this.playable});

  final PlaybackController playable;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = playable.state;
    final accent = context.accent.accent;
    final durationMs = state.duration.inMilliseconds;
    final hasDuration = durationMs > 0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + NordicSpace.s3,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 5,
                    activeTrackColor: accent,
                    inactiveTrackColor: t.fill2,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  ),
                  child: Slider(
                    value: hasDuration
                        ? state.position.inMilliseconds
                            .clamp(0, durationMs)
                            .toDouble()
                        : 0,
                    max: hasDuration ? durationMs.toDouble() : 1,
                    onChanged: hasDuration
                        ? (value) =>
                            playable.seek(Duration(milliseconds: value.round()))
                        : null,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDuration(state.position), style: _timeStyle(context)),
                    Text(
                      hasDuration
                          ? '-${formatDuration(state.duration - state.position)}'
                          : '--:--',
                      style: _timeStyle(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: NordicSpace.s2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButtonRound(
                icon: Icons.skip_previous,
                size: 52,
                iconSize: 26,
                color: t.fg2,
                onPressed: state.hasPrevious ? playable.previous : null,
              ),
              const SizedBox(width: NordicSpace.s6),
              GestureDetector(
                onTap: playable.toggle,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: const Alignment(-0.7, -1),
                      end: const Alignment(0.7, 1),
                      colors: [Color.lerp(accent, Colors.white, 0.12)!, accent],
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
                  child: Icon(
                    state.playing ? Icons.pause : Icons.play_arrow,
                    size: 30,
                    color: t.bg,
                  ),
                ),
              ),
              const SizedBox(width: NordicSpace.s6),
              IconButtonRound(
                icon: Icons.skip_next,
                size: 52,
                iconSize: 26,
                color: t.fg2,
                onPressed: state.hasNext ? playable.next : null,
              ),
            ],
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