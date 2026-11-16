import 'package:flutter/material.dart';

import '../../theme/fx.dart';
import '../../theme/tokens.dart';

/// 一屏「依次浮起」的时间线 —— 「列表错开入场」那一整块共用它一根。
///
/// **一根时间线,不是每格一根**:后者在懒加载的网格里会变成「滚到哪儿,哪儿
/// 就浮一下」—— 一直滑就一直浮,读起来像在抖。挂在这一屏上的时间线只演一次
/// (`340 + 24×10` ms),之后挂载的格子(滚下去才建出来的那些)拿到的进度已经
/// 到头,于是**直接以静止态出现**。
///
/// 与原型那一段是同一件事:`.screen.fx-stagger .scroll > *` 只在那一次换屏里
/// 各得一个延迟,之后重绘不再重演(第四十三轮那条「整屏淡入只演一次」同理)。
class FxStagger extends StatefulWidget {
  const FxStagger({super.key, required this.child});

  final Widget child;

  @override
  State<FxStagger> createState() => _FxStaggerState();
}

class _FxStaggerState extends State<FxStagger>
    with SingleTickerProviderStateMixin {
  /// 一格 24ms,十格封顶,外加演完一块的 340ms。
  static final Duration _total = NordicFx.stagger +
      NordicFx.staggerDelay(NordicFx.staggerMaxStep);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _total,
  );

  bool _on = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = MotionScope.of(context).isOn(FxId.stagger);
    if (_initialized && on == _on) return;
    _initialized = true;
    _on = on;
    // 刚打开这一条(或第一次进来)就从头演一次 —— 用户刚点的开关,
    // 该当场看见它。关掉时停在头上,免得再打开时从半截开始。
    if (on) {
      _c.forward(from: 0);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StaggerTimeline(
      progress: _on ? _c : null,
      child: widget.child,
    );
  }
}

/// 把这一屏的时间线递下去。`progress` 为空 = 这一条动效关着(各格原样)。
class _StaggerTimeline extends InheritedWidget {
  const _StaggerTimeline({required this.progress, required super.child});

  final Animation<double>? progress;

  static Animation<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_StaggerTimeline>()
      ?.progress;

  @override
  bool updateShouldNotify(_StaggerTimeline old) => progress != old.progress;
}

/// 「列表错开入场」里的一格。
///
/// [index] 是它在这一屏里的位置:第 i 格等 `min(i, 10) × 24ms` 起,再花 340ms
/// 从下方 6px 浮到原位(原型 `fx-rise`)。没有 [FxStagger] 包着的地方(单独
/// 推开的二级页)只是原样显示 —— 不为了一格内容到处铺时间线。
class FxRise extends StatelessWidget {
  const FxRise({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final progress = _StaggerTimeline.maybeOf(context);
    if (progress == null) return child;

    final delay = NordicFx.staggerDelay(index).inMicroseconds;
    final span = NordicFx.stagger.inMicroseconds;
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final elapsed = progress.value * (delay + span);
        final raw = ((elapsed - delay) / span).clamp(0.0, 1.0);
        final p = NordicMotion.ease.transform(raw);
        if (p >= 1) return child!;
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, NordicFx.staggerDistance * (1 - p)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 「托盘落位」—— 播放坞从下方 22px 升上来(原型 `fx-dock-in`)。
///
/// 与错开入场不同,这一条**挂在常驻区上**,切一次 tab 就是「换了一屏」,
/// 所以 `replay` 跟着 tab 走:变了就再演一次。
class FxDockRise extends StatefulWidget {
  const FxDockRise({super.key, required this.replay, required this.child});

  /// 变了就重演 —— 给「当前是哪个 tab」。
  final Object? replay;

  final Widget child;

  @override
  State<FxDockRise> createState() => _FxDockRiseState();
}

class _FxDockRiseState extends State<FxDockRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: NordicFx.dock);

  bool _on = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = MotionScope.of(context).isOn(FxId.dock);
    if (_initialized && on == _on) return;
    _initialized = true;
    _on = on;
    if (on) {
      _c.forward(from: 0);
    } else {
      // 关掉就停在落点:建出来、切 tab 都不动一下。
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void didUpdateWidget(FxDockRise old) {
    super.didUpdateWidget(old);
    if (_on && widget.replay != old.replay) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_on) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final p = NordicMotion.ease.transform(_c.value);
        if (p >= 1) return child!;
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, NordicFx.dockDistance * (1 - p)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 「歌词换行浮起」—— 新亮起来的那一句从下方 4px 浮起、从 0.35 的暗亮到全亮
/// (原型 `fx-lyric-in`,挂在 `.lyric-line.on .txt` 上)。
///
/// **只在新亮的那一下演**:歌词位置每秒跳好几次,跟着进度重演就是一直在抖。
/// 所以判据是 [active] 由假转真,不是「这一行是不是亮的」—— 后者会在每次
/// 重建时重来一遍。
class FxLyricRise extends StatefulWidget {
  const FxLyricRise({super.key, required this.active, required this.child});

  /// 这一行此刻是不是「正在被读到」的那一句。
  final bool active;

  final Widget child;

  @override
  State<FxLyricRise> createState() => _FxLyricRiseState();
}

class _FxLyricRiseState extends State<FxLyricRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: NordicFx.lyric, value: 1);

  bool _on = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = MotionScope.of(context).isOn(FxId.lyric);
    if (_initialized && on == _on) return;
    _initialized = true;
    _on = on;
    if (on) {
      if (widget.active) _c.forward(from: 0);
    } else {
      // 关掉就停在落点(也在原位),不留下半截。
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void didUpdateWidget(FxLyricRise old) {
    super.didUpdateWidget(old);
    if (_on && widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_on) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final p = NordicMotion.ease.transform(_c.value);
        if (p >= 1) return child!;
        return Opacity(
          opacity: NordicFx.lyricOpacity +
              (1 - NordicFx.lyricOpacity) * p,
          child: Transform.translate(
            offset: Offset(0, NordicFx.lyricDistance * (1 - p)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
