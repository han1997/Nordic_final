import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/widgets/components.dart';

/// 键盘 / 遥控器焦点(第四十六轮)。
///
/// 电视没有鼠标:方向键要能把焦点移到下一格、确认键要真的点下去、
/// 焦点进到屏幕外时列表要跟过去。这三条都落在 [Pressable] 上,所以在这里
/// 钉住;具体哪一屏有没有把可点元素接上 Pressable,由各屏自己的用例管。
void main() {
  Widget harness(List<Widget> children, {Axis direction = Axis.horizontal}) {
    final layout = direction == Axis.horizontal
        ? Row(mainAxisAlignment: MainAxisAlignment.center, children: children)
        : Column(children: children);
    return MaterialApp(
      theme: NordicTheme.build(NordicTokens.dark),
      home: Scaffold(body: Center(child: layout)),
    );
  }

  Widget tile(String label, {VoidCallback? onTap, double width = 120}) =>
      Pressable(
        onTap: onTap ?? () {},
        scale: 1,
        child: SizedBox(
          width: width,
          height: 64,
          child: Center(child: Text(label)),
        ),
      );

  bool focused(WidgetTester tester, String label) =>
      Focus.maybeOf(tester.element(find.text(label)))?.hasFocus ?? false;

  testWidgets('方向键把焦点带进第一格，确认键真的点下去', (tester) async {
    final taps = <String>[];
    await tester.pumpWidget(harness([
      tile('A', onTap: () => taps.add('A')),
      tile('B', onTap: () => taps.add('B')),
    ]));

    // 冷启动时没有任何控件持有焦点 —— 这正是电视的起点。
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focused(tester, 'A'), isTrue,
        reason: '第一次按方向键，焦点要落在那一侧的第一格上，不能停在根节点');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, ['A'], reason: '确认键（Enter / 遥控器 OK）要触发 onTap');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focused(tester, 'B'), isTrue, reason: '右方向键换到下一格');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, ['A', 'B'], reason: '遥控器 OK 映射的是 select，也要触发');
  });

  testWidgets('焦点环只在键盘导航时出现', (tester) async {
    await tester.pumpWidget(harness([tile('A')]));

    final ring = find.descendant(
      of: find.byType(Pressable),
      matching: find.byType(DecoratedBox),
    );
    expect(ring, findsNothing, reason: '没有键盘焦点时不画环');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(ring, findsOneWidget, reason: '焦点落在这一格上时要多画那一圈环');
    final decoration =
        tester.widget<DecoratedBox>(ring).decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect((decoration.border! as Border).top.width, 2);
  });

  testWidgets('不可点的 Pressable 不进焦点链', (tester) async {
    await tester.pumpWidget(harness([
      tile('A'),
      Pressable(
        child: const SizedBox(
          width: 120,
          height: 64,
          child: Center(child: Text('disabled')),
        ),
      ),
    ]));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focused(tester, 'A'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focused(tester, 'disabled'), isFalse,
        reason: 'onTap 为空的控件照旧返回原样，不能变成一个按了没反应的焦点');
    expect(focused(tester, 'A'), isTrue,
        reason: '右边没有可聚焦的东西时，焦点留在原处');
  });

  testWidgets('焦点往下走，列表跟着滚', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: NordicTheme.build(NordicTokens.dark),
      home: Scaffold(
        body: ListView.builder(
          itemCount: 60,
          itemBuilder: (context, index) => Pressable(
            onTap: () {},
            scale: 1,
            child: SizedBox(
              height: 56,
              child: Center(child: Text('第 $index 行')),
            ),
          ),
        ),
      ),
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(focused(tester, '第 0 行'), isTrue);

    for (var i = 1; i <= 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(scrollable.position.pixels, greaterThan(100),
        reason: '焦点一路往下，列表要跟着把选中项滚进视野');
    expect(focused(tester, '第 8 行'), isTrue);
  });
}
