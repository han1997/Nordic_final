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
import '../widgets/playback_controls.dart';
import '../widgets/states.dart';
import 'song_menu_sheet.dart';

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

  /// 已经滚到过的行号。只在换行那一刻滚 —— 每秒滚一次会互相打断。
  int _lastScrolledIndex = -1;

  /// 上一次滚动时的屏高。屏幕变了(横竖屏 / 分屏 / 系统栏)要重新居中一次,
  /// 否则那一句会停在偏移过的位置。
  double _lastViewportHeight = 0;

  /// 每行一把 key —— 滚动落点靠它**量**准(见 [_scrollToLine])。
  ///
  /// 换成 key 是因为原先的「估高」真的不准:写死每行 74px,而真实行高
  /// (22px × 1.4 的行盒 + 上下各 11 内边距)≈ 52.8;再叠上列表那一大截上内边距
  /// (0.28 × 屏高),两处误差在第 10 行前后抵消、之后线性发散 —— 于是副歌一到
  /// 高亮句就钻进顶部渐隐带,最后四分之一干脆不滚了。几十把 key 的布局开销
  /// 远比这个偏差便宜。
  List<GlobalKey> _lineKeys = const [];

  /// 用户手动翻歌词的时刻。刚翻过就先别自动拉回 —— 读着读着被拽走很烦。
  DateTime? _userBrowsedAt;

  /// 当前曲目的时长。无时间轴歌词按它摊行;在 build 里从播放状态同步。
  Duration _duration = Duration.zero;

  /// 订阅了哪一份位置通道 —— 换播放器时要退订旧的(见 [didChangeDependencies])。
  PlaybackController? _playback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 位置不进 state 的通知(见 PlaybackController.position),这一屏自己订。
    // 逐句高亮要跟着走,所以这里按位置重建整屏是对的 —— 歌词就是几行文字,
    // 而音乐库那边的货架绝不该被同一件事牵着重建。
    final playback = context.read<PlaybackController>();
    if (identical(playback, _playback)) return;
    _playback?.position.removeListener(_onPosition);
    _playback = playback..position.addListener(_onPosition);
  }

  void _onPosition() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _playback?.position.removeListener(_onPosition);
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
      // 行数变了就得换一批 key —— key 与行一一对应,错位会让滚动落到别处。
      _lineKeys = List.generate(lyrics.lines.length, (_) => GlobalKey());
      _lastScrolledIndex = -1;
    });
  }

  /// 当前该高亮的行号。
  ///
  /// 有时间轴时按 [LyricLine.start] 找 —— **取最后一个 start ≤ 当前位置**,
  /// 而不是找最近的那一句。这样唱到句间间隙时高亮仍停在前一句上,
  /// 不会提前跳到下一句。
  int _activeIndex(Lyrics lyrics, Duration position) {
    if (lyrics.lines.isEmpty) return -1;
    if (!lyrics.synced) {
      return averageIndexFor(
        position: position,
        duration: _duration,
        lineCount: lyrics.lines.length,
      );
    }

    var active = 0;
    for (var i = 0; i < lyrics.lines.length; i++) {
      final start = lyrics.lines[i].start;
      if (start == null) continue;
      if (start > position) break;
      active = i;
    }
    return active;
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
    // 位置不进 state 的通知(见 PlaybackController.position),这一屏自己订:
    // 逐句高亮与底部进度条都跟着它走。
    final position = playable.position.value;
    _duration = playable.state.duration;
    final activeIndex = _activeIndex(_lyrics, position);

    // 换行才滚(每帧滚会互相打断);屏幕尺寸变了也补滚一次。
    // 放到帧后:那时 key 才量得出真实尺寸。
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (activeIndex >= 0 &&
        (activeIndex != _lastScrolledIndex ||
            screenHeight != _lastViewportHeight)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToLine(activeIndex),
      );
    }

    return ImmersiveScaffold(
      accent: accent,
      // 与播放页**同一份**控制区(进度条 + 五键)—— 两页是同一件东西的两面,
      // 翻过去不该像换了台设备。
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlaybackScrubber(playable: playable),
          MediaControls(playable: playable),
        ],
      ),
      child: Column(
        children: [
          NordicAppBar(
            title: '${song.title} · ${song.artist}',
            big: false,
            transparent: true,
            // 与播放页同一副顶栏骨架:返回在左、标题居中、「⋯」在右。
            centerTitle: true,
            leading: IconButtonRound(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              // 与播放页同一张「⋯」—— 在歌词页听到一半想收藏 / 下载时,
              // 不必先退回播放页(原型在这屏上也是这颗)。
              IconButtonRound(
                icon: Icons.more_horiz,
                quiet: true,
                onPressed: () => showSongMenu(context, song),
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

    // 点歌词回封面 —— 与播放页「点封面看歌词」互为来路。拖动滚动不会触发
    // 点击手势,所以翻歌词不会误退。
    return Column(
      children: [
        // 没有时间轴的歌词只能按整首的进度平均走 —— 那不是「跟着唱」,
        // 得如实说一句,否则用户会以为高亮坏了。
        if (!_lyrics.synced)
          const ListNote('这份歌词没有时间轴,只能按整首的进度平均走 —— 高亮句不一定对得上。'),
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: NotificationListener<ScrollStartNotification>(
              // 手指拖动才算「用户在翻」:`ensureVisible` 自己发的通知没有 dragDetails。
              onNotification: (notification) {
                if (notification.dragDetails != null) {
                  _userBrowsedAt = DateTime.now();
                }
                return false;
              },
              child: _LyricsList(
                lyrics: _lyrics,
                activeIndex: activeIndex,
                controller: _scrollController,
                lineKeys: _lineKeys,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 把某一句滚到歌词框的**垂直中央**。
  ///
  /// 交给 `Scrollable.ensureVisible(alignment: 0.5)` —— 框架按真实布局算偏移,
  /// 换行的行、列表那截上内边距都自动算对。自己估高试过,不准(见 [_lineKeys])。
  void _scrollToLine(int index) {
    if (!mounted) return;

    // 刚被用户翻过就先让着他:想往后看几眼是常事,硬拉回来很难用。
    final browsed = _userBrowsedAt;
    if (browsed != null &&
        DateTime.now().difference(browsed) < const Duration(seconds: 4)) {
      return;
    }

    if (index < 0 || index >= _lineKeys.length) return;
    final lineContext = _lineKeys[index].currentContext;
    // 拿不到就说下次再说 —— 别把没滚成的那一行记成「已经滚过了」,
    // 否则它会一直停在原处直到下一句。
    if (lineContext == null) return;

    _lastScrolledIndex = index;
    _lastViewportHeight = MediaQuery.sizeOf(context).height;

    Scrollable.ensureVisible(
      lineContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 260),
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
    required this.lineKeys,
  });

  final Lyrics lyrics;
  final int activeIndex;
  final ScrollController controller;

  /// 与 [lyrics] 逐行对应 —— 外层靠它把高亮句滚到中间。
  final List<GlobalKey> lineKeys;

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
      // **全量铺**,不是 `.builder`:滚动落点要量「任意一句」的真实位置,
      // 而懒加载只把视线附近那几行建出来 —— 跳向远处的句子时它压根不存在,
      // `ensureVisible` 也就无从下手。歌词通常几十到一百多行,
      // 全建出来的代价远小于「跳不中」。
      child: ListView(
        controller: controller,
        // 上下各留出半屏,让第一句与最后一句也能滚到中央。
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.sizeOf(context).height * 0.28,
          horizontal: NordicSpace.s6,
        ),
        children: [
          for (var i = 0; i < lyrics.lines.length; i++)
            _LyricLine(
              key: i < lineKeys.length ? lineKeys[i] : null,
              line: lyrics.lines[i],
              state: i == activeIndex
                  ? _LineState.active
                  : i < activeIndex
                      ? _LineState.past
                      : _LineState.upcoming,
            ),
        ],
      ),
    );
  }
}

/// 没有时间轴的歌词:按整首的进度**平均摊行**。
///
/// 这是不得已的近似 —— 没有 `start` 就无从知道哪一句在什么时候唱。
/// 时长也不知道时返回 0:宁可不走,也不假装知道唱到了哪儿。
int averageIndexFor({
  required Duration position,
  required Duration duration,
  required int lineCount,
}) {
  if (lineCount <= 0) return -1;
  if (duration.inMilliseconds <= 0) return 0;
  final ratio =
      (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  return (ratio * lineCount).floor().clamp(0, lineCount - 1);
}

enum _LineState { past, active, upcoming }

/// 一句歌词。三档亮度区分「过去 / 现在 / 未来」—— 不是只有 on/off,
/// 方向感才读得出来。
class _LyricLine extends StatelessWidget {
  const _LyricLine({super.key, required this.line, required this.state});

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

