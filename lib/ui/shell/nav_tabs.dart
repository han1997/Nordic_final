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

    final content = AnimatedContainer(
      duration: NordicMotion.pillFill,
      curve: NordicMotion.ease,
      height: height,
      width: width,
      // 未选中是**完全无底、一圈透明边**(那颗药丸的位置由图标与文字自己说明);
      // 选中态换成 [selectPillDecoration] 那层有体积的强调色,200ms 里淡进来 ——
      // 与原型 `transition: ... background 0.2s var(--ease)` 同一条。
      //
      // **两态都给一份完整的 BoxDecoration**,未选中那份是
      // `transparent` + 同样的圆角 + `transparent` 的 1px 边:框架插值的是
      // 属性,写 `null` 的话过渡会直接跳过去。边也必须两态都在 —— 只在一态
      // 出现会让那颗药丸的内容盒在切换时挪 1px。
      //
      // 用 AnimatedContainer 而不是外面套 FadeTransition:渐变没法按透明度
      // 插值。代价是这颗药丸自己每帧重画,见下面 RepaintBoundary 那条。
      decoration: selected
          ? selectPillDecoration(t, accent)
          : BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(NordicRadius.full),
              border: Border.all(color: Colors.transparent, width: 1),
            ),
      // 选中胶囊那两道内描边在下面 (_PillEdges),与那道发丝边不冲突。
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

    // 这颗药丸自己隔一层重绘边界:选中 / 取消选中那 200ms 里它每帧都在重画
    // (渐变与边框色一起插值),不隔离的话每帧会顺着父链把托盘里那片玻璃与
    // 坞的内容一起标脏 —— 与 `_TrayProgress`、「坞」两处同一条口径
    // (见 docs/performance.md)。
    final pill = RepaintBoundary(child: content);

    if (pressedFeedback) {
      return Pressable(
        onTap: () => onSelected(tab),
        pressedDecoration: BoxDecoration(
          color: t.fill1,
          borderRadius: BorderRadius.circular(NordicRadius.full),
        ),
        child: pill,
      );
    }
    return GestureDetector(
      onTap: () => onSelected(tab),
      behavior: HitTestBehavior.opaque,
      child: pill,
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
