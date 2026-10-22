import 'package:flutter/material.dart';

import '../adaptive/window.dart';
import 'bottom_stack.dart';
import 'nav_rail.dart';
import 'wide_bar.dart';

/// 常驻区(导航 + 播放坞)的**唯一切换点**:
///
///   窄屏(手机 / 平板竖屏)→ [BottomStack] 原样;
///   宽屏(>= 840)→ 左竖栏 + 底部播放横条。
///
/// 三处调用点(主壳 / 沉浸外壳 / 服务器页)都经过这里 —— 形态判断只此一份。
/// 下一轮 TV 若要在形态上再叠字号 / 焦点,也是改这一处。
class NordicChrome extends StatelessWidget {
  const NordicChrome({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    this.showDock = true,
  });

  /// 见 [BottomStack.activeTab]:可以为空(专辑 / 艺人 / 服务器几屏谁都不高亮)。
  final AppTab? activeTab;

  final ValueChanged<AppTab> onTabSelected;

  /// 沉浸页(播放 / 歌词)不显示坞 —— 那一屏整屏都是播放控制。
  final bool showDock;

  @override
  Widget build(BuildContext context) {
    if (!context.isExpanded) {
      // 窄支**原样返回** BottomStack:类名、`activeTab` 可为空的语义、
      // 显示逻辑一个字不改(几十条既有用例的判据建在 `find.byType(BottomStack)` 上)。
      return BottomStack(
        activeTab: activeTab,
        onTabSelected: onTabSelected,
        showDock: showDock,
      );
    }
    // Positioned.fill:内层 Stack 才不会缩成零尺寸(Positioned 的孩子不贡献大小),
    // 空白处不拦点击 —— 与窄屏托盘「浮着但不挡列表」同一条口径。
    return Positioned.fill(
      child: Stack(
        children: [
          NordicNavRail(activeTab: activeTab, onTabSelected: onTabSelected),
          if (showDock) const WidePlaybackBar(),
        ],
      ),
    );
  }
}
