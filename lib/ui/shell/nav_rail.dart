import 'package:flutter/material.dart';

import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../adaptive/window.dart';
import 'bottom_stack.dart';
import 'nav_tabs.dart';

/// 宽屏(>= 840)的左侧竖栏 —— 三颗 tab 从底部胶囊搬到这里(原型 `.railnav`)。
///
/// 与托盘同一套悬浮习语:四周 10px、同一层玻璃([NordicGlassPanel.nav])、
/// 同一个圆角档(r-xl);上下按安全区让开。谁浮它由调用方点名(见
/// `shell/chrome.dart` 的 NordicChrome)—— 播放 / 歌词 / 表单页没有底部托盘,
/// 也就没有它。
///
/// **按 `{activeTab, onTabSelected}` 定型**:下一轮 TV 遥控器焦点进来时,
/// 这里加 focus 参数即可,不必重排。
class NordicNavRail extends StatelessWidget {
  const NordicNavRail({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
  });

  /// 可以为空 —— 专辑 / 艺人 / 服务器几屏不属于任何 tab,谁都不高亮
  /// (与窄屏托盘的语义逐条相同)。
  final AppTab? activeTab;

  final ValueChanged<AppTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Positioned(
      left: NordicWindow.railMargin,
      top: NordicWindow.railMargin + pad.top,
      bottom: NordicWindow.railMargin + pad.bottom,
      child: SizedBox(
        // 84 = 6(内衬)× 2 + 72(按钮宽)。窄了按钮会被裁、宽了玻璃会虚。
        width: NordicWindow.railWidth,
        child: NordicGlass(
          panel: NordicGlassPanel.nav,
          borderRadius: BorderRadius.circular(NordicRadius.xl),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                for (final tab in AppTab.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: NavTabButton(
                      tab: tab,
                      selected: tab == activeTab,
                      onSelected: onTabSelected,
                      height: 60,
                      width: 72,
                      pressedFeedback: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
