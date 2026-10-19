import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/music_source.dart';
import 'package:nordic/playback/scrobble.dart';

/// 播放状态回报的判据。
///
/// 三条边界各是一条容易写错的地方:**同一首各只报一次**(队列重排 / 换档重装
/// 都会再走一遍装载)、**够一半才算听过**(拖动进度条到结尾不该算);
/// **时长未知就别猜**(报一条假数据比不报更糟)。
void main() {
  group('ScrobbleTracker', () {
    test('同一首的「正在播放」只报一次，换歌之后才再报', () {
      final t = ScrobbleTracker();

      expect(t.noteNowPlaying('s1'), isTrue);
      // 队列重排 / 换档重装都会再走一遍装载,但这一首还是在放 —— 不该再报一遍。
      expect(t.noteNowPlaying('s1'), isFalse);
      expect(t.noteNowPlaying('s2'), isTrue);
      // 切回来算「又开始了」—— 那时它确实重新装载了一次。
      expect(t.noteNowPlaying('s1'), isTrue);
    });

    test('位置够一半才报「听过」，而且只报一次', () {
      final t = ScrobbleTracker();
      const dur = Duration(minutes: 3);

      expect(t.notePosition('s1', position: const Duration(seconds: 30), duration: dur),
          isFalse);
      expect(t.notePosition('s1', position: const Duration(seconds: 89), duration: dur),
          isFalse);
      expect(t.notePosition('s1', position: const Duration(seconds: 90), duration: dur),
          isTrue);
      // 同一首再往后走多少都不重复报。
      expect(t.notePosition('s1', position: const Duration(seconds: 170), duration: dur),
          isFalse);
      // 下一首重新开始算。
      expect(t.notePosition('s2', position: const Duration(seconds: 90), duration: dur),
          isTrue);
    });

    test('长曲子按 4 分钟封顶，不按一半', () {
      final t = ScrobbleTracker();

      // 20 分钟的现场:一半是 10 分钟,但 4 分钟就该算听过了 ——
      // 听完两遍才记一次不是任何一个客户端会做的事。
      const long = Duration(minutes: 20);
      expect(t.notePosition('s1', position: const Duration(minutes: 4), duration: long),
          isTrue);
    });

    test('短曲子按一半，不按 4 分钟', () {
      final t = ScrobbleTracker();

      // 一首 90 秒的:一半是 45 秒。定死在 4 分钟的话它永远报不出去。
      const short = Duration(seconds: 90);
      expect(t.notePosition('s1', position: const Duration(seconds: 44), duration: short),
          isFalse);
      expect(t.notePosition('s1', position: const Duration(seconds: 45), duration: short),
          isTrue);
    });

    test('时长未知（0）时一条都不报 —— 判不出「一半」就别猜', () {
      final t = ScrobbleTracker();

      expect(t.notePosition('s1', position: const Duration(hours: 1), duration: Duration.zero),
          isFalse);
      expect(t.notePosition('s1', position: const Duration(hours: 1), duration: Duration.zero),
          isFalse);
    });

    test('两个计数各走各的：报了「正在播放」不影响「听过」', () {
      final t = ScrobbleTracker();
      const dur = Duration(minutes: 2);

      expect(t.noteNowPlaying('s1'), isTrue);
      expect(t.notePosition('s1', position: const Duration(minutes: 1), duration: dur),
          isTrue);
    });
  });

  group('PlaybackReporter', () {
    late List<(String, bool)> sent;
    late _FakeSource source;

    setUp(() {
      sent = [];
      source = _FakeSource(sent);
    });

    test('判据说该报了才真的发；同一首不重复发', () {
      final r = PlaybackReporter(() => source);

      r.nowPlaying('s1');
      r.nowPlaying('s1');
      r.position('s1', position: const Duration(minutes: 1), duration: const Duration(minutes: 2));
      r.position('s1', position: const Duration(minutes: 2), duration: const Duration(minutes: 2));

      expect(sent, [('s1', false), ('s1', true)]);
    });

    test('没有仓库（还没连服务器）时一条都不发', () {
      final r = PlaybackReporter(() => null);

      r.nowPlaying('s1');
      r.position('s1', position: const Duration(minutes: 9), duration: const Duration(minutes: 10));

      expect(sent, isEmpty);
    });

    test('请求失败是静默的 —— 不该把异常抛回播放事件那条路', () async {
      final r = PlaybackReporter(() => _FakeSource(sent, fail: true));

      r.nowPlaying('s1');
      // 让那一趟 `unawaited` 的 future 跑完;它要是没被吞掉,这里会冒出
      // 「Unhandled exception」把用例打红。
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(sent, [('s1', false)]);
    });
  });
}

/// 只记下「报了什么」的假音源 —— 其余方法这一组用不到。
class _FakeSource implements MusicSource {
  _FakeSource(this.sent, {this.fail = false});

  final List<(String, bool)> sent;
  final bool fail;

  @override
  Future<void> reportPlayback(
    String songId, {
    required bool submission,
    DateTime? at,
  }) async {
    sent.add((songId, submission));
    if (fail) throw const MusicSourceException('服务器不可达');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
