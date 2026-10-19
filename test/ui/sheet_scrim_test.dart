import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/widgets/components.dart';

/// 弹层那层蒙版**原地淡入,不位移**。
///
/// 框架的 `_BottomSheetLayout` 是把整块内容按**带曲线的** `_sheetAnimation`
/// 从屏幕下方挪上来的,而 `NordicScrim` 里那层「抵消框架位移」的补偿早先按
/// 路由的**线性** `animation` 求值 —— 两条曲线不等价,补偿只抵掉一部分,
/// 净剩 `H[v - curve(v)]` 的位移(中途可达屏高的四分之一)。真机上的表现是
/// 「弹层升起时底下一整块蒙版带着边缘从上方压下来」,而原型只淡入。
///
/// 量的是**蒙版那一层本身**(`NordicScrim` 里的 `BackdropFilter`),不是
/// `NordicScrim` 整棵 —— 后者连着随纸走的那个孩子,本来就该动。
/// 改回线性曲线这一条会立刻红(蒙版的上边缘会一路往下走)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 一层蒙版 + 一张纸。
  Widget sheets({VoidCallback? onScrimTap}) => NordicScrim(
        onTap: onScrimTap,
        child: NordicSheet(title: '随便什么', child: Container(height: 120)),
      );

  /// [closeOnScrimTap] 为真时蒙版可点关(点遮罩那一路);
  /// 为假时蒙版不接这一下 —— 用例自己用别的方式关。
  Future<void> openSheet(
    WidgetTester tester, {
    bool closeOnScrimTap = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NordicTheme.build(NordicTokens.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showNordicSheet<void>(
                  context: context,
                  builder: (sheetContext) => sheets(
                    onScrimTap: closeOnScrimTap
                        ? () => Navigator.of(sheetContext).pop()
                        : null,
                  ),
                ),
                child: const Text('开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开'));
  }

  /// 蒙版那一层(**彩色暗层所在的**那个 `BackdropFilter`)。
  ///
  /// 那一棵里有两个:蒙版自己那个 blur(6),以及纸的玻璃 blur(34)。
  /// 蒙版铺在**前**(Stack 里先摆),所以取 first。
  Finder backdrops() => find.descendant(
        of: find.byType(NordicScrim),
        matching: find.byType(BackdropFilter),
      );

  /// 量的时候取第一个(蒙版)。**判空要用 [backdrops]** —— `.first` 在空集上
  /// 会直接抛 StateError,那不是这条用例想报的失败。
  Finder backdrop() => backdrops().first;

  testWidgets('升起那一路：逐帧量，蒙版始终铺满整屏', (tester) async {
    await openSheet(tester);

    // 一帧一帧地推,每一帧都量一次 —— 只量首尾两帧会漏掉中途那个「压下来」
    // 最厉害的时刻(曲线与直线的差在中段最大)。
    var frames = 0;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 32));
      if (backdrops().evaluate().isEmpty) continue;
      final found = backdrop();
      frames++;
      final rect = tester.getRect(found);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        rect.top,
        moreOrLessEquals(0, epsilon: 0.5),
        reason: '第 $i 帧：蒙版上边缘跑了（${rect.top})—— 它本该一直贴着屏幕顶',
      );
      expect(
        rect.height,
        moreOrLessEquals(screen.height, epsilon: 0.5),
        reason: '第 $i 帧：蒙版不是整屏高 —— 那层补偿把它带着走了',
      );
    }
    expect(frames, greaterThan(3), reason: '一帧都没量到，这条用例等于没跑');
    await tester.pumpAndSettle();
  });

  testWidgets('关掉那一路也一样 —— 反着走不重演那一下', (tester) async {
    await openSheet(tester, closeOnScrimTap: true);
    await tester.pumpAndSettle();

    // 点遮罩关掉。**不能点正中心** —— 那里正好是那张纸自己,事件目标不是
    // 遮罩,关不掉(原型的自检脚本里记着同一个坑)。
    final rect = tester.getRect(backdrop());
    await tester.tapAt(Offset(rect.center.dx, rect.top + 4));

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 32));
      if (backdrops().evaluate().isEmpty) break;
      final found = backdrop();
      expect(
        tester.getRect(found).top,
        moreOrLessEquals(0, epsilon: 0.5),
        reason: '第 $i 帧（关）：蒙版上边缘跑了',
      );
    }
    await tester.pumpAndSettle();
    expect(find.byType(NordicScrim), findsNothing);
  });

  test('那条曲线不是直线 —— 这正是必须两边同款的另一半', () {
    // 补偿层一旦按**线性**求值,与框架那条带缓动的就抵不干净。
    // 这里钉住「它确实不是直线」(中点不等于 0.5)以及两端点照旧,
    // 免得有人把它换成 `Curves.linear` 还觉得「看起来一样」。
    expect(nordicSheetCurve.transform(0), 0);
    expect(nordicSheetCurve.transform(1), 1);
    expect(
      nordicSheetCurve.transform(0.5),
      isNot(moreOrLessEquals(0.5, epsilon: 0.001)),
      reason: '这条曲线被换成了直线 —— 补偿层按它算就抵不掉框架的位移',
    );
  });
}