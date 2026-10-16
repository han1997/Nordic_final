import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/subsonic_payload.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/playback_controls.dart';
import '../widgets/cover.dart';
import 'song_menu_sheet.dart';

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
            _nowPlayingBar(context),
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
          _nowPlayingBar(
            context,
            actions: [
              IconButtonRound(
                icon: Icons.more_horiz,
                quiet: true,
                onPressed: () => _showSongMenu(context, song),
              ),
            ],
          ),
          // 骨架与原型一致:`flex: 1` 的封面区(在里头居中)+ 底部一组
          // (信息 / 进度 / 控制)。
          //
          // 这里**不是**一个可滚动的长条:之前用「滚动 + minHeight」把内容
          // 顶在上边,去掉底部两排胶囊之后底下就空了一大块 —— 封面也不再居中。
          // 封面高度同时受宽与高约束(窄屏 / 分屏按高度收一档),于是不必靠
          // 滚动兜底。
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  Expanded(
                    child: Center(
                      child: _HeroStack(
                        song: song,
                        playing: playable.state.playing,
                        maxSize: math.min(
                          math.min(
                            constraints.maxWidth - NordicSpace.s6 * 2,
                            292,
                          ),
                          // 高度也吃得下才行 —— 0.55 是给下面那组留的位置。
                          constraints.maxHeight * 0.55,
                        ),
                      ),
                    ),
                  ),
                  _SongInfo(song: song),
                  PlaybackScrubber(playable: playable),
                  MediaControls(playable: playable),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSongMenu(BuildContext context, Song song) =>
      showSongMenu(context, song);
}

/// 播放页顶栏 —— 与原型同款:左边一个返回箭头,中间一颗**居中的小字标签**,
/// 右边「⋯」(空态时没有右边的动作)。
///
/// 那颗标签不是标题:11px、字距 0.1em、三级前景色 —— 它只说「这是哪一屏」,
/// 真正的主角在下面的封面。
Widget _nowPlayingBar(BuildContext context, {List<Widget> actions = const []}) =>
    NordicAppBar(
      title: '正在播放',
      big: false,
      transparent: true,
      centerTitle: true,
      titleWidget: Text(
        '正在播放',
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
          color: context.nordic.fg3,
        ),
      ),
      leading: IconButtonRound(
        // 原型用的是左箭头(不是往下)。播放页现在也是从右侧滑入的,
        // 左箭头与来路对得上。
        icon: Icons.chevron_left,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      actions: actions,
    );

/// 封面 —— 播放页唯一的主角。
///
/// 背后原先还压着一截黑胶盘面(靠自转表示「在放」),但那圈盘面把封面挤窄、
/// 又把视线分成两半。现在播放状态交给播放键与进度条说,封面独占居中,
/// 背后只留一层光晕:在放时缓慢呼吸。
///
/// 封面**可点** —— 点它翻到歌词,歌词页点回来,进出都不必去够返回键。
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
        // 512 与专辑页 / 网格同一张 —— 从那儿进播放页时直接命中缓存,
        // 不再为了更大的 700 重新下一张(那一下正好落在滑入动画上)。
        coverUri = repo.coverUri(song.coverArtId!, size: 512);
      } on SubsonicException {
        coverUri = null;
      }
    }

    // 原型:`.hero-cover` 上限 292,光晕比封面大一圈(inset -6%)。
    final size = maxSize.clamp(140.0, 292.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s6),
      child: GestureDetector(
        onTap: () => AppRoutes.openLyrics(context),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: size,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              _CoverGlow(size: size, playing: playing),
              Hero(
                tag: 'cover-${song.albumId}',
                child: Cover(
                  coverArtId: song.coverArtId,
                  seed: song.albumId,
                  uri: coverUri,
                  size: size,
                  radius: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 封面背后那层光晕。
///
/// **在放时呼吸,暂停时停住** —— 这是这一屏仅存的动效,而它走的是 opacity
/// (合成层上的事),不是动画 box-shadow:后者每帧都要重画整张封面。
class _CoverGlow extends StatefulWidget {
  const _CoverGlow({required this.size, required this.playing});

  final double size;
  final bool playing;

  @override
  State<_CoverGlow> createState() => _CoverGlowState();
}

class _CoverGlowState extends State<_CoverGlow>
    with SingleTickerProviderStateMixin {
  /// 一个来回 6.4 秒 —— 与原型同速。再快就成了「闪」。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_CoverGlow old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.playing && _controller.isAnimating) {
      // 停在当前亮度,不跳回暗档 —— 呼吸是「在放」的信号,停下来就够。
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent.accent;
    final side = widget.size * 1.12;

    return IgnorePointer(
      // 单独一层:这圈光晕每帧都在动,隔开之后它的重绘与重合成不会牵动
      // 整屏(播放页本来就同时挂着氛围模糊与坞那层玻璃)。
      child: RepaintBoundary(
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.38, end: 0.72).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
          ),
          child: Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // 渐隐到底就是柔化,不必再叠一层 ImageFilter.blur ——
              // 那会多一次全尺寸的滤镜合成。
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.55),
                  accent.withValues(alpha: 0),
                ],
                stops: const [0.24, 0.68],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
        // 原型 `.player-info .top-row` 是居中:心形对着标题与艺人那一块居中,
        // 不是贴着标题顶。
        crossAxisAlignment: CrossAxisAlignment.center,
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
                        // 原型:letter-spacing -0.035em。
                        letterSpacing: -0.9,
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



/// 弹层里的通用条目 —— `.menu-item`。

