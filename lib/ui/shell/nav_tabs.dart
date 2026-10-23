import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';
import 'bottom_stack.dart';

/// 一颗 tab(图标 + 文字 + 选中胶囊)—— 底部标签栏与宽屏左竖栏**共用一份**。
///
/// 两处读出的是同一件事:这个位置现在是活的。选中态(selectFill 胶囊、
/// 强调色图标)与字级逐条相同,差异只有排布 —— 托盘里横着均分(宽度由
/// 外面的 [Expanded] 给,外面再套一层左右 16 的内缩),竖栏里固定 68×52 竖着摞。
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
      child: Column(
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
