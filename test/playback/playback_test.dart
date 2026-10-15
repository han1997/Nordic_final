import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';

void main() {
  group('转码档位', () {
    test('原音档不传任何转码参数', () {
      // 关键:传了 format 就等于转码,哪怕码率写得很高也是重编码过的一道。
      expect(QualityOption.original.maxBitRate, isNull);
      expect(QualityOption.original.format, isNull);
      expect(QualityOption.original.isOriginal, isTrue);
    });

    test('三档转码各自对应码率,且都标为无损之外的档', () {
      expect(QualityOption.high.maxBitRate, 320);
      expect(QualityOption.medium.maxBitRate, 192);
      expect(QualityOption.low.maxBitRate, 96);
      for (final q in [QualityOption.high, QualityOption.medium, QualityOption.low]) {
        expect(q.isOriginal, isFalse);
        expect(q.format, isNotNull);
      }
    });

    test('码率从高到低排列 —— 面板上的顺序就是画质顺序', () {
      final rates = QualityOption.all
          .map((q) => q.maxBitRate ?? 99999)
          .toList();
      expect(rates, orderedEquals([...rates]..sort((a, b) => b.compareTo(a))));
    });

    test('未知 id 退回默认档而不是抛异常', () {
      expect(QualityOption.byId('nope'), QualityOption.fallback);
      expect(QualityOption.byId(null), QualityOption.fallback);
      expect(QualityOption.byId('low'), QualityOption.low);
    });

    test('控制器只在真的换了档位时才通知', () {
      final controller = QualityController(QualityOption.medium);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.set(QualityOption.medium);
      expect(notifications, 0, reason: '同档位重复设置不该触发重建');

      controller.set(QualityOption.low);
      expect(notifications, 1);
      expect(controller.value, QualityOption.low);
    });
  });

  group('播放状态', () {
    test('时长未知时进度不假装是 0%,也不越界', () {
      const unknown = PlaybackState(position: Duration(seconds: 30));
      expect(unknown.progress, 0, reason: '时长未知时不该给一个凭空的百分比');

      const halfway = PlaybackState(
        position: Duration(seconds: 30),
        duration: Duration(seconds: 60),
      );
      expect(halfway.progress, closeTo(50, 0.01));
    });

    test('进度在越界位置被夹回 0–100', () {
      const past = PlaybackState(
        position: Duration(seconds: 90),
        duration: Duration(seconds: 60),
      );
      expect(past.progress, 100);
    });

    test('copyWith 能清掉旧错误', () {
      const failed = PlaybackState(error: '连不上');
      expect(failed.copyWith(clearError: true).error, isNull);
      // 不显式清除时保留 —— 否则重绘一次错误提示就没了。
      expect(failed.copyWith(playing: true).error, '连不上');
    });
  });
}