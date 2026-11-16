import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/server_config.dart';

/// 六条动效 —— **与 `prototype/app.js` 的 `FX_ITEMS` 逐字一致**。
///
/// `id` 是同一个词在四个地方的名字:原型的 `<html data-fx>`、样式的
/// `[data-fx~="id"]`、落盘时写进 [ConfigStore] 的那个词、以及这里的枚举名。
/// `name` / `where` / `short` 就是设置页那一行显示的三句(标题、旁边那一行)。
///
/// 改名字只在这张表里改一处 —— `test/ui/prototype_parity_test.dart` 会拿原型
/// 那张表逐条比 `id`、`name`、`where`、`short`,对不上就红。
enum FxId {
  stagger(
    id: 'stagger',
    name: '列表错开入场',
    where: '进入任何列表 / 首页',
    short: '每块内容依次浮起 6px',
  ),
  tabx(
    id: 'tabx',
    name: '切 tab 横向推移',
    where: '首页 / 音乐库 / 设置',
    short: '两屏一前一后错开 16px',
  ),
  spring(
    id: 'spring',
    name: '弹层回弹',
    where: '所有底部面板',
    short: '升上来轻过一点再落定',
  ),
  press(
    id: 'press',
    name: '按压回弹',
    where: '歌曲行 / 专辑格 / 歌单',
    short: '按下缩到 0.97，松手弹回',
  ),
  dock(
    id: 'dock',
    name: '托盘落位',
    where: '带底部托盘的每一屏',
    short: '播放条从下方 22px 升上来',
  ),
  lyric(
    id: 'lyric',
    name: '歌词换行浮起',
    where: '歌词页',
    short: '新一句从下方 4px 浮起并亮起',
  );

  const FxId({
    required this.id,
    required this.name,
    required this.where,
    required this.short,
  });

  /// 落盘 / 原型 `data-fx` 上用的那个词(与枚举名相同,但**分开写**:
  /// 枚举名是 Dart 的事,这个字符串是与原型对齐的事)。
  final String id;

  final String name;

  /// 它**什么时候**会出现 —— 判断要不要留一条,先看这一句。
  final String where;

  final String short;
}

/// 三档预设 —— 与原型 `FX_PRESETS` 同一张表(`all` / `rec` / `none`)。
///
/// 预设不是「另一套动效」,只是这六条的一次取值。
enum FxPreset {
  all('全部开启'),
  rec('推荐组合'),
  none('全部关闭');

  const FxPreset(this.label);

  final String label;

  bool allows(FxId id) => switch (this) {
        FxPreset.all => true,
        FxPreset.none => false,
        // 推荐组合留下的四条:错开与回弹承担「内容在哪儿」的读法;
        // 横向推移与托盘落位每次换屏都出现,留久了容易读成噪音(原型同一条口径)。
        FxPreset.rec => id != FxId.tabx && id != FxId.dock,
      };
}

/// 六条动效的数值 —— 与 `prototype/styles.css` 的动效节一一对应。
///
/// 这里只放**数**:距离、时长、起始不透明度。改一条动效的手感先改这儿,
/// 别在实现里各写一遍字面量。
abstract final class NordicFx {
  /// 「列表错开入场」:每块内容 6px 浮起,0.34s 演完。
  static const stagger = Duration(milliseconds: 340);
  static const staggerDistance = 6.0;

  /// 一格 24ms,第 11 块起一起落位(原型 `:nth-child(n+11)`)——
  /// 逐格无限延后的话,长列表末尾要等一秒才出现,反而像卡住。
  static const staggerStep = Duration(milliseconds: 24);
  static const staggerMaxStep = 10;

  static Duration staggerDelay(int index) =>
      staggerStep * math.min(index < 0 ? 0 : index, staggerMaxStep);

  /// 「切 tab 横向推移」:两屏一前一后错开 16px。
  static const tabShift = 16.0;
  static const tabSlide = Duration(milliseconds: 240);

  /// 「弹层回弹」:0.46s 升起,一半多一点时冲过落点 1.4%,再落定。
  static const sheet = Duration(milliseconds: 460);
  static const sheetOvershoot = 0.014;
  static const sheetPeak = 0.66;

  /// 「按压回弹」:按下缩到 0.97(行 0.985),0.16s 一来一回。
  static const press = Duration(milliseconds: 160);

  /// 「托盘落位」:播放条从下方 22px 升上来,0.42s。
  static const dock = Duration(milliseconds: 420);
  static const dockDistance = 22.0;

  /// 「歌词换行浮起」:新一句从下方 4px 浮起,从 0.35 的暗到全亮,0.42s。
  static const lyric = Duration(milliseconds: 420);
  static const lyricDistance = 4.0;
  static const lyricOpacity = 0.35;
}

/// 弹层升起那条曲线(*「弹层回弹」开着时*走它):[NordicFx.sheetPeak] 处
/// 冲过落点 [NordicFx.sheetOvershoot] 再落定 —— 原型 `fx-sheet-spring` 的
/// `66% { translateY(-1.4%) }`。
///
/// **它的值会超过 1**,这不是笔误:框架的 `_BottomSheetLayout` 按
/// `size.height - childSize.height * animationValue` 定位整块内容,超过 1 就是
/// 往上多走一点。[NordicScrim] 那层抵消位移的补偿按**同一条**曲线求值,
/// 所以两边一起冲、一起落定,蒙版照旧原地淡入(见 `sheet_scrim_test.dart`)。
class NordicSpringCurve extends Curve {
  const NordicSpringCurve();

  /// 头一段走 `easeOutCubic` 而不是直线:冲过落点那一下才像有惯性;
  /// 尾巴一段线性收回,落定时不再有第二次过冲。
  @override
  double transformInternal(double t) {
    if (t >= 1) return 1;
    if (t <= 0) return 0;
    if (t <= NordicFx.sheetPeak) {
      return Curves.easeOutCubic.transform(t / NordicFx.sheetPeak) *
          (1 + NordicFx.sheetOvershoot);
    }
    return 1 +
        NordicFx.sheetOvershoot * (1 - (t - NordicFx.sheetPeak) / (1 - NordicFx.sheetPeak));
  }
}

/// 动效开关 —— 六条各一个 bool,三档预设是它的三个取值。
///
/// **存的是「关掉的那几条」**,不是「开着的那几条」:以后往 [FxId] 里加一条时,
/// 老用户拿到的是「开」(与原型默认全开一致),而不是莫名其妙关着。
/// 盘上写的是 id、空格分隔(`stagger tabx`),与原型 `data-fx` 上那串同构。
class MotionPrefs extends ChangeNotifier {
  MotionPrefs({Set<FxId> off = const {}, this.store, this.readOnly = false})
      : _off = {...off};

  /// 从盘上读一份([ConfigStore.loadFxOff])。
  factory MotionPrefs.fromStore(ConfigStore store) =>
      MotionPrefs(off: parseFxIds(store.loadFxOff()), store: store);

  /// **没挂 [MotionScope] 时用的那一份**:全开、写不进去。
  ///
  /// 组件测试与只测布局的那些用例没有理由知道动效开关这回事,它们照旧拿到
  /// 「全开」;但它们会点到开关 —— 写进一份跨用例共享的对象会让用例互相污染,
  /// 所以这一份是只读的(真要在用例里开关动效,自己套一个 [MotionScope])。
  static final MotionPrefs fallback = MotionPrefs(readOnly: true);

  /// 落盘用。为空时改动只在内存里(用例里就是这么用的)。
  final ConfigStore? store;

  /// 只读:没挂 [MotionScope] 时用的那一份(见 [fallback])。
  final bool readOnly;

  Set<FxId> _off;

  /// 能不能写。为假时 [set] / [applyPreset] 是空操作(见 [fallback])。
  bool get writable => !readOnly;

  bool isOn(FxId id) => !_off.contains(id);

  /// 当前这份正好等于哪一档预设;一条都不像就返回 null ——
  /// 设置页据此不高亮任何一档(逐条改过之后就是这种状态)。
  FxPreset? get preset {
    for (final preset in FxPreset.values) {
      if (FxId.values.every((id) => preset.allows(id) == isOn(id))) {
        return preset;
      }
    }
    return null;
  }

  void set(FxId id, bool on) {
    if (readOnly || isOn(id) == on) return;
    final next = {..._off};
    if (on) {
      next.remove(id);
    } else {
      next.add(id);
    }
    _off = next;
    _persist();
    notifyListeners();
  }

  void applyPreset(FxPreset preset) {
    if (readOnly) return;
    final next = {
      for (final id in FxId.values)
        if (!preset.allows(id)) id,
    };
    if (setEquals(next, _off)) return;
    _off = next;
    _persist();
    notifyListeners();
  }

  void _persist() {
    // 按 [FxId] 的声明序拼,顺序稳定 —— 同一个集合只会写出一种字符串。
    unawaited(
      store?.saveFxOff(
            FxId.values.where(_off.contains).map((f) => f.id).join(' '),
          ) ??
          Future<void>.value(),
    );
  }

  /// 盘上那串 id → 集合。认不出的词直接丢掉(旧版本写下的、手改过的)。
  static Set<FxId> parseFxIds(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    final words = raw.split(RegExp(r'\s+')).toSet();
    return {
      for (final id in FxId.values)
        if (words.contains(id.id)) id,
    };
  }
}

/// 把开关挂进树 —— 全应用一处([main.dart] 里包住 `NordicApp`)。
///
/// 用 [InheritedNotifier] 而不是 `Provider`:它**不要求在场**。
/// [Pressable]、弹层、坞、歌词行这些深处组件都要问一句「这一条开着吗」,
/// 而几十个既有用例是单独 pump 它们的 —— 少一层 provider 就整片崩。
class MotionScope extends InheritedNotifier<MotionPrefs> {
  const MotionScope({
    super.key,
    required MotionPrefs prefs,
    required super.child,
  }) : super(notifier: prefs);

  /// 取开关,**建立依赖**:开关变了这一块要重建。
  static MotionPrefs of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>()?.notifier ??
      MotionPrefs.fallback;

  /// 取开关,**不建立依赖** —— 事件回调(点一下、切 tab)里用这个。
  static MotionPrefs read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MotionScope>()?.notifier ??
      MotionPrefs.fallback;
}
