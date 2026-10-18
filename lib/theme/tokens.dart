import 'package:flutter/material.dart';

/// 设计 token —— `prototype/styles.css` 的 `:root` 逐条翻译。
///
/// 两个主题共用同一份**结构**,差异全部落在这里:深色靠光晕撑层次,
/// 浅色靠留白与描边。强调色不在这里 —— 它由当前封面在运行时提取
/// (见 [NordicAccent]),每张专辑给界面一套自己的气质。
///
/// 命名刻意保留原型里的层级名(`bg1` / `fg2` / `line2`),方便和
/// styles.css 对着看;不要重命名成更有「语义」的名字,那会让两边对不上。
@immutable
class NordicTokens extends ThemeExtension<NordicTokens> {
  const NordicTokens({
    required this.brightness,
    required this.bg,
    required this.bg1,
    required this.bg2,
    required this.bg3,
    required this.fg,
    required this.fg2,
    required this.fg3,
    required this.fg4,
    required this.line,
    required this.line2,
    required this.fill1,
    required this.fill2,
    required this.fill3,
    required this.glow,
    required this.glass,
    required this.glass2,
    required this.glass3,
    required this.glass4,
    required this.blur,
    required this.blurSm,
    required this.glassSaturation,
    required this.glassRim,
    required this.glassShadow,
    required this.scrim,
    required this.shade,
    required this.shade2,
    required this.hi,
    required this.hi2,
    required this.rim,
    required this.depth,
    required this.depth2,
    required this.mark,
    required this.markShadow,
    required this.knob,
    required this.ok,
    required this.warn,
    required this.bad,
    required this.coverPlaceholder1,
    required this.coverPlaceholder2,
  });

  final Brightness brightness;

  // ---- 底色:近黑,带一点冷紫,不是死黑 ----
  final Color bg;
  final Color bg1;
  final Color bg2;
  final Color bg3;

  // ---- 文字 ----
  final Color fg;
  final Color fg2;
  final Color fg3;
  final Color fg4;

  // ---- 分隔与填充 ----
  final Color line;
  final Color line2;
  final Color fill1;
  final Color fill2;
  final Color fill3;

  /// 光晕强度总闸,浅色下压到很低(材质差异的主要杠杆之一)。
  final double glow;

  // ---- 材质:深色靠发光,浅色靠描边 ----
  final Color glass;

  /// 次级玻璃(服务器卡等)。
  final Color glass2;

  /// 面板玻璃:卡片 / 弹层 / 分段控件 —— 底下的内容透得最少,文字最稳。
  final Color glass3;

  /// 更薄的玻璃:输入框 / 筛选胶囊。
  final Color glass4;

  /// 主模糊半径。浅色下要收一半 —— 浅底上大半径会糊成一片。
  final double blur;
  final double blurSm;

  /// 玻璃后的饱和度提升,否则会发灰。
  final double glassSaturation;

  /// 玻璃上缘那道高光 —— 玻璃感的关键,没有它半透明色块只会读成一块灰。
  final Color glassRim;

  /// 玻璃内阴影,做出厚度。
  final Color glassShadow;

  final Color scrim;

  /// 氛围背景压暗起点 / 终点。
  final Color shade;
  final Color shade2;

  /// 封面对角高光 / 第二层高光。
  final Color hi;
  final Color hi2;

  /// 封面上缘内描边。
  final Color rim;

  final Color depth;
  final Color depth2;

  /// 艺人头像 / 唱片首字。
  final Color mark;
  final Color markShadow;

  final Color knob;

  final Color ok;
  final Color warn;
  final Color bad;

  /// 封面纯渐变兜底的默认两端(未被具体条目覆盖时用)。
  final Color coverPlaceholder1;
  final Color coverPlaceholder2;

  bool get isDark => brightness == Brightness.dark;

  /// 深色:近黑冷调底,光晕全开。
  static const dark = NordicTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF07070C),
    bg1: Color(0xFF0C0C14),
    bg2: Color(0xFF13131D),
    bg3: Color(0xFF1C1C28),
    fg: Color(0xFFFBFBFD),
    fg2: Color(0x99FBFBFD), // 251,251,253 @ 0.60
    fg3: Color(0x5EFBFBFD), // @ 0.37
    fg4: Color(0x30FBFBFD), // @ 0.19
    line: Color(0x16FBFBFD), // @ 0.085
    line2: Color(0x26FBFBFD), // @ 0.15
    fill1: Color(0x0DFBFBFD), // @ 0.05
    fill2: Color(0x17FBFBFD), // @ 0.09
    fill3: Color(0x24FBFBFD), // @ 0.14
    glow: 1,
    glass: Color(0xCC181821), // rgba(24,24,33,0.80)
    glass2: Color(0x8C181821), // @ 0.55
    glass3: Color(0x9E14141D), // rgba(20,20,29,0.62)
    glass4: Color(0x6B14141D), // @ 0.42
    blur: 34,
    blurSm: 18,
    glassSaturation: 1.8,
    glassRim: Color(0x1AFFFFFF), // rgba(255,255,255,0.10)
    glassShadow: Color(0x47000000), // rgba(0,0,0,0.28)
    scrim: Color(0xA8030306), // rgba(3,3,6,0.66)
    shade: Color(0x5707070C), // rgba(7,7,12,0.34)
    shade2: Color(0xED07070C), // @ 0.93
    hi: Color(0x38FFFFFF), // rgba(255,255,255,0.22)
    hi2: Color(0x05FFFFFF), // @ 0.02
    rim: Color(0x24FFFFFF), // @ 0.14
    depth: Color(0xE6000000), // rgba(0,0,0,0.90)
    depth2: Color(0xA6000000), // @ 0.65
    mark: Color(0xF2FFFFFF), // rgba(255,255,255,0.95)
    markShadow: Color(0x80000000), // rgba(0,0,0,0.50)
    knob: Color(0xFFFFFFFF),
    ok: Color(0xFF3DDC97),
    warn: Color(0xFFFFC46B),
    bad: Color(0xFFFF6B6B),
    coverPlaceholder1: Color(0xFF2A2F3D),
    coverPlaceholder2: Color(0xFF141821),
  );

  /// 浅色:同一套结构换一副材质。发光几乎关掉,改用留白 + 描边 + 极浅投影。
  static const light = NordicTokens(
    brightness: Brightness.light,
    bg: Color(0xFFF6F6F9),
    bg1: Color(0xFFFFFFFF),
    bg2: Color(0xFFFFFFFF),
    bg3: Color(0xFFEDEDF2),
    fg: Color(0xFF14141C),
    fg2: Color(0xA814141C), // 20,20,28 @ 0.66
    fg3: Color(0x7014141C), // @ 0.44
    fg4: Color(0x3D14141C), // @ 0.24
    line: Color(0x1714141C), // @ 0.09
    line2: Color(0x2914141C), // @ 0.16
    fill1: Color(0x0B14141C), // @ 0.045
    fill2: Color(0x1314141C), // @ 0.075
    fill3: Color(0x1C14141C), // @ 0.11
    glow: 0.14, // 只留一点温度
    glass: Color(0xC7FFFFFF), // rgba(255,255,255,0.78)
    glass2: Color(0x94FFFFFF), // @ 0.58
    glass3: Color(0xA8FFFFFF), // @ 0.66
    glass4: Color(0x80FFFFFF), // @ 0.50
    blur: 20,
    blurSm: 12,
    glassSaturation: 1.5,
    glassRim: Color(0xD9FFFFFF), // rgba(255,255,255,0.85)
    glassShadow: Color(0x1A141628), // rgba(20,22,40,0.10)
    scrim: Color(0x4D1C1C26), // rgba(28,28,38,0.30)
    shade: Color(0x85F6F6F9), // rgba(246,246,249,0.52)
    shade2: Color(0xF2F6F6F9), // @ 0.95
    hi: Color(0x4DFFFFFF), // 浅色下白高光会糊成一片,换成一层薄雾
    hi2: Color(0x0D14141C), // rgba(20,20,28,0.05)
    rim: Color(0xB8FFFFFF), // rgba(255,255,255,0.72)
    depth: Color(0x21141628), // rgba(20,22,40,0.13)
    depth2: Color(0x17141628), // @ 0.09
    mark: Color(0xFFFFFFFF),
    markShadow: Color(0x59141628), // rgba(20,22,40,0.35)
    knob: Color(0xFFFFFFFF),
    ok: Color(0xFF3DDC97),
    warn: Color(0xFFFFC46B),
    bad: Color(0xFFFF6B6B),
    coverPlaceholder1: Color(0xFFE2E5EE),
    coverPlaceholder2: Color(0xFFC9CEDC),
  );

  /// 按亮度取一套 token。**优先用 `context.nordic`**(见 context_ext.dart);
  /// 这个方法只给拿不到 BuildContext 的地方用(如 CustomPainter)。
  static NordicTokens of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 从 [NordicTokens] 取 token 走 `context.nordic`(见 context_ext.dart)。
  /// token 挂在 `ThemeData.extensions` 上,不另建 InheritedWidget ——
  /// 这样 MaterialApp 的深浅切换、系统栏、文字缩放全都照常工作。

  /// 两套 token 之间不做插值 —— 原型的主题切换是**瞬时**换材质
  /// (CSS 变量替换),没有淡入淡出。硬插值会让浅色底上短暂出现
  /// 深色的高光描边,反而脏。所以 lerp 取「过半即切」。
  @override
  NordicTokens copyWith() => this;

  @override
  NordicTokens lerp(ThemeExtension<NordicTokens>? other, double t) {
    if (other is! NordicTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// 圆角 —— `--r-sm` … `--r-full`。
abstract final class NordicRadius {
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 26.0;
  static const xl = 34.0;
  static const full = 999.0;
}

/// 间距 —— `--s1` … `--s8`。
abstract final class NordicSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 26.0;
  static const s7 = 34.0;
  static const s8 = 44.0;
}

/// 字阶 —— `--fs-*`。原型的 font-weight 用得比较重(680–780),
/// 这里保留同样的档位,免得标题看起来比原型软。
abstract final class NordicType {
  static const display = 38.0;
  static const h1 = 30.0;
  static const h2 = 21.0;
  static const h3 = 17.0;
  static const lg = 16.0;
  static const md = 15.0;
  static const sm = 13.0;
  static const xs = 11.0;
}

/// 缓动 —— `--ease`。
abstract final class NordicMotion {
  static const ease = Cubic(0.22, 0.61, 0.36, 1);

  /// 封面共享元素过渡:原型 `::view-transition-group(cover-art)` 为 0.46s。
  static const coverMorph = Duration(milliseconds: 460);

  /// 整页交叉淡出。
  static const pageFade = Duration(milliseconds: 340);

  /// 整屏淡入 —— **切 tab 与播放页进出共用一套**(原型 `.screen` 的 `screen-in`
  /// 与 `::view-transition-new(phone)` 的 `vt-fade-in` 都是 0.22s)。
  ///
  /// 两处写成同一个常量不是凑巧:用户要的就是「进播放页用切 tab 那套」,
  /// 拆成两个数早晚会各自漂走。
  static const screenFade = Duration(milliseconds: 220);

  /// 弹层上滑。
  static const sheetUp = Duration(milliseconds: 300);

  /// 黑胶自转一圈:原型 16s linear。
  static const vinylSpin = Duration(seconds: 16);
}

/// 从 [NordicTokens] 取 token 的便捷入口 —— `context.nordic`(见 context_ext.dart)。