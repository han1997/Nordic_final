import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/theme/fx.dart';
import 'package:nordic/ui/widgets/components.dart';
import 'package:nordic/ui/widgets/fx.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 动效开关(`设置 → 动效`)的六条与三档,以及它们真的挂到了动的那些地方。
///
/// 这里钉三件事:
///   1. **口径与原型一致** —— 六条的 id / 名字 / 位置 / 一句话,逐字对
///      `prototype/app.js` 的 `FX_ITEMS`;三档预设的取舍也对 `FX_PRESETS`。
///   2. **落盘的往返** —— 存的是「关掉的那几条」,读回来还是那几条,
///      没存过 / 认不出的词都按全开(与原型默认全开同一条口径)。
///   3. **开关真的管用** —— 关掉一条之后,那一条的实现里不再有位移。
void main() {
  group('六条动效的口径', () {
    test('id 与原型 FX_ITEMS 逐字一致，顺序也一致', () {
      final src = File('prototype/app.js').readAsStringSync();
      final block = RegExp(
        r'const FX_ITEMS = \[(.*?)\n\];',
        dotAll: true,
      ).firstMatch(src)!.group(1)!;
      final ids = RegExp(r"id:\s*'([^']+)'")
          .allMatches(block)
          .map((m) => m.group(1)!)
          .toList();
      expect(ids, FxId.values.map((f) => f.id).toList());
    });

    test('名字、位置、一句话也逐字一致', () {
      final src = File('prototype/app.js').readAsStringSync();
      for (final fx in FxId.values) {
        // 一条在原型里长这样:
        //   { id: 'stagger', name: '列表错开入场', where: '…', short: '…', icon: … }
        final re = RegExp(
          "name: '([^']*)'[^}]*?where: '([^']*)'[^}]*?short: '([^']*)'",
        );
        final entry = RegExp(
          "id: '${fx.id}'.*?\\}",
          dotAll: true,
        ).firstMatch(src)!.group(0)!;
        final m = re.firstMatch(entry)!;
        expect(m.group(1), fx.name, reason: '${fx.id} 的名字对不上原型');
        expect(m.group(2), fx.where, reason: '${fx.id} 的位置对不上原型');
        expect(m.group(3), fx.short, reason: '${fx.id} 的那句话对不上原型');
      }
    });

    test('三档预设的取舍与原型 FX_PRESETS 一致', () {
      final src = File('prototype/app.js').readAsStringSync();
      final block = RegExp(
        r'const FX_PRESETS = \{(.*?)\n\};',
        dotAll: true,
      ).firstMatch(src)!.group(1)!;
      for (final preset in FxPreset.values) {
        // 原型里这三条长这样:
        //   all:  FX_ALL_ON,
        //   rec:  { stagger: true, tabx: false, … },
        //   none: FX_ALL_OFF,
        final entry = RegExp(
          "\\b${preset.name}:\\s*([^\\n]+)",
        ).firstMatch(block)!.group(1)!.trim().replaceAll(RegExp(r',$'), '');
        final on = switch (entry) {
          'FX_ALL_ON' => FxId.values.toSet(),
          'FX_ALL_OFF' => <FxId>{},
          _ => {
              for (final m in RegExp(r"(\w+):\s*(true|false)").allMatches(entry))
                if (m.group(2) == 'true')
                  FxId.values.firstWhere((f) => f.id == m.group(1)),
            },
        };
        for (final fx in FxId.values) {
          expect(
            preset.allows(fx),
            on.contains(fx),
            reason: '${preset.name} 这一档里 ${fx.id} 的取舍对不上原型',
          );
        }
      }
    });

    test('推荐组合留下的就是那四条', () {
      expect(
        FxId.values.where(FxPreset.rec.allows).toList(),
        [FxId.stagger, FxId.spring, FxId.press, FxId.lyric],
      );
    });
  });

  group('MotionPrefs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('默认全开 —— 与原型 STATE.fx 的初值同一条口径', () {
      final prefs = MotionPrefs();
      expect(FxId.values.every(prefs.isOn), isTrue);
      expect(prefs.preset, FxPreset.all);
    });

    test('逐条改过之后不属于任何一档', () {
      final prefs = MotionPrefs();
      // 推荐组合就是这两条关着,所以一条条关到那一步,三档里就有它。
      prefs.set(FxId.tabx, false);
      expect(prefs.preset, isNull);
      prefs.set(FxId.dock, false);
      expect(prefs.preset, FxPreset.rec);
      // 再关一条原型里留着的那条 —— 谁都不像了,三档全灭。
      prefs.set(FxId.stagger, false);
      expect(prefs.preset, isNull);
    });

    test('预设一次改六条', () {
      final prefs = MotionPrefs();
      prefs.applyPreset(FxPreset.none);
      expect(FxId.values.any(prefs.isOn), isFalse);
      prefs.applyPreset(FxPreset.rec);
      expect(prefs.preset, FxPreset.rec);
      prefs.applyPreset(FxPreset.all);
      expect(FxId.values.every(prefs.isOn), isTrue);
    });

    test('落盘存的是「关掉的那几条」，读回来还是那几条', () async {
      final prefs = MotionPrefs.fromStore(await ConfigStore.open());
      prefs.set(FxId.tabx, false);
      prefs.set(FxId.dock, false);
      await Future<void>.delayed(Duration.zero);

      final reopened = await ConfigStore.open();
      expect(reopened.loadFxOff(), 'tabx dock');
      final restarted = MotionPrefs.fromStore(reopened);
      expect(restarted.isOn(FxId.tabx), isFalse);
      expect(restarted.isOn(FxId.dock), isFalse);
      expect(restarted.isOn(FxId.stagger), isTrue);
      expect(restarted.preset, FxPreset.rec);
    });

    test('盘上是空串 / 认不出的词，都按全开', () {
      expect(MotionPrefs.parseFxIds(null), isEmpty);
      expect(MotionPrefs.parseFxIds(''), isEmpty);
      expect(MotionPrefs.parseFxIds('这种词没写进枚举'), isEmpty);
      expect(MotionPrefs.parseFxIds('press'), {FxId.press});
    });

    test('没挂 scope 时那份是只读的 —— 用例之间不会互相污染', () {
      final prefs = MotionPrefs.fallback;
      expect(prefs.writable, isFalse);
      prefs.set(FxId.press, false);
      prefs.applyPreset(FxPreset.none);
      expect(FxId.values.every(prefs.isOn), isTrue);
    });
  });

  group('开关挂到应用里', () {
    /// 这一组是「别只在 `fx.dart` 里实现了一遍」的守卫:六条各自要有一处
    /// 真的挂在应用的树上,而且那一份偏好要由 `main.dart` 挂上去 ——
    /// 没挂的话每一处都回退到那份只读的全开,设置里的开关就成了摆设。
    const sites = <FxId, (String, String)>{
      FxId.stagger: ('lib/ui/screens/home_screen.dart', 'FxStagger('),
      FxId.tabx: ('lib/ui/shell/shell.dart', 'FxId.tabx'),
      FxId.spring: ('lib/ui/widgets/components.dart', 'FxId.spring'),
      FxId.press: ('lib/ui/widgets/components.dart', 'FxId.press'),
      FxId.dock: ('lib/ui/shell/bottom_stack.dart', 'FxDockRise('),
      FxId.lyric: ('lib/ui/screens/lyrics_screen.dart', 'FxLyricRise('),
    };

    test('六条各有一处真的挂在应用上', () {
      for (final entry in sites.entries) {
        final (path, marker) = entry.value;
        expect(
          File(path).readAsStringSync(),
          contains(marker),
          reason: '${entry.key.id} 的实现在 $path 里找不到 $marker —— '
              '那就是「开关关不掉，因为压根没挂」',
        );
      }
      // 六条都得有着落;将来加了第七条,这里会先红。
      expect(sites.keys.toSet(), FxId.values.toSet());
    });

    test('`main.dart` 把这一份挂到树上 —— 不挂就等于是全开且写不进去', () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(src, contains('MotionScope('));
      expect(src, contains('MotionPrefs.fromStore(configStore)'));
    });
  });

  group('开关管到实现', () {
    Future<void> pumpScoped(
      WidgetTester tester,
      MotionPrefs prefs,
      Widget child,
    ) async {
      await tester.pumpWidget(
        MotionScope(
          prefs: prefs,
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );
    }

    /// 这一层(以及它下面)所有 `Transform` 的竖直位移。
    double riseOf(WidgetTester tester, Finder of) {
      final transforms = tester.widgetList<Transform>(
        find.ancestor(of: of, matching: find.byType(Transform)),
      );
      var dy = 0.0;
      for (final t in transforms) {
        dy += t.transform.getTranslation().y;
      }
      return dy;
    }

    testWidgets('「托盘落位」关掉后播放坞不再从 22px 升上来', (tester) async {
      final on = MotionPrefs();
      await pumpScoped(
        tester,
        on,
        const FxDockRise(replay: 'home', child: SizedBox(height: 60)),
      );
      await tester.pump();
      expect(riseOf(tester, find.byType(SizedBox).first), greaterThan(0));

      final off = MotionPrefs(off: {FxId.dock});
      await pumpScoped(
        tester,
        off,
        const FxDockRise(replay: 'home', child: SizedBox(height: 60)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(riseOf(tester, find.byType(SizedBox).first), 0);
    });

    testWidgets('「列表错开入场」按位置依次落位，关掉之后一步不动', (tester) async {
      // `key` 让两遍各建一棵新的:沿用同一棵的话控制器早就演完了,
      // 「关掉之后一步不动」量到的是「已经演完」,不是「根本没演」。
      Widget body(List<Widget> children, {Key? key}) => FxStagger(
            key: key,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++)
                  FxRise(index: i, child: children[i]),
              ],
            ),
          );
      final rows = [
        for (var i = 0; i < 3; i++) SizedBox(key: ValueKey(i), height: 20),
      ];

      await pumpScoped(tester, MotionPrefs(), body(rows));
      await tester.pump(const Duration(milliseconds: 20));
      // 同一时刻:第 0 格已经在落位,第 2 格还没起步 —— 这才是「依次」。
      final first = riseOf(tester, find.byKey(const ValueKey(0)));
      final third = riseOf(tester, find.byKey(const ValueKey(2)));
      expect(first, lessThan(NordicFx.staggerDistance));
      expect(third, greaterThan(first));

      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        expect(riseOf(tester, find.byKey(ValueKey(i))), 0);
      }

      await pumpScoped(
        tester,
        MotionPrefs(off: {FxId.stagger}),
        body(rows, key: const ValueKey('off')),
      );
      await tester.pump(const Duration(milliseconds: 20));
      for (var i = 0; i < 3; i++) {
        expect(riseOf(tester, find.byKey(ValueKey(i))), 0);
      }
    });

    testWidgets('「按压回弹」关掉后按下去不再缩', (tester) async {
      Finder scale() => find.byType(AnimatedScale);

      await pumpScoped(
        tester,
        MotionPrefs(),
        Center(
          child: Pressable(
            onTap: () {},
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      );
      await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(scale()).scale, lessThan(1));
      await tester.pumpAndSettle();

      await pumpScoped(
        tester,
        MotionPrefs(off: {FxId.press}),
        Center(
          child: Pressable(
            onTap: () {},
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      );
      expect(scale(), findsNothing);
      final down = await tester.startGesture(
        tester.getCenter(find.byType(SizedBox)),
      );
      await tester.pump();
      expect(scale(), findsNothing);
      await down.up();
    });

    testWidgets('「歌词换行浮起」只在新亮的那一下演，重建不重演', (tester) async {
      Widget line(bool active) => FxLyricRise(
            active: active,
            child: SizedBox(key: const ValueKey('line'), height: 20),
          );
      double rise() => riseOf(tester, find.byKey(const ValueKey('line')));

      await pumpScoped(tester, MotionPrefs(), line(false));
      await tester.pumpAndSettle();
      expect(rise(), 0, reason: '还没轮到它，不许提前动');

      await pumpScoped(tester, MotionPrefs(), line(true));
      await tester.pump(const Duration(milliseconds: 30));
      expect(rise(), greaterThan(0), reason: '轮到它了，从下方 4px 浮起');
      await tester.pumpAndSettle();
      expect(rise(), 0);

      // 歌词位置每跳一次,这几行都要重建一遍 —— 重建不算「又亮了一次」,
      // 否则一直在抖。这里把父级重画一遍(不是 identity,会真的走 didUpdateWidget)。
      await pumpScoped(tester, MotionPrefs(), line(true));
      await tester.pump(const Duration(milliseconds: 30));
      expect(rise(), 0, reason: '还是那一句，重建一次不许再浮一次');

      // 真的换了行才算:灭 → 亮。
      await pumpScoped(tester, MotionPrefs(), line(false));
      await tester.pumpAndSettle();
      await pumpScoped(tester, MotionPrefs(), line(true));
      await tester.pump(const Duration(milliseconds: 30));
      expect(rise(), greaterThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets('「弹层回弹」那条曲线真的冲过落点，而默认那条不冲', (tester) async {
      final spring = NordicSpringCurve();
      expect(
        spring.transform(NordicFx.sheetPeak),
        closeTo(1 + NordicFx.sheetOvershoot, 1e-9),
      );
      expect(spring.transform(1), 1);
      expect(spring.transform(0), 0);
      // 单调冲到峰值,再单调落定 —— 中途不许再抽第二下。
      var prev = 0.0;
      for (var t = 0.0; t <= NordicFx.sheetPeak; t += 0.01) {
        final v = spring.transform(t);
        expect(v, greaterThanOrEqualTo(prev - 1e-9));
        prev = v;
      }
      var tail = 1 + NordicFx.sheetOvershoot;
      for (var t = NordicFx.sheetPeak; t <= 1; t += 0.01) {
        final v = spring.transform(t);
        expect(v, lessThanOrEqualTo(tail + 1e-9));
        tail = v;
      }
    });
  });
}
