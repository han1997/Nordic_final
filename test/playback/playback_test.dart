import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/playback/audio_handler.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';

void main() {
  // 造处理器会碰 AudioSession 的平台通道,先起绑定。
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('播放层无条件在场', () {
    test('不经过 AudioService.init 也能建出处理器 —— main.dart 的兜底路径', () {
      // 界面处处按「播放层一定在」取用(坞 / 播放页 / 歌曲菜单),所以
      // AudioService.init 挂住时必须能退到这条路,而不是给界面一个 null。
      final handler = NordicAudioHandler(() => null, QualityController());

      expect(handler.songs, isEmpty);
      expect(handler.currentSong, isNull);
      expect(handler.quality, QualityOption.fallback);

      handler.player.dispose();
    });
  });

  group('后台运行开关', () {
    test('开关开着:退到后台不动', () async {
      var paused = false;

      final did = await pauseWhenBackgrounded(
        backgroundPlay: true,
        pause: () async => paused = true,
      );

      expect(did, isFalse);
      expect(paused, isFalse, reason: '开着后台运行就得继续放');
    });

    test('开关关掉:退到后台就暂停', () async {
      var paused = false;

      final did = await pauseWhenBackgrounded(
        backgroundPlay: false,
        pause: () async => paused = true,
      );

      expect(did, isTrue);
      expect(paused, isTrue);
    });
  });

  group('离线优先', () {
    // 「下载过的曲子离线也能播」这句话的落点就是下面的规则:
    // 本机有文件就走本机,没有才拼网络地址。
    const song = Song(
      id: 's1',
      title: '曲目',
      artist: '艺人',
      album: '专辑',
      albumId: 'al-1',
    );

    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nordic-offline');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('本机有下载就走本机文件,连网络地址都不拼', () {
      final file = File('${dir.path}${Platform.pathSeparator}01 - 曲目.flac')
        ..writeAsBytesSync([1, 2, 3]);
      var askedRemote = false;

      final origin = playbackOriginFor(
        song,
        localPath: file.path,
        remote: () {
          askedRemote = true;
          return Uri.parse('http://nas.local/rest/stream.view?id=s1');
        },
      );

      expect(origin.local, isTrue);
      expect(origin.uri.scheme, 'file');
      expect(origin.uri.toFilePath(), file.path);
      // 离线时根本拼不出网络地址(没有服务器),这条短路正是它能播的原因。
      expect(askedRemote, isFalse, reason: '有本机文件就不该再问网络要地址');
    });

    test('记录里有路径但文件没了 —— 回退到网络,而不是播一个空', () {
      final missing = '${dir.path}${Platform.pathSeparator}被删掉了.flac';

      final origin = playbackOriginFor(
        song,
        localPath: missing,
        remote: () => Uri.parse('http://nas.local/rest/stream.view?id=s1'),
      );

      expect(origin.local, isFalse);
      expect(origin.uri.toString(), contains('nas.local'));
    });

    test('没下过的走服务器流', () {
      final origin = playbackOriginFor(
        song,
        remote: () => Uri.parse('http://nas.local/rest/stream.view?id=s1'),
      );

      expect(origin.local, isFalse);
      expect(origin.uri.queryParameters['id'], 's1');
    });
  });
}