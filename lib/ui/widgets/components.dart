import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';

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
      child: GestureDetector(
        onTap: onPressed,
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
    return GestureDetector(
      onTap: onPressed,
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
              const SizedBox(width: 8),
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
      child: GestureDetector(
        onTap: onPressed,
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
                const SizedBox(width: 6),
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
    this.quiet = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;

  /// 带一层极淡的填充底色 —— 详情页动作排上的那几个圆按钮。
  final bool halo;

  /// 次级图标,颜色退一档。
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: halo ? t.fill1 : null,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: color ?? (quiet ? t.fg2 : t.fg),
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
      child: Row(
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
          const Spacer(),
          if (trailing != null) trailing!,
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
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
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
      return GestureDetector(
        onTap: onTap,
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
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: NordicGlass(
          panel: NordicGlassPanel.thin,
          borderRadius: BorderRadius.circular(NordicRadius.full),
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
  const EmptyState({super.key, required this.title, this.detail, this.topPadding = 120});

  final String title;
  final String? detail;
  final double topPadding;

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
    return InkWell(
      onTap: onTap,
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

/// 弹层遮罩 —— `.sheet-scrim`。
class NordicScrim extends StatelessWidget {
  const NordicScrim({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onTap,
            // 遮罩也轻轻糊一下(原型 `blur(6px)`)—— 弹层后面的内容
            // 从「被压暗」变成「退到后面」,层次才分得开。
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ColoredBox(color: t.scrim),
            ),
          ),
        ),
        child,
      ],
    );
  }
}