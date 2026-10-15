import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/app.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';

void main() {
  testWidgets('应用能起来并拿到 token', (tester) async {
    await tester.pumpWidget(const NordicApp());
    await tester.pumpAndSettle();

    // 起不来会在 build 里抛(如 token 取不到),这里一旦渲染出内容即视为通过。
    expect(find.text('Nordic'), findsOneWidget);
  });

  testWidgets('切主题时 token 跟着换', (tester) async {
    await tester.pumpWidget(const NordicApp());
    await tester.pumpAndSettle();

    // 默认跟随系统(测试环境是浅色)。
    expect(find.text('亮色 true · glow 0.14'), findsOneWidget);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(find.text('亮色 false · glow 1.0'), findsOneWidget);
  });

  testWidgets('两套主题都装上了 NordicTokens extension', (tester) async {
    for (final tokens in [NordicTokens.dark, NordicTokens.light]) {
      final theme = NordicTheme.build(tokens);
      expect(theme.extension<NordicTokens>(), same(tokens));
    }
  });
}