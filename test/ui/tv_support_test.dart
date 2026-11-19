import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/app.dart';

/// 电视这条线(第四十六轮):**leanback 身份 + 焦点 + 10 尺字号**。
///
/// 三样东西都不在 `flutter test` 的运行时里:电视桌面、遥控器、真机字号。
/// 所以这里钉的是「它们有没有接上」:
///   - 清单里那几条决定电视装不装、桌面上认不认得出来;
///   - 设计板与舞台有没有 TV 这一档(与原型的对账);
///   - 字号倍率是乘在系统缩放上,而不是把它换掉。
void main() {
  group('Android 清单：电视装得上、桌面上认得出', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('leanback 与「没有触摸屏」都不拦安装', () {
      expect(manifest, contains('android.software.leanback'));
      expect(manifest, contains('android.hardware.touchscreen'));
      final features = RegExp(r'<uses-feature[^>]*/>').allMatches(manifest);
      final names = features.map((m) => m.group(0)!).toList();
      for (final name in ['android.software.leanback', 'android.hardware.touchscreen']) {
        final line = names.firstWhere((n) => n.contains(name),
            orElse: () => '');
        expect(line, contains('android:required="false"'),
            reason: '$name 若 required=true，手机会被 Play 判成不兼容');
      }
    });

    test('电视桌面走 LEANBACK_LAUNCHER，并带一张 banner', () {
      expect(manifest, contains('android.intent.category.LEANBACK_LAUNCHER'));
      expect(manifest, contains('android:banner="@drawable/tv_banner"'));

      final banner =
          File('android/app/src/main/res/drawable/tv_banner.xml').readAsStringSync();
      expect(banner, contains('@mipmap/ic_launcher_foreground'),
          reason: 'banner 复用图标的前景层，不另画一份图形');
    });
  });

  group('原型：TV 是独立的一档，不是「宽屏」的别名', () {
    final js = File('prototype/app.js').readAsStringSync();
    final css = File('prototype/styles.css').readAsStringSync();

    test('外壳有 tv 变体与焦点环样式', () {
      expect(css, contains('.phone.tv {'));
      expect(css, contains('.screen.tv-focus'));
      expect(css, contains('width: 960px'));
      expect(css, contains('height: 540px'));
    });

    test('舞台的尺寸分段里有 TV，设计板有 TV 格', () {
      expect(js, contains("['tv', 'TV']"),
          reason: '侧栏尺寸切换要有 TV，否则交互流里到不了这一档');
      final board = js.substring(
        js.indexOf('const BOARD = ['),
        js.indexOf('function boardFrames'),
      );
      final tvCells = RegExp(r"frame: 'tv'").allMatches(board).length;
      expect(tvCells, greaterThanOrEqualTo(2),
          reason: '设计板至少铺两格 TV —— 库（带焦点环）与播放页');
      expect(board, contains('focus: true'),
          reason: '焦点环是 TV 与宽屏唯一的不同，设计板上必须有一格画出来');
    });
  });

  group('10 尺字号', () {
    test('倍率乘在系统缩放上，不是覆盖它', () {
      final normal = NordicApp.scalerFor(TextScaler.noScaling);
      expect(normal.scale(14), closeTo(14 * NordicApp.tvTextScale, 0.001));

      // 电视也吃无障碍字号:系统已经放大到 1.3 时,TV 那一档继续叠乘。
      final accessible = NordicApp.scalerFor(const TextScaler.linear(1.3));
      expect(accessible.scale(14),
          closeTo(14 * 1.3 * NordicApp.tvTextScale, 0.001));
    });
  });
}
