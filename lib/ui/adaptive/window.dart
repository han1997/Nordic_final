import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';

/// 宽屏适配的**唯一口径** —— 断点与宽屏形态的几个数全在这里。
///
/// 分级照 Material 3 的窗口分级写作三档,但本轮只有 `expanded` 真在改形态:
/// 常驻区换左竖栏 + 播放横条、网格放开列数、播放页翻两栏。
/// 数值与 `prototype/styles.css` 尾部的容器查询(`@container (min-width: 840px)`)
/// 是同一套 —— `test/ui/adaptive_test.dart` 会读原型文件核对,改这里要同步改原型。
enum WindowClass {
  /// < 600:手机竖屏。底部胶囊托盘 + 两列网格(与历史形态逐像素一致)。
  compact,

  /// 600–839:平板竖屏 / 手机横屏。**形态与 compact 同** —— 这一档写出来是给
  /// 将来的密度调整留一个落脚点,眼下它不改变任何东西。
  medium,

  /// >= 840:平板横屏 / 桌面 / TV。左竖栏 + 底部播放横条 + 多列网格 + 两栏播放页。
  expanded,
}

abstract final class NordicWindow {
  /// 分级阈值(逻辑像素,只看宽)。
  static const mediumMin = 600.0;
  static const expandedMin = 840.0;

  /// 左竖栏:宽 84,四周 10;内容让位 104 = 10 + 84 + 10。
  static const railWidth = 84.0;
  static const railMargin = 10.0;
  static const gutter = railMargin + railWidth + railMargin;

  /// 底部播放横条:高 72(见 shell/wide_bar.dart),列表底部留白 88
  /// = 72 + 10 边距 + 6 空气(见 [BottomStack.listInset] 的分级口径)。
  static const barHeight = 72.0;
  static const barInset = 88.0;

  /// 网格:单格上限 280、间距 16(即 [NordicSpace.s4])—— 可用宽 / 296 向上取整。
  /// **与原型 app.js 的 `gridColsOf` 同一条公式**(那边写成 104 + 40 的减法版,
  /// 40 是网格自身左右 padding = s5 × 2)。
  static const gridMaxExtent = 280.0;

  /// 可用宽 → 列数。**只在 [WindowClass.expanded] 调用** —— 单靠这条公式,
  /// 默认测试视口(800 宽)会算出 3 列,而那一档必须保持 2 列:
  /// 几十条既有用例的判据建在两列网格之外的骨架上,列数漂一寸都是在挪地基。
  static int gridColumns(double available) =>
      math.max(2, (available / (gridMaxExtent + NordicSpace.s4)).ceil());

  static WindowClass classOf(double width) => width >= expandedMin
      ? WindowClass.expanded
      : width >= mediumMin
          ? WindowClass.medium
          : WindowClass.compact;

  /// 判级**只看逻辑宽**(MediaQuery.size)—— 不看物理像素:
  /// 测试里用 physicalSize / DPR 放大出来的「高瘦手机」与真机因此同一口径。
  static WindowClass of(BuildContext context) =>
      classOf(MediaQuery.sizeOf(context).width);
}

extension NordicWindowX on BuildContext {
  WindowClass get window => NordicWindow.of(this);

  /// 宽屏形态(>= 840)。**所有新形态的开关只认它** —— 挂到 medium 上会改变
  /// 默认测试视口(800×600)的形状,那一条底线写进 docs/performance.md 了。
  bool get isExpanded => window == WindowClass.expanded;
}

/// 宽屏下给左竖栏让出 104(主壳 / 沉浸外壳 / 服务器页三处共用)。
/// 窄屏或 [enabled] = false(这一屏本来就不浮常驻区)时原样返回。
///
/// 让位放在**壳**上一次性给出,页面里那 12 处 [BottomStack.listInset] 才不必
/// 各改一遍;代价是内容不会滚到竖栏玻璃底下(玻璃身后是均匀底色)——
/// 这是刻意的取舍,见 docs/performance.md。
class NavGutter extends StatelessWidget {
  const NavGutter({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => enabled && context.isExpanded
      ? Padding(
          padding: const EdgeInsets.only(left: NordicWindow.gutter),
          child: child,
        )
      : child;
}

/// 宽屏下把内容收成一栏(默认 720)—— 设置 / 关于 / 歌词正文这类「读的一栏」。
/// 窄屏原样返回(那些屏本来就够不到 720,包了也是空转)。
class NarrowContent extends StatelessWidget {
  const NarrowContent({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => context.isExpanded
      ? Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        )
      : child;
}
