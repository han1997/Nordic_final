import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/theme/glass.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/adaptive/window.dart';
import 'package:nordic/ui/shell/bottom_stack.dart';
import 'package:nordic/ui/shell/nav_rail.dart';
import 'package:nordic/ui/shell/nav_tabs.dart';

/// 悬浮导航的尺寸契约(第二十八轮立,第二十九轮随「胶囊再收窄、竖栏改竖直
/// 居中」一并更新)。
///
/// **为什么单开一条**:这一组数字原先没有任何用例守着 —— 改前 / 改后都是
/// 506 全绿,也就是说谁把它们顺手改回去,测试一声都不会出。这一轮把它们钉住。
///
/// 钉的是**关系**,不是那几个绝对像素:托盘左右各留 20、药丸比格子窄 36、
/// 边距与缝同宽、竖栏面板贴合内容且竖直居中。绝对数会随字号与设备宽漂移,
/// 关系才是「好看」这几版真正定下来的东西。
void main() {
  /// 底部标签栏两侧的留白,也是每颗药丸的左右内缩 —— **两者必须同宽**
  /// (见下面「边距与缝同宽」那一条)。
  const inset = NordicSpace.s5;

  Widget wrap(Widget child, Size size) => MaterialApp(
        theme: NordicTheme.build(NordicTokens.dark),
        home: Scaffold(body: Stack(children: [child])),
      );

  group('底部胶囊托盘', () {
    Future<void> pump(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(
        BottomStack(
          activeTab: AppTab.home,
          showDock: false,
          onTabSelected: (_) {},
        ),
        size,
      ));
      await tester.pump();
    }

    testWidgets('托盘与内容栏同一条边线（各留 20）；标签栏 58；药丸 63 x 50', (tester) async {
      await pump(tester, const Size(390, 844));

      // **托盘的左右缘**是这一条的主角(2026-10-24「胶囊整体太宽」那一串)。
      // 先后试过 10(几乎满宽,读作贴边的横栏)与 28(比内容栏还窄,跟屏幕上
      // 任何东西都对不齐);定在 20 —— 内容栏自己的左边距。
      final tray = tester.getRect(find.byType(NordicGlass));
      expect(tray.left, BottomStack.trayMargin, reason: '托盘左边留白');
      expect(390 - tray.right, BottomStack.trayMargin, reason: '托盘右边留白');
      expect(
        BottomStack.trayMargin,
        NordicSpace.s5,
        reason: '托盘与内容栏同一条边线 —— 这一处的位置全靠这条对齐立住',
      );
      expect(
        tray.width,
        lessThan(390 - 2 * 16),
        reason: '整颗玻璃得浮起来，而不是贴着屏幕边的一条横栏',
      );

      // 标签栏是**那一行**(Row);药丸只是它 58 里居中摆着的 50。
      final row = tester.getRect(
        find.ancestor(
          of: find.byType(NavTabButton).first,
          matching: find.byType(Row),
        ).first,
      );
      expect(row.height, 58, reason: '标签栏高');

      final pills = [
        for (var i = 0; i < AppTab.values.length; i++)
          tester.getRect(find.byType(NavTabButton).at(i)),
      ];
      expect(pills[0].height, 50, reason: '药丸高');

      // 左右各 inset 的边距 + 每颗左右各 inset 的内缩 = 8 x inset,
      // 剩下的三等分就是药丸宽。(三等分除不尽,所以按容差比。)
      expect(pills[0].width, closeTo((tray.width - inset * 8) / 3, 0.01));
      expect(
        pills[0].width,
        lessThan(pills[0].height * 1.5),
        reason: '真药丸的比例 —— 原先那颗是横跨三分之一屏的一块「板子」',
      );
      // **托盘变窄最容易踩的一脚**:药丸跟着被压到点按下限附近。两条数
      // (trayMargin 与这里的 inset)是一起动的,所以这一条守着它们别脱钩。
      expect(
        pills[0].width,
        greaterThanOrEqualTo(60),
        reason: '托盘收窄不能把药丸挤没 —— 点按区（target 48）之外还要留得住字',
      );

      // 边距与缝同宽:靠托盘那两条留白与三颗之间那道缝是同一个数,
      // 三段于是看起来是均分的。(三等分除不尽,所以按容差比。)
      final gap = pills[1].left - pills[0].right;
      expect(gap, closeTo(inset * 2, 0.01), reason: '三颗之间那道缝');
      expect(pills[0].left - tray.left, closeTo(gap, 0.01), reason: '靠托盘那两条留白');
    });

    testWidgets('图标 23、字号 11.5 / 行高 1、图标与文字间距 4', (tester) async {
      await pump(tester, const Size(390, 844));

      final first = find.byType(NavTabButton).first;
      final icon = tester.widget<Icon>(
        find.descendant(of: first, matching: find.byType(Icon)).first,
      );
      expect(icon.size, 23);

      final label = tester.widget<Text>(find.text('首页'));
      expect(label.style?.fontSize, 11.5);
      expect(label.style?.height, 1, reason: '行高收到 1，内容才在 50 的胶囊里上下各剩 5.75');

      expect(
        tester.getRect(find.text('首页')).top -
            tester.getRect(find.descendant(of: first, matching: find.byType(Icon)).first).bottom,
        4,
        reason: '图标与文字之间那一格',
      );
    });
  });

  group('宽屏左竖栏', () {
    Future<void> pump(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(
        NordicNavRail(activeTab: AppTab.home, onTabSelected: (_) {}),
        size,
      ));
      await tester.pump();
    }

    testWidgets('面板贴合内容：84 x 180，且在左缘竖直居中', (tester) async {
      await pump(tester, const Size(1280, 800));

      // 外层占的是**让位用的那一列**(撑满,好把玻璃居中);看尺寸要看玻璃。
      final frame = tester.getRect(find.byType(NordicNavRail));
      expect(frame.left, NordicWindow.railMargin, reason: '左缘 10');
      expect(frame.width, NordicWindow.railWidth);

      final panel = tester.getRect(find.byType(NordicGlass));
      // 8 x 2 内衬 + 52 x 3 按钮 + 4 x 2 缝。
      expect(panel.height, 180, reason: '面板按内容收口，不再是通到屏幕底的柱子');
      expect(
        panel.center.dy,
        closeTo(400, 0.01),
        reason: '竖直居中 —— 贴左上角的话底下那一列全空，左下角是块没用的空档',
      );
      expect(
        panel.top > NordicWindow.railMargin && panel.bottom < 800 - NordicWindow.railMargin,
        isTrue,
        reason: '上下都留得下东西，而不是贴到某一头',
      );

      expect(tester.getSize(find.byType(NavTabButton).first), const Size(68, 52));
    });
  });
}
