import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';
import 'bottom_stack.dart';

/// 一颗 tab(图标 + 文字 + 选中胶囊)—— 底部标签栏与宽屏左竖栏**共用一份**。
///
/// 两处读出的是同一件事:这个位置现在是活的。选中态(selectFill 胶囊、
/// 强调色图标)与字级逐条相同,差异只有排布 —— 托盘里横着均分(宽度由
/// 外面的 [Expanded] 给,外面再套一层左右 20 的内缩),竖栏里固定 68×52 竖着摞。
///
/// 按下反馈两处分走:[pressedFeedback] 为真时走 [Pressable](竖栏是新增的,
/// 按 docs/performance.md「可点元素一律走 Pressable」办);为假时保持托盘的
/// 历史写法(裸 GestureDetector、按下不换底)—— 托盘的行为一个字都不改。
class NavTabButton extends StatelessWidget {
  const NavTabButton({
    super.key,
    required this.tab,
    required this.selected,
    required this.onSelected,
    this.height = 50,
    this.width,
    this.pressedFeedback = false,
  });

  final AppTab tab;
  final bool selected;
  final ValueChanged<AppTab> onSelected;

  final double height;
  final double? width;
  final bool pressedFeedback;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent.accent;

    final content = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: selected ? selectFill(accent) : Colors.transparent,
        borderRadius: BorderRadius.circular(NordicRadius.full),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 选中胶囊那**两道内描边** —— 原型 `.tabbar button[aria-selected]` /
          // `.railnav button[aria-selected]` 的 `inset 0 1px 0 var(--glass-rim)`
          // 与 `inset 0 -1px 0 var(--glass-sh)`:上缘一道白、下缘一道黑。
          //
          // **半透明的底上不能用 BoxShadow 冒充 inset**:Flutter 的 BoxShadow
          // 画在盒子外面,那道影会从整颗胶囊里透出来(glass.dart 里玻璃上缘
          // 那道高光是同一个坑)。这里就是两条贴边的 1px 实线。
          if (selected) const _PillEdges(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                tab.icon,
                size: 23,
                color: selected ? context.accentSafe : t.fg3,
              ),
              // 图标与文字之间松一格;文字行高收到 1 —— 内容整体长高到 38.5,
              // 在 50 的胶囊里上下各剩 5.75,四周不再挤(见原型 `.tabbar` 同名注释)。
              const SizedBox(height: 4),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: selected ? t.fg : t.fg3,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (pressedFeedback) {
      return Pressable(
        onTap: () => onSelected(tab),
        pressedDecoration: BoxDecoration(
          color: t.fill1,
          borderRadius: BorderRadius.circular(NordicRadius.full),
        ),
        child: content,
      );
    }
    return GestureDetector(
      onTap: () => onSelected(tab),
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}

/// 选中胶囊上下缘那两道 1px 的线 —— 原型 `inset 0 ±1px 0` 的那两条。
///
/// 上下各一条、中间撑开:圆角由外面那颗胶囊裁(这个 Stack 就在它的圆角里),
/// 线条两端于是跟着圆角自然收细,与 CSS 的 inset 描边同一个样子。
class _PillEdges extends StatelessWidget {
  const _PillEdges();

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Column(
      children: [
        SizedBox(height: 1, child: ColoredBox(color: t.glassRim)),
        const Spacer(),
        SizedBox(height: 1, child: ColoredBox(color: t.glassShadow)),
      ],
    );
  }
}
