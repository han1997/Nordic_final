import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/grain.dart';
import '../../theme/tokens.dart';

/// 封面 —— `.cover` 的等价物。
///
/// 三层叠出来:斜向渐变 + 左上角一团强调色光晕 + 一层胶片颗粒。
/// 有真实封面图时铺图;**没图时用这套渐变兜底** —— 兜底不是「加载中」,
/// 而是「这张专辑确实没有封面」,所以不留骨架屏,直接画出来。
///
/// [seed] 决定兜底配色(一般传专辑 id)。同一个 id 每次得到同一套颜色,
/// 冷启动之间也不会变 —— 「每张专辑有自己的气质」靠这个成立。
class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.coverArtId,
    required this.seed,
    this.uri,
    this.size,
    this.width,
    this.height,
    this.radius = NordicRadius.md,
    this.showShadow = true,
  });

  /// 真实封面标识。为空即走渐变兜底。
  final String? coverArtId;

  /// 兜底配色的种子,一般传专辑 id。
  final String seed;

  /// 封面图地址。由调用方从仓库取 —— 只有仓库知道当前线路与凭据。
  ///
  /// **可能是 `file://`**:下过的那张封面就在本机(见 `AppState.localCoverUri`),
  /// 断网时也能显示。
  final Uri? uri;

  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final bool showShadow;

  bool get _hasArt => coverArtId != null && coverArtId!.isNotEmpty && uri != null;

  /// 这张封面实际占的方框边长。宽高都给时取长边 —— 解码桶是方的,
  /// 按长边取不会糊。
  static double? _displayEdge(double? w, double? h) {
    if (w == null && h == null) return null;
    final a = w ?? 0;
    final b = h ?? 0;
    return a > b ? a : b;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = NordicAccent.derived(seed);
    final w = width ?? size;
    final h = height ?? size;

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          if (showShadow)
            BoxShadow(
              color: t.depth,
              blurRadius: 38,
              offset: const Offset(0, 18),
            ),
          // 上缘内描边,给封面一道边。
          BoxShadow(
            color: t.rim,
            blurRadius: 0,
            offset: const Offset(0, 1),
            spreadRadius: -0.5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_hasArt)
              _CoverArt(
                uri: uri!,
                displaySize: _displayEdge(w, h),
                fallback: _Fallback(accent: accent),
              )
            else
              _Fallback(accent: accent),
            // 斜向高光。压在图上也在渐变上,给封面一层「塑料」的厚度。
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [t.hi, t.hi2, Colors.transparent],
                    stops: const [0.0, 0.4, 0.6],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面图本身 —— `file://` 与 `http(s)://` 两条路。
///
/// 分开写是因为 `Image.network` 不认 `file://`(会把路径当网址发出去,
/// 然后拿回一块空白)。两者的错误与加载中行为一致:退回渐变,
/// 而不是留白或者破图 —— 服务器上偶有坏图,本地文件也可能被清理工具删掉。
class _CoverArt extends StatelessWidget {
  const _CoverArt({
    required this.uri,
    required this.fallback,
    this.displaySize,
  });

  final Uri uri;
  final Widget fallback;

  /// 这张图实际要画多大(logical px)。不传就按原图解码。
  final double? displaySize;

  /// 解码边长:显示尺寸 × 像素密度,**向上取到 2 的幂**再夹在 128–1024。
  ///
  /// 取整到 2 的幂是为了让不同地方的同尺寸封面共用一份解码结果 ——
  /// 46 的坞缩略图和 48 的队列行是同一个桶,不必各解一张。
  static int? _decodeEdge(BuildContext context, double? displaySize) {
    if (displaySize == null || displaySize <= 0) return null;
    final px = displaySize * MediaQuery.devicePixelRatioOf(context);
    var edge = 128;
    while (edge < px && edge < 1024) {
      edge *= 2;
    }
    return edge;
  }

  @override
  Widget build(BuildContext context) {
    // 加载中先用渐变占位,图到了再换上去,不留白。
    Widget placeholder(
      BuildContext context,
      Widget child,
      int? frame,
      bool wasSynchronouslyLoaded,
    ) =>
        wasSynchronouslyLoaded || frame != null ? child : fallback;

    final decode = _decodeEdge(context, displaySize);

    if (uri.scheme == 'file') {
      return Image.file(
        File(uri.toFilePath()),
        fit: BoxFit.cover,
        cacheWidth: decode,
        cacheHeight: decode,
        errorBuilder: (_, _, _) => fallback,
        frameBuilder: placeholder,
      );
    }

    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      // 本机那份封面是下载时按 1024 存的,而这里可能只要画 46 ——
      // 不设这一对参数就会把整张图解进内存,切页面时正撞上动画。
      // (网络那份多数已经由服务器按 size 缩过,设了也无害。)
      cacheWidth: decode,
      cacheHeight: decode,
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: placeholder,
    );
  }
}

/// 渐变兜底 —— 「有图但加载失败」也复用它。
class _Fallback extends StatelessWidget {
  const _Fallback({required this.accent});

  final NordicAccent accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: const Alignment(-0.8, -1),
            end: const Alignment(0.8, 1),
            colors: [accent.c1, accent.c2],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: CoverGlowPainter(accent.accent)),
            const GrainOverlay(),
          ],
        ),
      );
}

/// 左上角那团强调色光晕 + 右下角的暗部 —— 原型 `.cover` 的前两层渐变。
/// 艺人色块也复用同一个 painter。
class CoverGlowPainter extends CustomPainter {
  CoverGlowPainter(this.accent, {this.c1});

  final Color accent;

  /// 右下角的暗部色。不传则只画强调色光晕。
  final Color? c1;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.64, -0.84),
          radius: 0.9,
          colors: [
            accent.withValues(alpha: 0.62),
            accent.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    final dark = c1;
    if (dark == null) return;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.76, 0.84),
          radius: 0.85,
          colors: [
            dark.withValues(alpha: 0.9),
            dark.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(CoverGlowPainter old) =>
      old.accent != accent || old.c1 != c1;
}

/// 艺人首字块 —— `.plate`(大,带字)/ `.avatar`(小圆)。
///
/// **Navidrome 多数库没有艺人头像**,所以首字块是常态而非兜底,
/// 不要在这里去拉不存在的图。
class ArtistPlate extends StatelessWidget {
  const ArtistPlate({
    super.key,
    required this.artist,
    this.size = 52,
    this.radius,
    this.circular = false,
  });

  final Artist artist;
  final double size;

  /// 不传则:圆形取 size/2,方块取 18。
  final double? radius;

  final bool circular;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = NordicAccent.derived(artist.id);
    final r = radius ?? (circular ? size / 2 : NordicRadius.md);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: const Alignment(-0.8, -1),
          end: const Alignment(0.7, 1),
          colors: [accent.c1, accent.c2],
        ),
        boxShadow: [
          BoxShadow(
            color: t.rim,
            blurRadius: 0,
            offset: const Offset(0, 1),
            spreadRadius: -0.5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: CoverGlowPainter(accent.accent, c1: accent.c1)),
            Center(
              child: Text(
                artist.initials,
                style: TextStyle(
                  // 字号跟着块走 —— 原型用 container query 的 34cqw,
                  // 这里按同一比例换算。
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.05 * size * 0.35,
                  color: t.mark,
                  shadows: [
                    Shadow(
                      color: t.markShadow,
                      blurRadius: 16,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
            const GrainOverlay(opacity: 0.16),
          ],
        ),
      ),
    );
  }
}

/// 「正在播放」的跳动竖条 —— `.bars`。
///
/// 暂停时**真的停住**(而不是继续空转),与原型
/// `.vinyl.paused { animation-play-state: paused }` 的做法一致。
class PlayingBars extends StatefulWidget {
  const PlayingBars({super.key, this.size = 15, this.playing = true, this.color});

  final double size;
  final bool playing;
  final Color? color;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );

  /// 三根条各自的相位与基准高度,照搬原型的 `:nth-child` 设定。
  static const _phases = [-0.42, -0.90, -0.15];
  static const _base = [0.42, 0.92, 0.62];

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
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
    final color = widget.color ?? context.accent.accent;

    return SizedBox(
      width: 3 * 3 + 2 * 2.5,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // 暂停时停在当前相位上,不再随时间变化。
          final t = widget.playing ? _controller.value : 0.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 2.5 : 0),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: 3,
                      height: widget.size *
                          (_base[i] * 0.45 +
                              0.55 * _wave(t + _phases[i]) * _base[i]),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 原型的 `@keyframes eq`:`scaleY(0.42)` ↔ `scaleY(1)`,正弦往返。
  double _wave(double t) {
    final phase = t % 1.0;
    return (math.sin(phase * 2 * math.pi - math.pi / 2) + 1) / 2;
  }
}