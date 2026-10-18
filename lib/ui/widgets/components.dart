import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';

/// 按下去缩一点 —— 原型里 `.icon-btn` / `.btn` / `.play-btn` 都带
/// `transform: scale(0.92~0.975)`。
///
/// 移植时漏了这一层:全应用的可点元素差不多都是裸 [GestureDetector],
/// **按下去屏幕上什么都不动**,直到抬起手才发生跳转 —— 手感上就是「这机器慢」。
/// 这里收成一处,免得二十来个调用点各写一遍(写漏一处就是又一处没反应)。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.behavior = HitTestBehavior.opaque,
    this.pressedDecoration,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// 按压时的缩放。大块面(卡片 / 整行)用 0.97 就够 ——
  /// 按原型那颗 0.92 缩在整屏宽的卡片上会晃眼。
  final double scale;

  final HitTestBehavior behavior;

  /// 换成点按时的底色,不走缩放。
  ///
  /// 整行 / 整条那种大面积用这个:原型的 `.row:hover{background:var(--fill-1)}`、
  /// `.menu-item:hover` 都是这个路子 —— 一条 64px 高的行整体缩一下会晃眼,
  /// 而「底下亮了一层」既明显又不动布局。
  final Decoration? pressedDecoration;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (!mounted || _down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    // 不可点就完全走原样 —— 不给一个「按得下去但没反应」的假反馈。
    if (widget.onTap == null) return widget.child;

    final decoration = widget.pressedDecoration;
    if (decoration != null) {
      return GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        child: DecoratedBox(
          decoration: _down ? decoration : const BoxDecoration(),
          child: widget.child,
        ),
      );
    }

    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        // 按下要立刻、回弹可以慢一点 —— 与原型 `0.14s var(--ease)` 一致。
        duration: Duration(milliseconds: _down ? 70 : 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 主按钮 —— `.btn.primary`,实心强调色,整宽。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.fillMaxWidth = true,
    this.height = 52,
    this.emphasis = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool fillMaxWidth;
  final double height;

  /// false 时用填充色而非强调色渐变 —— 列表里的次要动作。
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent;
    final enabled = onPressed != null;

    final child = Row(
      mainAxisSize: fillMaxWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: emphasis ? t.bg : t.fg),
          const SizedBox(width: 9),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: emphasis ? t.bg : t.fg,
                ),
          ),
        ),
      ],
    );

    return Opacity(
      // 不可用时压暗而不是隐藏 —— 按钮还在原位,用户知道它存在。
      opacity: enabled ? 1 : 0.45,
      child: Pressable(
        onTap: onPressed,
        scale: 0.975,
        child: Container(
          height: height,
          width: fillMaxWidth ? double.infinity : null,
          padding: fillMaxWidth ? null : const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NordicRadius.full),
            gradient: emphasis
                ? LinearGradient(
                    begin: const Alignment(-0.7, -1),
                    end: const Alignment(0.7, 1),
                    colors: [
                      Color.lerp(accent.accent, Colors.white, 0.10)!,
                      accent.accent,
                    ],
                  )
                : null,
            color: emphasis ? null : t.fill2,
            boxShadow: emphasis
                ? [
                    BoxShadow(
                      color: accent.accent.withValues(alpha: 0.75 * t.glow),
                      blurRadius: 34,
                      offset: const Offset(0, 16),
                      spreadRadius: -14,
                    ),
                  ]
                : null,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// 虚边按钮 —— `.btn.ghost`,用于「添加线路」这类补充动作。
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 48,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Pressable(
      onTap: onPressed,
      scale: 0.975,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NordicRadius.full),
          border: Border.all(color: t.line2, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: t.fg2),
              const SizedBox(width: 9),
            ],
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: t.fg2, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏上的小药丸按钮 —— `.pill-btn`(如「保存」「创建」)。
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.solid = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;

  /// 实心强调色 —— 表单的主提交动作。
  final bool solid;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent;
    final enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Pressable(
        onTap: onPressed,
        scale: 0.97,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: solid ? accent.accent : t.fill2,
            borderRadius: BorderRadius.circular(NordicRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: solid ? t.bg : t.fg2),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: solid ? t.bg : t.fg2,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 点空白处收起软键盘。
///
/// 为什么要它:`TextField.onTapOutside` 的**默认回退在触屏上什么都不做**
/// (桌面才收起),所以键盘会一直杵着把界面挤掉半屏,用户只能去按系统返回键。
/// 包一层整屏内容就能接住落在空白处的点击;落在控件上的点击仍归控件 ——
/// 手势竞技场里更深的那一层先赢,这里只吃「没人要」的那些。
///
/// 主壳([NordicShell])与沉浸页外壳([ImmersiveScaffold])各包了一次,
/// 于是全应用只有这两处,页面自己不用操心。
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      );
}

/// 「选中 / 开着」的那层底色。
///
/// 标签栏的选中胶囊与传输控制上的随机 / 循环共用这一档 —— 两处本就说的
/// 是同一件事(这个位置现在是活的),分头写两个数字迟早会漂开。
Color selectFill(Color accent) => accent.withValues(alpha: 0.17);

/// 圆形图标按钮 —— `.icon-btn`,可带一层淡填充(`halo`)。
class IconButtonRound extends StatelessWidget {
  const IconButtonRound({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 40,
    this.iconSize = 22,
    this.color,
    this.halo = false,
    this.background,
    this.quiet = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;

  /// 带一层极淡的填充底色 —— 详情页动作排上的那几个圆按钮。
  final bool halo;

  /// 指定底色,盖过 [halo] 的那档默认填充。
  ///
  /// 给「开着 / 关着」这类**要一眼看出来**的开关键用(传输控制上的随机与循环):
  /// 图标本身在两态之间只是颜色不同,幅度太小,真机上读不出来。
  /// 取值与标签栏的选中胶囊同源(强调色 17%),两处选中态才是一套说法。
  final Color? background;

  /// 次级图标,颜色退一档。
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Pressable(
      // 图标键照原型的 `.icon-btn:active` 缩 0.92 —— 比按钮明显一档。
      onTap: onPressed,
      scale: 0.92,
      child: Opacity(
        // 不可点就压暗。**代表「到头了」的那两颗键**(上一首 / 下一首)全靠这一个
        // 记号 —— 不压暗的话它跟能点的一模一样,点下去什么也不发生,
        // 读起来就是「这个键坏了」。
        opacity: onPressed == null ? 0.35 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: background ?? (halo ? t.fill1 : null),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: color ?? (quiet ? t.fg2 : t.fg),
          ),
        ),
      ),
    );
  }
}

/// 章节标题 —— `.section`:标题 + 计数 + 右侧可放动作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.padding,
  });

  final String title;

  /// 计数小字,如「529 首」。
  final String? count;

  /// 右侧动作(「重新测速」这类胶囊)。
  final Widget? trailing;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            NordicSpace.s5,
            NordicSpace.s6,
            NordicSpace.s5,
            NordicSpace.s3,
          ),
      // 外层**按中线对齐**。右侧动作(测速胶囊 / 排序键)不是文字,不该跟着基线
      // 走 —— 原型里这两条规则写得很清楚:`.section { align-items: baseline }`
      // 管文字,`.section .chip, .section .pill-btn { align-self: center }` 与
      // `.sort-btn { align-self: center }` 把非文字的右侧动作摘出去。
      //
      // 摘不出去会怎样:基线行按 `maxBaselineDistance - childBaseline` 摆子节点,
      // 而嵌套 flex 报回来的基线**不含它子节点的居中偏移** —— 30px 的胶囊于是
      // 报一个靠上的浅基线,整颗被压到标题下面几像素(真机上报的那一版)。
      child: Row(
        children: [
          // 标题与计数是一对**文字**,它俩之间才要基线对齐。
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (count != null) ...[
                const SizedBox(width: 10),
                Text(
                  count!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.fg4, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 排序入口 —— 章节头右侧那颗安静的文字按钮(带当前口径,如「按艺人」)。
///
/// **不做成胶囊**:它不是状态显示,而章节头左边已经有一处计数小字,
/// 再摆一颗胶囊会把这一行压重。(档位那颗之所以是胶囊,是因为它同时报着码率。)
/// 与原型 `.sort-btn` 同构:图标 + 文字,只在悬停时给一层底。
class SortButton extends StatelessWidget {
  const SortButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;

  /// 正在按新口径重拉(专辑那一栏要打服务器)—— 转个圈,不然点了像没反应。
  final bool busy;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Pressable(
      onTap: busy ? null : onTap,
      scale: 0.97,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: t.fg3,
                ),
              )
            else
              Icon(Icons.swap_vert, size: 15, color: t.fg3),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: t.fg3,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 筛选 / 状态胶囊 —— `.chip`。
class NordicChip extends StatelessWidget {
  const NordicChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.height = 34,
    this.color,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final double height;

  /// 覆盖强调色(如「重新测速」用中性色)。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = color ?? context.accent.accent;

    if (selected) {
      return Pressable(
        onTap: onTap,
        scale: 0.96,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(NordicRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: t.bg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: t.bg,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    // 未选中:薄玻璃底 + 发丝边,能透出背景。
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: SizedBox(
        height: height,
        child: NordicGlass(
          panel: NordicGlassPanel.thin,
          borderRadius: BorderRadius.circular(NordicRadius.full),
          // **必须显式居中**。玻璃底是个 `Stack`,它默认 `alignment` 是
          // `topStart`、`fit` 是 `loose` —— 子节点按**顶对齐**摆。而定高 30 的
          // 盒子里内容只有 ~15 高,不居中就会贴在上沿(真机上报的
          // 「测速两个字没对齐」)。选中态走的是不透明的定高 `Container`,
          // 那种盒子会把内容撑满、天然居中 —— 两边不一致的话,点一下
          // 「测速」→「测速中」字会往下跳一截。
          // 原型 `.chip { display:inline-flex; align-items:center }` 说的就是这件事。
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: t.fg3),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600, color: t.fg2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分段控件 —— `.segmented`。选中块做成实心玻璃片浮在轨道上。
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelOf,
    this.height = 36,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelOf;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return SizedBox(
      height: height + 8,
      child: NordicGlass(
        panel: NordicGlassPanel.thin,
        borderRadius: BorderRadius.circular(NordicRadius.full),
        border: false,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (final option in options)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(option),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: NordicMotion.ease,
                      height: height,
                      decoration: BoxDecoration(
                        color: option == value ? t.fill3 : Colors.transparent,
                        borderRadius: BorderRadius.circular(NordicRadius.full),
                      ),
                      child: Center(
                        child: Text(
                          labelOf?.call(option) ?? '$option',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: option == value ? t.fg : t.fg3,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 勾选圆点 —— `.tick`。线路 / 质量 / 接入类型三处共用。
class NordicTick extends StatelessWidget {
  const NordicTick({super.key, required this.selected, this.size = 24});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? accent : Colors.transparent,
        border: selected ? null : Border.all(color: t.line2, width: 1.6),
      ),
      child: selected
          ? Icon(Icons.check, size: size * 0.58, color: t.bg)
          : null,
    );
  }
}

/// 开关 —— `.switch`。长得像开关,不是圆形勾选。
class NordicSwitch extends StatelessWidget {
  const NordicSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent.accent;

    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: NordicMotion.ease,
        width: 46,
        height: 28,
        decoration: BoxDecoration(
          color: value ? accent : t.fill3,
          borderRadius: BorderRadius.circular(NordicRadius.full),
          border: Border.all(color: value ? accent : t.line),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: NordicMotion.ease,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 进度细线 —— `.prog-line`。坞底与「继续收听」卡各一条。
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.progress, this.height = 3});

  /// 0–1。
  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return ClipRRect(
      borderRadius: BorderRadius.circular(NordicRadius.full),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: t.fill3)),
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: ColoredBox(color: context.accent.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置项左侧的小图标块 —— `.set-icon`。
class SettingIcon extends StatelessWidget {
  const SettingIcon({super.key, required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: t.fill2,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 18, color: color ?? context.accentSafe),
    );
  }
}

/// 「原型只带了这几首」这类列表末尾说明 —— `.list-note`。
/// 放在列表**末尾**而不是顶部:先把内容给出来,再解释为什么少,
/// 读起来不像错误提示。
class ListNote extends StatelessWidget {
  const ListNote(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ??
            const EdgeInsets.fromLTRB(
              NordicSpace.s5,
              NordicSpace.s4,
              NordicSpace.s5,
              0,
            ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.7,
                color: context.nordic.fg3,
              ),
        ),
      );
}

/// 空态 —— `.empty`。**只在「确实为空」时用**;
/// 加载中与出错时另走 [LoadingState] / [ErrorState](见「不造假空态」约定)。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.detail,
    this.topPadding = 120,
    this.action,
  });

  final String title;
  final String? detail;
  final double topPadding;

  /// 空态底下那颗「接下来该做什么」的按钮。
  ///
  /// 只写一句「到设置里填地址」等于把活交给用户去找 —— 空态说的是「这儿没有」,
  /// 那就得顺手给出**怎么让它有**。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Padding(
      padding: EdgeInsets.fromLTRB(NordicSpace.s6, topPadding, NordicSpace.s6, 72),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: t.fg2,
                ),
          ),
          if (detail != null) ...[
            const SizedBox(height: NordicSpace.s3),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: NordicSpace.s5),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 底部弹层 —— `.sheet`。玻璃面 + 顶部把手 + 上滑动画。
/// 线路信号条 —— `.sig`。四根递增的条,亮的根数表示延迟档位。
///
/// 原型里这几个值是手写的 mock(12ms → 4 根、86ms → 3 根),这里按实测延迟
/// 折算 —— 界面上要的是「一眼看出哪条快」,精确数字就在旁边。
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.bars, this.height = 22});

  /// 亮几根,0–4。
  final int bars;
  final double height;

  /// 四根条的高度比例 —— 照搬原型的 `:nth-child`。
  static const _fractions = [0.30, 0.50, 0.72, 1.0];

  /// 延迟 → 根数。
  ///
  /// 门槛按「局域网 / 公网」的实感定:30ms 以内是内网直连,80ms 以内是就近
  /// 的公网,200ms 还可用,再往上就是「能连但不好用」。没测出延迟(线路不通、
  /// 或还没测)不亮 —— 不亮比亮错一根强。
  static int forLatency(Duration? latency) {
    if (latency == null) return 0;
    final ms = latency.inMilliseconds;
    if (ms <= 30) return 4;
    if (ms <= 80) return 3;
    if (ms <= 200) return 2;
    if (ms <= 600) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent.accent;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _fractions.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Container(
              width: 4,
              height: height * _fractions[i],
              decoration: BoxDecoration(
                color: i < bars ? accent : t.fg4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 底部纸里的一行动作 —— `.menu-item`。
///
/// 专辑页、艺人页、播放页、歌单页的「⋯」背后铺的都是这个。
/// 四个页面各抄一份的日子到此为止:它们是同一件东西,样式该只有一处。
class NordicMenuRow extends StatelessWidget {
  const NordicMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Pressable(
      onTap: onTap,
      // 原型的 `.menu-item:hover { background: var(--fill-1) }`。
      pressedDecoration: BoxDecoration(color: t.fill1),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NordicSpace.s5, vertical: NordicSpace.s4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: t.fg2),
            const SizedBox(width: NordicSpace.s4),
            // Expanded 是给长标签(「下载到本机(FLAC)」这种)留的余地 ——
            // 窄屏上宁可折行,也不要溢出成黄黑警示带。
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

class NordicSheet extends StatelessWidget {
  const NordicSheet({super.key, required this.child, this.title, this.subtitle});

  final Widget child;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        // 弹层也是玻璃 —— 底下的封面透上来一层颜色,弹层才不像贴上去的一块板
        // (原型 `.sheet` 就是带 backdrop-filter 的)。原先这里是纯色的
        // DecoratedBox,于是每一张底部纸都是死板的一块。
        child: NordicGlass(
          panel: NordicGlassPanel.panel,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(NordicRadius.xl),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 11),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.fill3,
                  borderRadius: BorderRadius.circular(NordicRadius.full),
                ),
              ),
              const SizedBox(height: 6),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NordicSpace.s5,
                    NordicSpace.s3,
                    NordicSpace.s5,
                    NordicSpace.s2,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          title!,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontSize: 21),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            subtitle!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              Flexible(child: child),
              SizedBox(height: MediaQuery.paddingOf(context).bottom + NordicSpace.s4),
            ],
          ),
        ),
      ),
    );
  }
}

/// 揭开一张底部纸 —— **所有弹层都从这里走**。
///
/// 两个参数收在一处,别在调用点各写一遍(写漏一处就是一层多余的黑):
///
/// - `barrierColor: Colors.transparent`:框架默认那层 `Colors.black54` 会与
///   [NordicScrim] 叠成**两层黑**,而且它是一整块纯黑、不模糊 —— 弹层背后发闷
///   就是它。透明之后 barrier 仍然拦点击、仍然点外面就关
///   (`bottom_sheet.dart` 里 `barrierColor.a == 0` 走的是不绘制的那条分支)。
/// - `isScrollControlled: true`:不写的话框架只给内容盒子**屏幕高度的 9/16**,
///   而 [NordicScrim] 就是 sheet 的内容 → 它只能盖住下半屏,上半屏剩一块没有
///   模糊的纯黑。顺带:[NordicSheet] 自己那句 86% 上限也才真的生效
///   (原型 `.sheet` 是 `max-height: 86%`)。
Future<T?> showNordicSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) =>
    showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      builder: builder,
    );

/// 弹层遮罩 —— `.sheet-scrim`。
///
/// **就这一层**:原型的 `.sheet-scrim`(66% 压暗 + `blur(6px)`),铺满整屏。
/// 框架自带的那层黑由 [showNordicSheet] 关掉 —— 两层叠起来是 84% 黑。
class NordicScrim extends StatelessWidget {
  const NordicScrim({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;

    final layer = GestureDetector(
      onTap: onTap,
      // 遮罩也轻轻糊一下(原型 `blur(6px)`)—— 弹层后面的内容
      // 从「被压暗」变成「退到后面」,层次才分得开。
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: ColoredBox(color: t.scrim),
      ),
    );

    // 路由的入场过渡是把**整块内容**从屏幕下方挪上来(不是 `SlideTransition`,
    // 是 `_BottomSheetLayout` 按 `animationValue` 给整块定位)。蒙板在路由里就会
    // 跟着走:整屏的暗层从下往上「擦」,上半屏最后才暗下来。
    //
    // 补一个等量的反向位移抵消掉,蒙板就成了原地淡入。位移量取 LayoutBuilder 的
    // `maxHeight` —— 它与路由定位用的那个高度是同一个(内容铺满整屏),能精确抵消。
    // 若哪天真机上反而看到位移,把这一层去掉就退回「跟着纸一起上滑」,不会坏。
    final animation = ModalRoute.of(context)?.animation;

    return Stack(
      children: [
        Positioned.fill(
          child: animation == null
              ? layer
              : LayoutBuilder(
                  builder: (context, constraints) => AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(
                        0,
                        (animation.value - 1) * constraints.maxHeight,
                      ),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: layer,
                  ),
                ),
        ),
        child,
      ],
    );
  }
}