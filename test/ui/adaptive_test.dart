import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/adaptive/window.dart';
import 'package:nordic/ui/shell/bottom_stack.dart';

/// 宽屏适配的口径守卫。
///
/// 这一组守三件事:
///   1. 分级阈值本身(599/600/839/840 四个边界点,只看逻辑宽);
///   2. **断点与原型同源** —— `prototype/styles.css` 的容器查询与
///      `prototype/app.js` 的 `gridColsOf` 里那几个数,与 [NordicWindow] 的
///      常量必须一致:原型是唯一设计真相来源,两边漂开等于实现悄悄改了设计;
///   3. 缩进口径两档(窄屏 150 / 宽屏 94)—— 12 处调用点全靠它。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('窗口分级只看逻辑宽：599/600/839/840 四个边界点', () {
    expect(NordicWindow.classOf(599), WindowClass.compact);
    expect(NordicWindow.classOf(600), WindowClass.medium);
    expect(NordicWindow.classOf(839), WindowClass.medium);
    expect(NordicWindow.classOf(840), WindowClass.expanded);
    // 几个真实宽度的落点(日常自查用)。
    expect(NordicWindow.classOf(390), WindowClass.compact); // 手机竖屏
    expect(NordicWindow.classOf(834), WindowClass.medium); // 平板竖屏
    expect(NordicWindow.classOf(1280), WindowClass.expanded); // 桌面窗
  });

  test('断点与原型同源：styles.css 的容器查询 / app.js 的网格公式', () {
    final css = File('prototype/styles.css').readAsStringSync();
    final js = File('prototype/app.js').readAsStringSync();

    // 宽屏翻牌的那条容器查询 —— 数值只此一处,改一边必须改另一边。
    expect(
      css,
      contains('@container (min-width: ${NordicWindow.expandedMin.toInt()}px)'),
      reason: 'prototype/styles.css 的宽屏容器查询与 NordicWindow.expandedMin 漂开了',
    );
    // 左竖栏让位(104)在原型里两处出现:.screen 的 padding 与播放横条的左缘。
    expect(css, contains('padding-left: ${NordicWindow.gutter.toInt()}px'));
    expect(css, contains('left: ${NordicWindow.gutter.toInt()}px'));

    // 网格公式:原型 app.js 的 gridColsOf —— 840 门槛 + (设备宽 − 104 − 40)/296。
    // 40 是网格自身左右 padding(s5 × 2);296 = 单格上限 280 + 间距 16。
    expect(js, contains('phoneW < ${NordicWindow.expandedMin.toInt()}'));
    expect(
      js,
      contains('(phoneW - ${NordicWindow.gutter.toInt()} - 40) / 296'),
      reason: 'prototype/app.js 的 gridColsOf 与 NordicWindow.gridColumns 漂开了',
    );
    expect(NordicWindow.gridMaxExtent + NordicSpace.s4, 296);
  });

  test('网格列数：一条除式，三点定形', () {
    // 可用宽三点:840−104−40 = 696;1280 → 1136;1920 → 1776。
    expect(NordicWindow.gridColumns(696), 3);
    expect(NordicWindow.gridColumns(1136), 4);
    expect(NordicWindow.gridColumns(1776), 6);
    // 再窄也不少于 2 列(公式本身的最小值)。
    expect(NordicWindow.gridColumns(100), 2);
  });

  testWidgets('listInset 两档：窄屏 150 / 宽屏 94（都不含安全区）', (tester) async {
    addTearDown(tester.view.reset);
    double? captured;
    Future<void> at(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          captured = BottomStack.listInset(context);
          return const SizedBox.shrink();
        }),
      ));
    }

    await at(const Size(1280, 800));
    expect(captured, NordicWindow.barInset);
    expect(captured, 94.0);

    await at(const Size(390, 844));
    expect(captured, BottomStack.bottomInset);
    expect(captured, 150.0);
  });
}
