import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/theme/accent.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/theme_mode.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/shell/shell.dart';

/// 主题层的用例。
///
/// 刻意**不**整树 pump `NordicApp`:它下方的一级页面要
/// [PlaybackController](audio_service 的处理器),而处理器在测试环境里
/// 没有平台通道。为一个主题测试去造一份假的播放层,测的就不是主题了。
/// 主题相关的行为(默认档、token 注入、材质差异)下面这几条都能直接验到。
void main() {
  testWidgets('默认走深色 —— 这套设计的主场是近黑底 + 封面光晕', (tester) async {
    // 没存过偏好时 byName(null) 应回深色,而不是跟随系统。
    expect(NordicThemeMode.byName(null), NordicThemeMode.dark);
    expect(NordicThemeMode.byName('没这个档'), NordicThemeMode.dark);
    // 显式存过的档要照实还原。
    expect(NordicThemeMode.byName('light'), NordicThemeMode.light);
    expect(NordicThemeMode.byName('follow'), NordicThemeMode.follow);
  });

  testWidgets('两套主题都装上了 NordicTokens extension', (tester) async {
    for (final tokens in [NordicTokens.dark, NordicTokens.light]) {
      final theme = NordicTheme.build(tokens);
      expect(theme.extension<NordicTokens>(), same(tokens));
      expect(theme.brightness, tokens.brightness);
    }
  });

  testWidgets('沉浸页外壳把强调色挂进了作用域', (tester) async {
    final accent = NordicAccent.derived('album-1');
    late BuildContext inner;

    await tester.pumpWidget(
      MaterialApp(
        theme: NordicTheme.build(NordicTokens.dark),
        home: ImmersiveScaffold(
          accent: accent,
          child: Builder(builder: (context) {
            inner = context;
            return const SizedBox.shrink();
          }),
        ),
      ),
    );

    // 页面内任意深度都能拿到同一个强调色 —— 这正是「随封面取色」
    // 能遍布整屏的机制。在 pump 之后取 context,不在 build 里比 ——
    // build 期间 inherited widget 的注册尚未完成。
    expect(NordicAccentScope.of(inner), accent);
  });

  testWidgets('AppBar 的大标题与窄标题都不溢出', (tester) async {
    for (final big in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: Scaffold(
            appBar: NordicAppBar(
              title: '音乐库',
              subtitle: big ? 'HomeMusic · 531 首' : null,
              big: big,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 溢出时 Flutter 会把异常塞进 takeException,这里必须为空。
      expect(tester.takeException(), isNull, reason: 'big=$big 时标题栏不应溢出');
    }
  });
}