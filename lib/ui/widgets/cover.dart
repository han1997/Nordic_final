import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../data/models.dart';
import '../../data/music_source.dart';
import '../../data/subsonic_repository.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/grain.dart';
import '../../theme/tokens.dart';

/// 装上封面磁盘缓存的配置。在 `main()` 里调一次。
///
/// 默认那份只留 **200** 个对象:库里 400 多张专辑、每张还要按尺寸各存一份,
/// 很容易超过它 —— 于是滚动时刚看过的封面可能已经被淘汰,回头又要重下一遍。
/// 这里放到 2000 个(每张几十 KB,占用顶到几十上百 MB),过期给一个月。
///
/// 用 `defaultCacheManager` 而不是逐处传:封面地址散在十几个调用点,
/// 逐个传的话漏一处就悄悄退回默认的 200。
void configureCoverCache() {
  CachedNetworkImageProvider.defaultCacheManager = CacheManager(
    Config(
      'nordic-covers',
      maxNrOfCacheObjects: 2000,
      stalePeriod: const Duration(days: 30),
    ),
  );
}

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
    this.gaplessPlayback = false,
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

  /// 换图时**留住上一帧**,别先退回渐变占位。
  ///
  /// 默认关着:绝大多数地方的封面从生到死都是同一张,没得可留。开着是给
  /// **播放页**那种「同一个位置、换一首歌就换一张图」的地方 —— 新图解码要几十
  /// 毫秒,不留旧帧的话每次换歌都先闪一下渐变。原型是浏览器画的,本来就不会
  /// 把上一张抹掉(旧图一直画到新图解码完),所以这是**向原型对齐**,不是改设计。
  final bool gaplessPlayback;

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
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_hasArt)
              LayoutBuilder(
                builder: (context, constraints) {
                  // 用**真实约束**当显示边长。网格里的封面是
                  // `width: double.infinity` —— 声明尺寸算不出边长,会一路
                  // 算到 1024 的桶(服务器只给了 512);而布局早就知道答案。
                  final box = constraints.biggest;
                  final measured =
                      box.isFinite && box.shortestSide > 0 ? box.shortestSide : null;
                  return _CoverArt(
                    uri: uri!,
                    coverArtId: coverArtId,
                    displaySize: measured ?? _displayEdge(w, h),
                    fallback: () => _Fallback(accent: NordicAccent.derived(seed)),
                    gaplessPlayback: gaplessPlayback,
                  );
                },
              )
            else
              _Fallback(accent: NordicAccent.derived(seed)),
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
            // 上缘内描边 —— 给封面一道边。
            //
            // 原先这里(与 [ArtistPlate] 那里)写成 `BoxShadow(offset: (0, 1))`,
            // 但 BoxShadow **没有 inset 语义**:画出来是往盒子外面投的一道影,
            // 再被上面那层不透明的封面盖住 —— 等于从来没出现过。
            // `glass.dart` 上缘那道光早就改成了贴边的 1px 实线,这里是同一件事。
            IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 1,
                  child: ColoredBox(color: t.rim),
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
    this.coverArtId,
    this.displaySize,
    this.gaplessPlayback = false,
  });

  final Uri uri;

  /// 兜底那一块(**惰性**):大多数专辑都有真封面,而兜底配色要从种子算一遍
  /// (哈希 + 三次 HSL 换算)—— 每次建封面都先算一份再扔掉,是列表滚动的热路径上
  /// 白花的账。
  final Widget Function() fallback;

  /// 换图时留住上一帧(见 [Cover.gaplessPlayback])。
  final bool gaplessPlayback;

  /// 封面标识 —— 磁盘缓存的键要它(见 [_cacheKey])。
  final String? coverArtId;

  /// 这张图实际要画多大(logical px)。不传就按原图解码。
  final double? displaySize;

  /// 磁盘缓存的键。
  ///
  /// **不能用 URL 本身**:Subsonic 的鉴权每次换一个 salt(见 `SubsonicAuth`),
  /// 同一张封面每次的 URL 都不一样 —— 拿 URL 当键等于永远不命中,缓存目录还会
  /// 攒下一堆同一张图的副本。用「封面 id + 尺寸」当键:换线路(内网 / 公网)
  /// 也照样命中,而不同尺寸各自一份(服务端本来就按 size 缩过,那是不同的图)。
  static String? _cacheKey(String? coverArtId, Uri uri) {
    if (coverArtId == null || coverArtId.isEmpty) return null;
    return 'cover|$coverArtId|${uri.queryParameters['size'] ?? ''}';
  }

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
        wasSynchronouslyLoaded || frame != null ? child : fallback();

    final decode = _decodeEdge(context, displaySize);

    if (uri.scheme == 'file') {
      return Image.file(
        File(uri.toFilePath()),
        fit: BoxFit.cover,
        cacheWidth: decode,
        cacheHeight: decode,
        gaplessPlayback: gaplessPlayback,
        errorBuilder: (_, _, _) => fallback(),
        frameBuilder: placeholder,
      );
    }

    // 走 `cached_network_image` 而不是 `Image.network`:后者只有内存缓存,
    // 冷启动每张封面都要重新下一遍。磁盘缓存也顺带让封面在断网时还看得见。
    return Image(
      image: CachedNetworkImageProvider(
        uri.toString(),
        cacheKey: _cacheKey(coverArtId, uri),
        // 按显示尺寸解码,别把整张 1024 的图解进内存 ——
        // 切页面时动画正跑、解码还在进行,顿挫就出在这种地方。
        maxWidth: decode,
        maxHeight: decode,
      ),
      fit: BoxFit.cover,
      gaplessPlayback: gaplessPlayback,
      errorBuilder: (_, _, _) => fallback(),
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
            // 上缘内描边 —— 与 [Cover] 同一处坑(BoxShadow 没有 inset 语义),
            // 改成贴顶边的 1px 实线。
            IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 1,
                  child: ColoredBox(color: t.rim),
                ),
              ),
            ),
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
          // 暂停时 `_controller` 停在原地(见 [didUpdateWidget] 里的 `stop`),
        // 取它的值就是「停在当前相位上」—— 早先这里写的是 `playing ? value : 0.0`,
        // 于是每次暂停三根条都**跳回**同一副样子(与这句注释说的正好相反)。
        final t = _controller.value;
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
/// 封面地址 —— **本机优先**,取不到就 null(界面退回渐变兜底)。
///
/// 十几处各写一遍 try/catch 是同一份逻辑:没服务器(`repo == null`)、
/// 没有封面 id、或者服务器配置还没接上(拼地址会抛)。收成一处,
/// 免得某处漏了一种情况而整屏报错。
Uri? albumCoverUri(
  SubsonicRepository? repo,
  String? coverArtId, {
  int size = 512,
}) {
  if (repo == null || coverArtId == null || coverArtId.isEmpty) return null;
  try {
    return repo.coverUri(coverArtId, size: size);
  } on MusicSourceException {
    return null;
  }
}
