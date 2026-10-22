import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../adaptive/window.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/playback_controls.dart';
import '../widgets/rows.dart';
import '../widgets/states.dart';
import 'song_menu_sheet.dart';

/// 歌词页 —— 逐句高亮,带时间轴时跟真实进度走;**点两句才跳**。
///
/// 关键区别:服务器给的若是**带时间轴**的结构化歌词(Navidrome 的
/// `getLyricsBySongId` 会给),高亮就落在当前时间该唱的那一句上;
/// 只有纯文本时退回「按行数平均分布」,并在页面上**说明这一点** ——
/// 假装时间已知会让高亮乱跳,用户会以为是坏了。
///
/// 跳转要**两下**:第一下只把那一句选中(行尾浮出「跳到这句 · 2:30」),
/// 同一句再点一下才落到那一段([seekTargetForLine])—— 跳转不可逆,手一滑就跳到
/// 别处、还回不到刚才在听的地方,所以先让人确认一次。点别的句子只是改选;
/// 两句之间的空白仍是「回封面」:与「点封面看歌词」互为来路的那一条不能丢,
/// 否则这一屏进出就只剩顶栏了。
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

  /// 当前高亮的行 —— **不进 state**。
  ///
  /// 位置每秒跳好几次,而整屏真正变的只有**换行**那几下:走进 `setState` 就是
  /// 把整屏(顶栏 + 一整列歌词 + 满屏氛围)重建一次,而且正好落在自动滚动那
  /// 260ms 的动画里 —— 真机上「跳转动画一顿一顿」多半就是这几帧。
  /// 每行自己订它、自己决定要不要重建(见 [_LyricLine]):换一行只有两行会动。
  final _activeLine = ValueNotifier<int>(-1);

  /// 点中、还差一下才跳的那一行 —— 也是**不进 state**。
  ///
  /// 同一个理由(见 [_activeLine]):选中一行真正变的只有两行(原来选中的那行、
  /// 新选中的那行),走整屏 `setState` 就是把顶栏 + 上百行歌词 + 满屏氛围重建一次,
  /// 而这次改动几乎一定会被**点两下**。每行自己订它、自己决定要不要重建。
  ///
  /// -1 = 没选中。换歌 / 歌词重载时清掉 —— 行号对不上,留着就是指着别人。
  final _pendingLine = ValueNotifier<int>(-1);

  /// 已经排进帧后回调的那一行。同一行只排一次 —— 排重了就是好几个
  /// `ensureVisible` 同时开跑、互相打断,那也读作「卡」。
  int _scheduledFor = -1;

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
  ///
  /// **每行都得有 key 且都要真的建出来**(见 [_LyricsList]:那一列不是 `ListView`):
  /// 没建出来的行拿不到 context,`ensureVisible` 无从下手 —— 「刚点进歌词页不
  /// 跳到当前句」正是这么来的(只有已经滚到眼前的那几行才有 context)。
  List<GlobalKey> _lineKeys = const [];

  /// 用户手动翻歌词的时刻。刚翻过就先别自动拉回 —— 读着读着被拽走很烦。
  DateTime? _userBrowsedAt;

  /// 当前曲目的时长。无时间轴歌词按它摊行;在 build 里从播放状态同步。
  Duration _duration = Duration.zero;

  /// 订阅了哪一份位置通道 —— 换播放器时要退订旧的(见 [didChangeDependencies])。
  PlaybackController? _playback;

  @override
  void initState() {
    super.initState();
    _activeLine.addListener(_onActiveLineChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 位置不进 state 的通知(见 PlaybackController.position),这一屏自己订。
    // 订的是**换行**那一件事,不是每一次位置变化 —— 见 [_onPosition]。
    // 音乐库那边的货架绝不该被同一件事牵着重建。
    final playback = context.read<PlaybackController>();
    if (identical(playback, _playback)) return;
    _playback?.position.removeListener(_onPosition);
    _playback = playback..position.addListener(_onPosition);
  }

  void _onPosition() {
    final playback = _playback;
    if (!mounted || playback == null) return;
    // 位置每秒跳好几次,但整屏真正需要重画的只有**换行**那几下 ——
    // 底部那条进度条自己订了位置通道(见 [PlaybackScrubber]),
    // 不必把一个整屏(含满屏氛围模糊)拉进「每秒重建几次」的名单里。
    final next = activeLyricIndex(
      _lyrics,
      playback.position.value,
      duration: _duration,
    );
    if (next != _activeLine.value) {
      _activeLine.value = next; // 监听者负责滚动;每行自己负责重画
      return;
    }
    // **没换行的时候也要再排一次。** 用户刚翻过歌词时那一滚会被让掉
    // (见 [_scrollToLine] 的四秒宽限),而「让一次」不该变成「再也不回来」——
    // 长句子、间奏里几十秒不换行是常态,那时唯一会把视线拉回去的机会就是
    // 这几跳。[_scheduleScroll] 自己排重,所以重复调用不花钱。
    _scheduleScroll(next);
  }

  /// 换行了 / 换屏高了 —— 把这一句带到框中央。
  ///
  /// 只在换行那一刻滚,否则每秒滚一次会互相打断(见 [_scheduledFor])。
  void _onActiveLineChanged() {
    if (!mounted) return;
    _scheduleScroll(_activeLine.value);
  }

  /// 排一次「滚到这一句」。放到帧后:那时 key 才量得出真实尺寸。
  ///
  /// **同一行只排一次**:位置每秒跳好几次,每次都排一个帧后回调的话,
  /// 好几个 `ensureVisible` 会同时开跑、互相打断 —— 那也读作「卡」。
  /// 「已经滚过了」用 [_scheduledFor] 记,拿不到 context 时把它清回 -1
  /// 让下一跳再试(见 [_scrollToLine])。
  void _scheduleScroll(int index) {
    if (index < 0 || index == _scheduledFor) return;
    _scheduledFor = index;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLine(index));
    // 帧后回调要有帧才跑 —— 换行那一下未必伴随一次重建(位置是不进 state 的),
    // 这里主动催一帧,免得滚动一直等到下一次别的什么重建才发生。
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _playback?.position.removeListener(_onPosition);
    _activeLine.dispose();
    _pendingLine.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ensureLyrics(String songId) async {
    if (_loadedForSongId == songId || _loading) return;
    setState(() {
      _loading = true;
      _loadedForSongId = songId;
      _lyrics = Lyrics.empty;
      _activeLine.value = -1;
      // 换歌 / 重载:上一首选中的那一句不算数(行号也对不上)。
      _pendingLine.value = -1;
    });

    final lyrics = await context.read<AppState>().lyricsFor(songId);
    if (!mounted) return;
    setState(() {
      _lyrics = lyrics;
      _loading = false;
      // 行数变了就得换一批 key —— key 与行一一对应,错位会让滚动落到别处。
      _lineKeys = List.generate(lyrics.lines.length, (_) => GlobalKey());
    });
    // 歌词到手就立刻把高亮与滚动定到当前那一句 —— 进来时歌已经放了一半是常态,
    // 「刚点进歌词页停在第一句」就是这么来的。这里的 key 是一批新的,
    // 所以把「已经滚过哪一行」的记账清掉,逼一次重新落点。
    _scheduledFor = -1;
    _onPosition();
    _scheduleScroll(_activeLine.value);
  }

  /// 点某一句 —— **两下才算跳**。
  ///
  /// 第一下只选中(行尾浮出「跳到这句 · 2:30」),同一句再点一下才落到那一段;
  /// 点别的句子只是改选,不跳。跳转不可逆,手一滑就跳到别处、还回不到刚才在听的
  /// 地方,所以先让人确认一次 —— 而确认要报出**要去哪儿**(胶囊里那个时间),
  /// 否则「确认」只是个多余的点击。
  ///
  /// 跳不到的行([seekTargetForLine] 返回 null)连选中都不给:跳不了的地方
  /// 不该装成跳了,也不该让那一行看起来「选中了却按不动」。
  void _onLineTap(int index) {
    final target = seekTargetForLine(_lyrics, index, duration: _duration);
    if (target == null) return;
    if (_pendingLine.value != index) {
      _pendingLine.value = index;
      return;
    }
    _pendingLine.value = -1;
    _playback?.seek(target);
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
    // 时长是无时间轴歌词摊行的依据,也是「点一句跳哪儿」的依据。
    _duration = playable.state.duration;
    // 高亮**不在这里算**:算它要读位置(每秒跳好几次),而每次重算都会把整屏
    // 拖进重建。位置那条通道自己会算([_onPosition])。
    // 歌词刚到手 / 换了歌时,_ensureLyrics 补算一次。

    // 屏高变了就重新居中一次 —— 旋转 / 分屏 / 系统栏变化后那句会停在偏移处。
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenHeight != _lastViewportHeight) {
      _lastViewportHeight = screenHeight;
      _scheduledFor = -1;
      _scheduleScroll(_activeLine.value);
    }

    return ImmersiveScaffold(
      accent: accent,
      // 与播放页**同一份**控制区(进度条 + 五键)—— 两页是同一件东西的两面,
      // 翻过去不该像换了台设备。
      bottomBar: NarrowContent(
        // 宽屏下控制排与正文同宽收成一栏(窄屏原样)。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlaybackScrubber(playable: playable),
            MediaControls(playable: playable),
          ],
        ),
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
          Expanded(child: _lyricsBody()),
        ],
      ),
    );
  }

  Widget _lyricsBody() {
    if (_loading) return const LoadingState(message: '正在读取歌词');

    if (_lyrics.isEmpty) {
      return const EmptyState(
        title: '这首歌还没有歌词',
        detail: '服务器上没有为这首曲目提供歌词。',
      );
    }

    // 点**某一句**两下跳到那一段,点**行以外的空白**(上下那一大截内边距)回封面 ——
    // 与播放页「点封面看歌词」互为来路,两条都留着。拖动滚动不会触发点击手势,
    // 所以翻歌词不会误退、也不会误跳。
    return Column(
      children: [
        // 没有时间轴的歌词只能按整首的进度平均走 —— 那不是「跟着唱」,
        // 得如实说一句,否则用户会以为高亮坏了。
        if (!_lyrics.synced)
          const ListNote('这份歌词没有时间轴，只能按整首的进度平均走 —— 高亮句不一定对得上。'),
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
                  child: NotificationListener<ScrollStartNotification>(
              // 手指拖动才算「用户在翻」:`ensureVisible` 自己发的通知没有 dragDetails。
              onNotification: (notification) {
                if (notification.dragDetails != null) {
                  _userBrowsedAt = DateTime.now();
                  // 用户接手了,就把「这一行已经滚过」的记账清掉 ——
                  // 不清的话,宽限过去之后 [_onPosition] 再排也是白排
                  // (同一行只会被记一次),那一屏就一直停在他松手的地方。
                  _scheduledFor = -1;
                }
                return false;
              },
              child: NarrowContent(
                // 宽屏下正文收成一栏(720)—— 只加一层限宽,**不动**列结构与
                // 26px 胶囊:行高与选中胶囊有用例按 Rect 钉着(lyrics_screen_test)。
                child: _LyricsList(
                  lyrics: _lyrics,
                  duration: _duration,
                  activeLine: _activeLine,
                  pendingLine: _pendingLine,
                  controller: _scrollController,
                  lineKeys: _lineKeys,
                  onLineTap: _onLineTap,
                ),
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
        DateTime.now().difference(browsed) < lyricBrowseGrace) {
      // 让,但**别把这一行记成「已经滚过了」**:记了的话宽限一过也不会再试
      // (同一行不会再有第二次「换行」),那一屏就一直停在用户松手的地方,
      // 直到下一句歌词才归位。清回 -1,下一跳再试(见 [_onPosition])。
      _scheduledFor = -1;
      return;
    }

    if (index < 0 || index >= _lineKeys.length) return;
    final lineContext = _lineKeys[index].currentContext;
    // 拿不到就说下次再说 —— 别把没滚成的那一行记成「已经滚过了」,
    // 否则它会一直停在原处直到下一句。
    if (lineContext == null) {
      _scheduledFor = -1;
      return;
    }

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
    required this.duration,
    required this.activeLine,
    required this.pendingLine,
    required this.controller,
    required this.lineKeys,
    required this.onLineTap,
  });

  final Lyrics lyrics;

  /// 没时间轴的歌词按它摊行 —— 也是「点这一句跳到哪儿」的依据(见
  /// [seekTargetForLine])。行尾那枚胶囊报的就是这个落点,所以逐行算一份。
  final Duration duration;

  /// 当前高亮行。**传的是通道不是值**:换一行只有那两行自己重建,
  /// 这一整列(含上百行)不跟着重来。
  final ValueListenable<int> activeLine;

  /// 点中、还差一下才跳的那一行。同样是通道(见 [activeLine])。
  final ValueListenable<int> pendingLine;

  final ScrollController controller;

  /// 与 [lyrics] 逐行对应 —— 外层靠它把高亮句滚到中间。
  final List<GlobalKey> lineKeys;

  /// 点某一句 → 选中 / 再点一下跳过去(两段式判断留在 [_LyricsScreenState])。
  final ValueChanged<int> onLineTap;

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
      // **每一行都要真的建出来**,不用 `ListView`:它按视口懒建 Element,
      // 屏幕外的行拿不到 context,`ensureVisible` 也就无从下手 —— 于是
      // 「刚点进歌词页停在第一句」(当前句离屏幕远时永远跳不过去)。
      // 歌词通常几十到一百多行,全建出来的代价远小于「跳不中」。
      //
      // 试过 `ListView(children:)` + 无限缓存区:那一支同样给每行白送一层
      // RepaintBoundary,但 `scrollCacheExtent` 取无限会让视口的语义矩形变成
      // 非有限值(框架断言)。这里是明确的一列,也别丢了那层边界(见下)。
      child: SingleChildScrollView(
        controller: controller,
        // 上下各留出半屏,让第一句与最后一句也能滚到中央。
        // 宽屏下屏更高、这条列也更窄,0.28 会空得离谱 —— 收个 220 上限
        // (窄屏一个数都不改)。
        padding: EdgeInsets.symmetric(
          vertical: context.isExpanded
              ? math.min(MediaQuery.sizeOf(context).height * 0.28, 220)
              : MediaQuery.sizeOf(context).height * 0.28,
          horizontal: NordicSpace.s6,
        ),
        child: Column(
          children: [
            for (var i = 0; i < lyrics.lines.length; i++)
              // 每行一层重绘边界 —— `ListView` 默认就带(`addRepaintBoundaries`),
              // 自己铺列就得自己加:滚动时整列每帧重画,有这层才只动位置不动字。
              RepaintBoundary(
                child: _LyricLine(
                  key: i < lineKeys.length ? lineKeys[i] : null,
                  line: lyrics.lines[i],
                  index: i,
                  activeLine: activeLine,
                  pendingLine: pendingLine,
                  // 落点在这里算一次、随行传下去:胶囊要报「跳到哪儿」,
                  // 而这一列只在整屏重建时才重算(不是每次点)。
                  target: seekTargetForLine(lyrics, i, duration: duration),
                  onTap: () => onLineTap(i),
                ),
              ),
          ],
        ),
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

/// 当前位置该高亮的行号。
///
/// 有时间轴时按 `LyricLine.start` 找 —— **取最后一个 `start ≤ 当前位置`**,
/// 而不是找最近的那一句。这样唱到句间间隙时高亮仍停在前一句上,
/// 不会提前跳到下一句。
///
/// 提成顶层函数是为了让「这一屏要不要重建」也能问它:位置每秒跳好几次,
/// 但真正变的只有**换行**那几下(见 `_LyricsScreenState._onPosition`)。
int activeLyricIndex(
  Lyrics lyrics,
  Duration position, {
  required Duration duration,
}) {
  if (lyrics.lines.isEmpty) return -1;
  if (!lyrics.synced) {
    return averageIndexFor(
      position: position,
      duration: duration,
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

/// 用户手动翻过歌词之后,**先让着他这么久**才恢复自动跟随。
///
/// 读着读着被拽走很烦,所以刚翻过就先不拉回来。但让一次不等于再也不回来 ——
/// 见 [_LyricsScreenState._onPosition] 里那一句「没换行的时候也要再排一次」。
///
/// 可变是为了测试:这一条比的是**真实时钟**(`DateTime.now()`),
/// 而 `testWidgets` 的假时钟推不动它(见 `lyrics_screen_test.dart`)。
Duration lyricBrowseGrace = const Duration(seconds: 4);

/// 点某一句歌词要跳到哪儿。**没有把握就返回 null** —— 界面据此不接这一下点击:
/// 跳不到的地方不该装成跳了。
///
/// 有时间轴就是那一句的起点(高亮取的是「最后一个 `start ≤ 位置`」,
/// 所以跳到起点稳稳落回本行)。
///
/// 没有时间轴时只能按整首摊行**反推**,这里取**那一行的中段**而不是起点:
/// 高亮走的是 [averageIndexFor] 的 `floor(比例 × 行数)`,起点在浮点误差下会被
/// 算成上一行(2.9999999 就是第二句);中段落回本行是稳的。
///
/// 抽成顶层纯函数是为了能直接测:「点第三句、高亮停在第二句」这类错只能在
/// 算里出现,肉眼很难在真机上分辨。它与 [activeLyricIndex] 互为逆运算 ——
/// 那个来回(点一句 → 高亮必须落在同一行)是这一条真正的判据。
Duration? seekTargetForLine(
  Lyrics lyrics,
  int index, {
  required Duration duration,
}) {
  if (index < 0 || index >= lyrics.lines.length) return null;
  final start = lyrics.lines[index].start;
  if (start != null) return start;
  // 整份**带着时间轴**、偏偏这一句没有起点(部分行缺 `start` 的混合时间轴)——
  // 那就是「没有把握」:按行数摊出来的那一刻与这一句真正的位置无关,跳过去
  // 只会跳到别处,而用户以为是这句话的位置。
  if (lyrics.synced) return null;
  if (duration.inMilliseconds <= 0) return null;

  final count = lyrics.lines.length;
  return Duration(
    milliseconds: ((index + 0.5) / count * duration.inMilliseconds).round(),
  );
}

enum _LineState { past, active, upcoming }

/// 一句歌词。三档亮度区分「过去 / 现在 / 未来」—— 不是只有 on/off,
/// 方向感才读得出来。
///
/// 自己订 [activeLine] 而不是由父级把状态传进来:换一行只有**新亮的那一行**与
/// **暗下去的那一行**要重画,整列歌词与整屏都不该跟着重建(见
/// [_LyricsScreenState._activeLine])。
class _LyricLine extends StatefulWidget {
  const _LyricLine({
    super.key,
    required this.line,
    required this.index,
    required this.activeLine,
    required this.pendingLine,
    required this.target,
    required this.onTap,
  });

  final LyricLine line;
  final int index;
  final ValueListenable<int> activeLine;

  /// 点中、还差一下才跳的那一行(见 [_LyricsScreenState._pendingLine])。
  final ValueListenable<int> pendingLine;

  /// 点这一句会跳到哪儿。null = 跳不到(混合时间轴缺 `start`、或连时长都不知道),
  /// 那一行就既不显示胶囊、也不接这一下点击。
  final Duration? target;

  /// 点这一句 → 选中 / 再点一下跳过去。
  final VoidCallback onTap;

  @override
  State<_LyricLine> createState() => _LyricLineState();
}

class _LyricLineState extends State<_LyricLine> {
  late _LineState _state;
  bool _selected = false;
  bool _pressed = false;

  _LineState _stateFor(int active) => widget.index == active
      ? _LineState.active
      : widget.index < active
          ? _LineState.past
          : _LineState.upcoming;

  bool _selectedFor(int pending) =>
      widget.target != null && widget.index == pending;

  @override
  void initState() {
    super.initState();
    _state = _stateFor(widget.activeLine.value);
    _selected = _selectedFor(widget.pendingLine.value);
    widget.activeLine.addListener(_onActiveChanged);
    widget.pendingLine.addListener(_onPendingChanged);
  }

  @override
  void didUpdateWidget(_LyricLine old) {
    super.didUpdateWidget(old);
    if (!identical(old.activeLine, widget.activeLine)) {
      old.activeLine.removeListener(_onActiveChanged);
      widget.activeLine.addListener(_onActiveChanged);
    }
    if (!identical(old.pendingLine, widget.pendingLine)) {
      old.pendingLine.removeListener(_onPendingChanged);
      widget.pendingLine.addListener(_onPendingChanged);
    }
    _state = _stateFor(widget.activeLine.value);
    _selected = _selectedFor(widget.pendingLine.value);
  }

  @override
  void dispose() {
    widget.activeLine.removeListener(_onActiveChanged);
    widget.pendingLine.removeListener(_onPendingChanged);
    super.dispose();
  }

  void _onActiveChanged() {
    final next = _stateFor(widget.activeLine.value);
    // 状态没变就**不重建** —— 一百多行里,真正变色的只有两行。
    if (next == _state || !mounted) return;
    setState(() => _state = next);
  }

  void _onPendingChanged() {
    final next = _selectedFor(widget.pendingLine.value);
    // 同上:点一下真正变的只有「原来选中的那行」与「新选中的那行」。
    if (next == _selected || !mounted) return;
    setState(() => _selected = next);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent.accent;
    final state = _state;
    final selected = _selected;
    final target = widget.target;

    // 选中那一行**提一档亮度**:要跟「正在唱的那一句」(最亮)分得开 ——
    // 那是两件事,不能长得一样。
    final color = selected
        ? t.fg2
        : switch (state) {
            _LineState.active => t.fg,
            _LineState.past => t.fg4.withValues(alpha: t.fg4.a * 0.6),
            _LineState.upcoming => t.fg4,
          };

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      // **opaque**:整行(含上下各 11px 的行距)都算命中。
      // 默认的 `deferToChild` 只命中文字本身那一小条 —— 行距上那半截会漏给
      // 外层那层「点空白退出」的手势上,于是「点歌词没反应,还把歌词页关了」。
      // 按下压一档 —— 原型的 `.lyric-line:active { opacity: .6 }`。
      // 没有这一下,「点了半句没反应」时用户分不出是没点中还是播放器没动。
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: Opacity(
        opacity: _pressed ? 0.6 : 1,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 350),
          curve: NordicMotion.ease,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.4,
            letterSpacing: -0.025,
            color: color,
            shadows: state == _LineState.active
                ? [
                    Shadow(
                        color: accent.withValues(alpha: 0.6 * t.glow),
                        blurRadius: 30)
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text(widget.line.text)),
                // 高亮句右缘那一撮辉光 —— 给当前行一个「正在被读到」的方向感。
                // 选中时让它让位:一行的右缘只放一个东西。
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  opacity: state == _LineState.active && !selected ? 1 : 0,
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
                // 还差一下才跳的那一句:行尾一枚小胶囊,报出**要跳到哪儿**。
                if (selected && target != null) _jumpChip(t, target),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 「跳到这句 · 2:30」那枚胶囊。
  ///
  /// **高 26 必须 ≤ 文字盒高**(22 × 1.4 ≈ 30.8):再高一点,选中一下就把整行
  /// 顶高、整列跟着往下推 —— 点一句歌词不该让歌词挪位。
  ///
  /// 也不复用 `PillButton`:那个固定 36px 高,塞进来就是同一个问题。
  Widget _jumpChip(NordicTokens t, Duration target) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s2),
      decoration: BoxDecoration(
        color: t.fill3,
        borderRadius: BorderRadius.circular(NordicRadius.full),
      ),
      alignment: Alignment.center,
      child: Text(
        '跳到这句 · ${formatDuration(target)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: t.fg2,
        ),
      ),
    );
  }
}

