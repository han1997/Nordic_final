import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/subsonic_payload.dart';
import '../../playback/playback_controller.dart';
import '../../playback/quality.dart';
import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import 'queue_sheet.dart';
import 'quality_sheet.dart';
import 'routes_sheet.dart';

/// 播放页 —— 封面主导,配色随封面走。
///
/// 这一屏是「随封面取色」的主场:[ImmersiveScaffold] 拿到基于专辑 id 的
/// [NordicAccent] 之后,进度条、播放键、选中态全部跟着变。
///
/// 转码档位、播放队列、线路切换都是从这里揭起来的底部弹层 ——
/// 三者在别处(设置页、专辑页)也要能打开同一张面板,所以各自独立成文件。
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playable = context.watch<PlaybackController>();
    final song = playable.state.song;

    // 还没播过任何东西时给一个诚实的空态,而不是一屏灰按钮。
    if (song == null) {
      return ImmersiveScaffold(
        accent: NordicAccent.neutral(context.nordic.brightness),
        child: Column(
          children: [
            NordicAppBar(
              title: '正在播放',
              big: false,
              transparent: true,
              leading: IconButtonRound(
                icon: Icons.keyboard_arrow_down,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const Expanded(
              child: EmptyState(
                title: '还没有在播的歌',
                detail: '从音乐库里点一首开始。',
              ),
            ),
          ],
        ),
      );
    }

    final accent = NordicAccent.derived(song.albumId);

    return ImmersiveScaffold(
      accent: accent,
      child: Column(
        children: [
          NordicAppBar(
            title: '正在播放',
            big: false,
            transparent: true,
            leading: IconButtonRound(
              icon: Icons.keyboard_arrow_down,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              IconButtonRound(
                icon: Icons.more_horiz,
                quiet: true,
                onPressed: () => _showSongMenu(context, song),
              ),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 封面区吃掉所有剩余高度 —— 原型里封面是这一屏的主角。
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      children: [
                        // 封面与唱片。高度不够时自己收一档,不溢出。
                        _HeroStack(
                          song: song,
                          playing: playable.state.playing,
                          maxSize: math.min(
                            constraints.maxWidth - NordicSpace.s6 * 2,
                            300,
                          ),
                        ),
                        _SongInfo(song: song),
                        _Scrubber(playable: playable),
                        _Controls(playable: playable),
                        _ChipRow(song: song),
                        _RouteLine(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSongMenu(BuildContext context, Song song) {
    final playable = context.read<PlaybackController>();
    final appState = context.read<AppState>();
    final starred = appState.isSongStarred(song.id);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => NordicScrim(
        onTap: () => Navigator.of(sheetContext).pop(),
        child: NordicSheet(
          title: song.title,
          subtitle: '${song.artist} · ${song.album}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetItem(
                icon: starred ? Icons.favorite : Icons.favorite_border,
                label: starred ? '取消收藏' : '收藏这首歌',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  appState.toggleSongStar(song.id);
                },
              ),
              _SheetItem(
                icon: Icons.playlist_play,
                label: '下一首播放',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  playable.playNext(song);
                },
              ),
              _SheetItem(
                icon: Icons.queue_music,
                label: '查看播放队列',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showQueueSheet(context);
                },
              ),
              _SheetItem(
                icon: Icons.album_outlined,
                label: '查看专辑',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  AppRoutes.openAlbum(context, song.albumId);
                },
              ),
              const SizedBox(height: NordicSpace.s2),
            ],
          ),
        ),
      ),
    );
  }
}

/// 封面 + 背后露出的黑胶盘面 —— `.hero-stack`。
///
/// 唱片**随播放状态自转**:静止的渐变色块再怎么调也只是色块,
/// 转起来才有「在放」的感觉。暂停时真的停住(不是隐藏)。
class _HeroStack extends StatelessWidget {
  const _HeroStack({
    required this.song,
    required this.playing,
    required this.maxSize,
  });

  final Song song;
  final bool playing;
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final repo = state.repository;

    Uri? coverUri;
    if (repo != null && song.hasCover) {
      try {
        coverUri = repo.coverUri(song.coverArtId!, size: 700);
      } on SubsonicException {
        coverUri = null;
      }
    }

    final size = maxSize.clamp(160.0, 300.0);
    // 封面收一档并右移,给左边露出的唱片让出宽度。露得太少会读成
    // 「封面旁边蹭了一道黑影」,所以留出约 50px。
    final vinylSize = size * 0.88;
    final shift = size * 0.14;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NordicSpace.s6,
        vertical: NordicSpace.s4,
      ),
      child: SizedBox(
        height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -vinylSize * 0.28,
              child: _Vinyl(size: vinylSize, playing: playing),
            ),
            Positioned(
              left: shift * 0.5,
              child: Hero(
                tag: 'cover-${song.albumId}',
                child: Cover(
                  coverArtId: song.coverArtId,
                  seed: song.albumId,
                  uri: coverUri,
                  size: size,
                  radius: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 黑胶盘面。细密的同心纹路 + 中央标签。
class _Vinyl extends StatefulWidget {
  const _Vinyl({required this.size, required this.playing});

  final double size;
  final bool playing;

  @override
  State<_Vinyl> createState() => _VinylState();
}

class _VinylState extends State<_Vinyl> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    // 真实黑胶 33⅓ 转/分,但按真实转速在屏幕上会显得一顿一顿的;
    // 原型定的 16s/圈看着才顺。
    duration: NordicMotion.vinylSpin,
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(_Vinyl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.playing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent.accent;
    return RotationTransition(
      turns: _spin,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [
              Color(0xFF1A1A20),
              Color(0xFF0B0B0F),
              Color(0xFF15151A),
              Color(0xFF08080B),
            ],
            stops: [0.17, 0.30, 0.62, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: context.nordic.depth,
              blurRadius: 64,
              offset: const Offset(0, 34),
              spreadRadius: -26,
            ),
          ],
        ),
        child: CustomPaint(
          // 同心纹路 —— 静态的圆盘看不出「在转」,这些细纹是转速的视觉载体。
          painter: _VinylGroovesPainter(),
          child: Center(
            child: Container(
              width: widget.size * 0.30,
              height: widget.size * 0.30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [accent, accent.withValues(alpha: 0)],
                  stops: const [0.26, 0.27],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VinylGroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = const Color(0x0DFFFFFF);

    // 每 3px 一道,与原型的 repeating-radial-gradient 口径一致。
    for (var r = maxRadius * 0.22; r < maxRadius; r += 3) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_VinylGroovesPainter oldDelegate) => false;
}

/// 歌名 / 艺人 / 专辑 + 收藏心。
class _SongInfo extends StatelessWidget {
  const _SongInfo({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final appState = context.watch<AppState>();
    final starred = appState.isSongStarred(song.id);
    final artistId = song.artistId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s6, NordicSpace.s5, NordicSpace.s6, NordicSpace.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: artistId != null
                          ? GestureDetector(
                              onTap: () => AppRoutes.openArtist(context, artistId),
                              child: Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: t.fg2),
                              ),
                            )
                          : Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(color: t.fg2),
                            ),
                    ),
                    Text(
                      ' · ',
                      style: TextStyle(color: t.fg2),
                    ),
                    Flexible(
                      child: GestureDetector(
                        onTap: () => AppRoutes.openAlbum(context, song.albumId),
                        child: Text(
                          song.album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: t.fg2),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: NordicSpace.s4),
          IconButtonRound(
            icon: starred ? Icons.favorite : Icons.favorite_border,
            iconSize: 26,
            color: starred ? context.accentSafe : t.fg2,
            onPressed: () => appState.toggleSongStar(song.id),
          ),
        ],
      ),
    );
  }
}

/// 进度条 + 时间。拖动时旋钮放大并泛光,给出「正握在手里」的反馈。
class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.playable});

  final PlaybackController playable;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  /// 拖动中的位置。非空即表示用户正按着 —— 这期间**不跟播放进度走**,
  /// 否则手指还没松,滑块已经被播放器的位置拽回去了。
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final state = widget.playable.state;
    final durationMs = state.duration.inMilliseconds;
    final hasDuration = durationMs > 0;
    final positionMs = state.position.inMilliseconds.toDouble();

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
class _Controls extends StatelessWidget {
  const _Controls({required this.playable});

  final PlaybackController playable;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = playable.state;
    final accent = context.accent.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s6, NordicSpace.s4, NordicSpace.s6, NordicSpace.s4),
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

/// 底部胶囊排:转码质量 / 歌词 / 队列。
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final quality = context.watch<QualityController>().value;
    final codec = quality.isOriginal
        ? (song.suffix?.toUpperCase() ?? '原音')
        : (quality.format?.toUpperCase() ?? 'MP3');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s4),
      child: Row(
        children: [
          NordicChip(
            label: '${quality.name} · $codec',
            icon: Icons.graphic_eq,
            height: 36,
            onTap: () => showQualitySheet(context),
          ),
          const Spacer(),
          NordicChip(
            label: '歌词',
            icon: Icons.format_quote,
            height: 36,
            onTap: () => AppRoutes.openLyrics(context),
          ),
          const SizedBox(width: NordicSpace.s2),
          NordicChip(
            label: '队列',
            icon: Icons.queue_music,
            height: 36,
            onTap: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }
}

/// 底部线路状态行 —— `.route-line`。点开线路切换面板。
class _RouteLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = context.watch<AppState>();
    final route = state.activeRoute;
    final ping = route == null ? null : state.pings[route.id];

    if (route == null) return const SizedBox(height: NordicSpace.s5);

    final ok = ping == null || ping.isOk;
    final latency = ping?.latency;

    return GestureDetector(
      onTap: () => showRoutesSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s5),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ok ? t.ok : t.bad,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '线路 '),
                    TextSpan(
                      text: route.name,
                      style: TextStyle(color: t.fg2, fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: ok
                          ? ' · 延迟 ${latency?.inMilliseconds ?? '--'} ms · 自动择优'
                          : ' · 不可用 · 自动择优',
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: t.fg3),
              ),
            ),
            Icon(Icons.swap_horiz, size: 15, color: t.fg3),
          ],
        ),
      ),
    );
  }
}

/// 弹层里的通用条目 —— `.menu-item`。
class _SheetItem extends StatelessWidget {
  const _SheetItem({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NordicSpace.s5, vertical: NordicSpace.s4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: t.fg2),
            const SizedBox(width: NordicSpace.s4),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}