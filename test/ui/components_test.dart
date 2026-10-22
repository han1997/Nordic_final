import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/widgets/components.dart';

/// 主按钮的两副形态:通栏(默认)与居中胶囊([PrimaryButton.fillMaxWidth] = false)。
///
/// 胶囊这题曾经挂在「容器里多包了一层 `Center`」上 —— `Align` 在松约束下会
/// 撑满可用宽度,`Row` 倒是老实收着自己的宽,于是整颗按钮静悄悄变成通栏:
/// 专辑页那一颗「播放」自 M2 起就没当过胶囊,窄屏宽屏都一样。
/// 这里把两种形态与「长标签撑宽而不是截断」一起钉住。
void main() {
  Future<Rect> pumpButton(
    WidgetTester tester, {
    required double width,
    required bool fill,
    String label = '播放',
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: NordicTheme.build(NordicTokens.dark),
      home: Scaffold(
        // 与专辑页 [_PlayButton] 同一副壳:两头留 s5,Center 断中,
        // ConstrainedBox 给 min-width 190。
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 190),
              child: PrimaryButton(
                label: label,
                icon: Icons.play_arrow,
                height: 50,
                fillMaxWidth: fill,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    ));
    return tester.getRect(find.byType(PrimaryButton));
  }

  testWidgets('fillMaxWidth:false —— 收成一枚居中胶囊，不吃满一行', (tester) async {
    for (final width in [420.0, 1280.0]) {
      final rect = await pumpButton(tester, width: width, fill: false);
      expect(rect.width, closeTo(190, 0.5),
          reason: 'min-width 190 的胶囊：宽 $width 下也不能变通栏');
      expect((rect.center.dx - width / 2).abs(), lessThan(1),
          reason: '胶囊居中');
    }
  });

  testWidgets('长标签把胶囊撑宽，而不是被截成 190', (tester) async {
    final rect = await pumpButton(
      tester,
      width: 1280,
      fill: false,
      label: '播放整张专辑里的全部曲目',
    );
    expect(rect.width, greaterThan(190),
        reason: 'min-width 只是下限 —— 内容更宽时跟着内容走（与原型 width:auto 一致）');
  });

  testWidgets('默认形态仍是通栏', (tester) async {
    final rect = await pumpButton(tester, width: 1280, fill: true);
    expect(rect.width, 1280 - 40, reason: '通栏：吃满父给的宽');
  });
}
