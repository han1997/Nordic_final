import 'dart:async';
import 'dart:io';

// 只取这一个:audio_service 也导出一个 `PlaybackState`,全量导入会与
// `package:nordic/playback/playback_controller.dart` 撞名。
import 'package:audio_service/audio_service.dart' show AudioServiceRepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/network_status.dart';
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

    test('「比它低」与「比它高」两串名单都从档位表上切出来', () {
      // 删除候选:只列更低的。更高的那份绝不能进去 —— 那是要留下的那一份。
      expect(
        lowerTiersThan(QualityOption.original).map((q) => q.id),
        orderedEquals(['high', 'medium', 'low']),
      );
      expect(
        lowerTiersThan(QualityOption.medium).map((q) => q.id),
        orderedEquals(['low']),
      );
      expect(lowerTiersThan(QualityOption.low), isEmpty);

      // 接管候选:只列更高的,由高到低(越好的越先试)。
      expect(
        betterTiersThan(QualityOption.low).map((q) => q.id),
        orderedEquals(['original', 'high', 'medium']),
      );
      expect(betterTiersThan(QualityOption.original), isEmpty);

      // 两串互不重叠,合上自己正好是整张表 —— 换档时不会漏掉也不会重复。
      for (final q in QualityOption.all) {
        expect(
          [...betterTiersThan(q), q, ...lowerTiersThan(q)],
          orderedEquals(QualityOption.all),
        );
      }
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
      expect(
        playbackProgress(const Duration(seconds: 30), Duration.zero),
        0,
        reason: '时长未知时不该给一个凭空的百分比',
      );
      expect(
        playbackProgress(const Duration(seconds: 30), const Duration(seconds: 60)),
        closeTo(50, 0.01),
      );
    });

    test('进度在越界位置被夹回 0–100', () {
      expect(
        playbackProgress(const Duration(seconds: 90), const Duration(seconds: 60)),
        100,
      );
      expect(
        playbackProgress(const Duration(seconds: -5), const Duration(seconds: 60)),
        0,
      );
    });

    test('copyWith 能清掉旧错误', () {
      const failed = PlaybackState(error: '连不上');
      expect(failed.copyWith(clearError: true).error, isNull);
      // 不显式清除时保留 —— 否则重绘一次错误提示就没了。
      expect(failed.copyWith(playing: true).error, '连不上');
    });
  });

  group('循环模式', () {
    test('三态轮转:顺序播放 → 列表循环 → 单曲循环 → 回到原位', () {
      // 真机上报的是「循环键点了没反应」。以前不但只有两态(off / one),
      // 而且状态是单向写的 —— 这条钉住三态的顺序本身。
      expect(nextRepeatMode(PlaybackRepeat.off), PlaybackRepeat.all);
      expect(nextRepeatMode(PlaybackRepeat.all), PlaybackRepeat.one);
      expect(nextRepeatMode(PlaybackRepeat.one), PlaybackRepeat.off);
    });

    test('三态各自映射到 audio_service 的重复模式', () {
      expect(
        audioServiceRepeatModeFor(PlaybackRepeat.off),
        AudioServiceRepeatMode.none,
      );
      expect(
        audioServiceRepeatModeFor(PlaybackRepeat.all),
        AudioServiceRepeatMode.all,
      );
      expect(
        audioServiceRepeatModeFor(PlaybackRepeat.one),
        AudioServiceRepeatMode.one,
      );
    });

    test('落到 just_audio 时「列表循环」真的用 LoopMode.all', () {
      // 以前那句三元把除 none 以外的一切都映射成 LoopMode.one ——
      // 「列表循环」这个状态在代码里压根不存在。
      expect(loopModeFor(AudioServiceRepeatMode.none), LoopMode.off);
      expect(loopModeFor(AudioServiceRepeatMode.all), LoopMode.all);
      expect(loopModeFor(AudioServiceRepeatMode.one), LoopMode.one);
      // 分组循环两边都没实现(android 的 REPEAT_MODE_GROUP),按顺序播放走,
      // 不假装支持。
      expect(loopModeFor(AudioServiceRepeatMode.group), LoopMode.off);
    });

    test('copyWith 带上循环模式', () {
      expect(const PlaybackState().repeat, PlaybackRepeat.off);
      expect(
        const PlaybackState().copyWith(repeat: PlaybackRepeat.one).repeat,
        PlaybackRepeat.one,
      );
    });
  });

  group('平台倒回开头', () {
    // 真机(2026-10-17):还没转码过的那一首(源是**没有长度**的冷流)放完时,
    // 平台没有切下一首,而是把这一首从 0 秒又放了一遍 —— 用户读作「单曲循环」。
    // 护栏在 `audio_handler` 的位置监察上,**这一组钉的是它的判据**:
    // 四条「不该管」只要漏一条,就会在拖动 / 切歌 / 单曲循环上误切下一首。
    bool rewind({
      Duration previous = const Duration(seconds: 200),
      Duration next = Duration.zero,
      Duration trackDuration = const Duration(seconds: 216),
      bool seekRequested = false,
      bool loopsOne = false,
      bool indexChanged = false,
    }) =>
        didPlatformRewind(
          previous: previous,
          next: next,
          trackDuration: trackDuration,
          seekRequested: seekRequested,
          loopsOne: loopsOne,
          indexChanged: indexChanged,
        );

    test('放完一首后自己回到开头 —— 这就是要拦的那一下', () {
      expect(rewind(), isTrue);
    });

    test('我们自己请求的 seek 不算 —— 用户想回到开头就让他回去', () {
      expect(rewind(seekRequested: true), isFalse);
    });

    test('换歌不算 —— 换歌本来就把位置归零', () {
      expect(rewind(indexChanged: true), isFalse);
    });

    test('单曲循环不算 —— 那一支本来就该回到开头', () {
      expect(rewind(loopsOne: true), isFalse);
    });

    test('小抖动不算,在开头附近来回也不算', () {
      expect(
        rewind(previous: const Duration(seconds: 100), next: const Duration(seconds: 97)),
        isFalse,
        reason: '三秒的差是位置流的常态,不该当成倒回',
      );
      expect(
        rewind(previous: const Duration(seconds: 4), next: Duration.zero),
        isFalse,
        reason: '开头附近本来就没有「放完了倒回去」这回事',
      );
    });

    test('位置往前走不算', () {
      expect(
        rewind(previous: const Duration(seconds: 30), next: const Duration(seconds: 60)),
        isFalse,
      );
    });

    test('十秒以内的短曲子也拦得住 —— 门槛跟着曲长收', () {
      // 写死「至少 10 秒」的话,间奏 / 试听片段这类曲子上护栏等于不存在:
      // 位置永远够不着门槛,于是它一直单曲循环下去。
      expect(
        rewind(
          previous: const Duration(seconds: 8),
          next: Duration.zero,
          trackDuration: const Duration(seconds: 8),
        ),
        isTrue,
      );
      expect(
        rewind(
          previous: const Duration(seconds: 3),
          next: Duration.zero,
          trackDuration: const Duration(seconds: 3),
        ),
        isTrue,
      );
    });

    test('长曲子的两条门槛不变 —— 别把老行为改坏', () {
      // 3 分半:半首 105 秒、四分之一 52 秒,都被 10 秒 / 5 秒的上限按住。
      expect(
        rewind(
          previous: const Duration(seconds: 9),
          next: Duration.zero,
          trackDuration: const Duration(seconds: 210),
        ),
        isFalse,
        reason: '九秒处往回跳不算「放完了」',
      );
      expect(
        rewind(
          previous: const Duration(seconds: 60),
          next: const Duration(seconds: 56),
          trackDuration: const Duration(seconds: 210),
        ),
        isFalse,
        reason: '四秒的差仍在位置流抖动的范围内',
      );
    });

    test('曲长未知就退回绝对值那两条底线', () {
      expect(rewind(trackDuration: Duration.zero), isTrue);
      expect(
        rewind(
          previous: const Duration(seconds: 4),
          next: Duration.zero,
          trackDuration: Duration.zero,
        ),
        isFalse,
      );
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

  group('位置监察(冷流末尾那一支)', () {
    // 冷流(没有长度的源)上平台不切下一首、而是把这一首原地重放,而且**全程不给
    // Dart 任何信号**(没 `completed`、没暂停、没断点)。于是这条护栏是那一类源上
    // **唯一在切歌的一支** —— 它值得被真的测到,不只是测那个纯函数。
    late _FakePlayer player;
    late NordicAudioHandler handler;

    setUp(() {
      player = _FakePlayer();
      handler = NordicAudioHandler(() => null, QualityController(), player: player);
    });

    tearDown(() => player.dispose());

    /// 推一次位置,并让订阅者真的跑到。
    Future<void> emit(Duration position) async {
      player.position = position;
      player.positions.add(position);
      await pumpEventQueue();
    }

    test('平台放完一首原地回 0 —— 自己切下一首,而且只切一次', () async {
      await emit(const Duration(seconds: 200));
      await emit(Duration.zero);

      expect(player.seekToNextCalls, 1);
      expect(player.playCalls, 1);
    });

    test('换歌不算 —— 下标变了就不是「倒回开头」', () async {
      await emit(const Duration(seconds: 200));
      player.currentIndex = 1;
      await emit(Duration.zero);

      expect(player.seekToNextCalls, 0);
    });

    test('我们自己拖的 seek 不算 —— 用户想回到开头就让他回去', () async {
      await emit(const Duration(seconds: 200));
      await handler.seek(Duration.zero);
      await emit(Duration.zero);

      expect(player.seekToNextCalls, 0);
    });

    test('单曲循环不算 —— 那一支本来就该回到开头', () async {
      player.loopMode = LoopMode.one;
      await emit(const Duration(seconds: 200));
      await emit(Duration.zero);

      expect(player.seekToNextCalls, 0);
    });

    test('暂停期间那一跳要留住 —— 恢复播放时才判', () async {
      await emit(const Duration(seconds: 200));
      player.playing = false;
      // 平台趁暂停把这一首倒回开头:基线不许跟着走,否则这一跳就被抹掉了,
      // 用户一按播放还是同一首从 0 开始(原症状换个场景复发)。
      await emit(Duration.zero);
      expect(player.seekToNextCalls, 0, reason: '暂停时不动作');

      player.playing = true;
      await emit(Duration.zero);
      expect(player.seekToNextCalls, 1, reason: '恢复播放后这一跳要判出来');
    });

    test('位置已经不在开头附近就不动 —— 平台自己可能已经切了', () async {
      await emit(const Duration(seconds: 200));
      // 位置流那一条事件是滞后的:真的位置已经往前走开了,就不该再动它一刀。
      player.position = const Duration(seconds: 30);
      player.positions.add(Duration.zero);
      await pumpEventQueue();

      expect(player.seekToNextCalls, 0);
    });

    test('队列走到头 —— 要真的把播放器按住,不能只播报状态', () async {
      player.hasNext = false;
      await emit(const Duration(seconds: 200));
      await emit(Duration.zero);

      expect(player.pauseCalls, 1, reason: '不按住的后果是界面说放完了、扬声器还在响');
      expect(player.seekToNextCalls, 0);
    });
  });

  group('队列尾部时长', () {
    // 队列面板标题写的「还有约 ...」由它算出来。控制器那边要一个真的播放器
    // 才建得起来(测试环境没有那条平台通道),所以算术这部分单独提了出来。
    List<Song> songsOf(List<int> seconds) => [
          for (var i = 0; i < seconds.length; i++)
            Song(
              id: 's$i',
              title: '第 $i 首',
              artist: '艺人',
              album: '专辑',
              albumId: 'al-1',
              duration: Duration(seconds: seconds[i]),
            ),
        ];

    test('是后面那几首之和,不含当前这首', () {
      final queue = songsOf([10, 20, 30, 40]);
      expect(tailDurationAfter(queue, 0), const Duration(seconds: 90));
      expect(tailDurationAfter(queue, 1), const Duration(seconds: 70));
    });

    test('最后一首之后是零 —— 不是「还剩自己这一首」', () {
      final queue = songsOf([10, 20, 30]);
      expect(tailDurationAfter(queue, 2), Duration.zero);
    });

    test('还没落在队列里(或队列是空的)也返回零,不抛', () {
      expect(tailDurationAfter(songsOf([10]), 5), Duration.zero);
      expect(tailDurationAfter(const <Song>[], 0), Duration.zero);
      expect(tailDurationAfter(songsOf([10]), -1), Duration.zero);
    });

    test('与逐项相加完全一致 —— 换顺序不影响总和', () {
      final queue = songsOf([7, 11, 13, 17, 19]);
      for (var i = 0; i < queue.length; i++) {
        final naive = queue
            .skip(i + 1)
            .fold(Duration.zero, (sum, s) => sum + s.duration);
        expect(tailDurationAfter(queue, i), naive);
      }
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

    test('听过的那一首(缓存)也走本机,连网络地址都不拼', () {
      final cached = File('${dir.path}${Platform.pathSeparator}s1-medium.mp3')
        ..writeAsBytesSync([1, 2, 3]);
      var askedRemote = false;

      final origin = playbackOriginFor(
        song,
        cachedPath: cached.path,
        remote: () {
          askedRemote = true;
          return Uri.parse('http://nas.local/rest/stream.view?id=s1');
        },
      );

      expect(origin.local, isTrue);
      expect(origin.uri.toFilePath(), cached.path);
      // 缓存也是本机文件 —— 于是顺带离线可听,离线时根本拼不出网络地址。
      expect(askedRemote, isFalse);
    });

    test('下载优先于缓存 —— 下载的是原文件,缓存那份可能是转码过的', () {
      final downloaded =
          File('${dir.path}${Platform.pathSeparator}01 - 曲目.flac')
            ..writeAsBytesSync([1]);
      final cached = File('${dir.path}${Platform.pathSeparator}s1-medium.mp3')
        ..writeAsBytesSync([2]);

      final origin = playbackOriginFor(
        song,
        localPath: downloaded.path,
        cachedPath: cached.path,
        remote: () => Uri.parse('http://nas.local/rest/stream.view?id=s1'),
      );

      expect(origin.uri.toFilePath(), downloaded.path);
    });

    test('缓存被清掉了 —— 回退到网络,而不是播一个空', () {
      final gone = '${dir.path}${Platform.pathSeparator}清掉了.mp3';

      final origin = playbackOriginFor(
        song,
        cachedPath: gone,
        remote: () => Uri.parse('http://nas.local/rest/stream.view?id=s1'),
      );

      expect(origin.local, isFalse);
      expect(origin.uri.toString(), contains('nas.local'));
    });
  });

  group('要不要留新缓存', () {
    // 开关右边那句就是「流量下不缓存」,而留缓存同样在花流量 ——
    // 一整首歌会在后台被拉完。这一条判错的代价是用户的钱。
    test('开关关着:什么连接都留', () {
      for (final status in NetworkStatus.values) {
        expect(
          shouldWriteCache(wifiOnly: false, status: status),
          isTrue,
          reason: '开关关着时不该有任何门控($status)',
        );
      }
    });

    test('开关开着:计费连接上不留', () {
      expect(
        shouldWriteCache(wifiOnly: true, status: NetworkStatus.metered),
        isFalse,
      );
    });

    test('开关开着:Wi-Fi 与「问不出来」都照留', () {
      // 问不出来(桌面 / 平台通道异常)按能用处理 —— 门控是为了省流量,
      // 不是为了在问不出来的地方把功能锁死。
      for (final status in [
        NetworkStatus.unmetered,
        NetworkStatus.unknown,
        NetworkStatus.offline,
      ]) {
        expect(
          shouldWriteCache(wifiOnly: true, status: status),
          isTrue,
          reason: '$status 不该被当成计费连接',
        );
      }
    });
  });

  group('缓存接管:同一首只留最高那一份', () {
    // 路径里带着档位,同一首在 192 与 原音 本来各留一份、永远并存。这一组从
    // **处理器那一头**钉住整条链路:本机已有更高档那份 → 装载的就是那个文件
    // (而不是又拉一遍网络、又写第二份);换歌那一下把更低档那几份丢掉。

    late Directory root;
    late MediaCache cache;
    late _FakePlayer player;
    late NordicAudioHandler handler;

    const song = Song(
      id: 'song-1',
      title: '可能',
      artist: '程响',
      album: '可能',
      albumId: 'al-1',
      suffix: 'flac',
    );

    setUp(() async {
      root = await Directory.systemTemp.createTemp('nordic-takeover');
      cache = await MediaCache.open(
        limitBytes: CacheLimit.gb1.bytes,
        root: Directory('${root.path}${Platform.pathSeparator}audio'),
      );
      player = _FakePlayer();
      // 所选档是「均衡」,而本机留着的是原音那一份。
      handler = NordicAudioHandler(
        () => null,
        QualityController(QualityOption.medium),
        cache: cache,
        player: player,
      );
    });

    tearDown(() async {
      await player.dispose();
      cache.dispose();
      if (root.existsSync()) await root.delete(recursive: true);
    });

    /// 往缓存里写一份完整的那一份(走缓存自己算出来的位置)。
    Future<String> write(String qualityId, {String? format}) async {
      final file = cache.fileFor(song, qualityId: qualityId, format: format)!;
      await file.writeAsBytes(List<int>.filled(64, 1));
      await File('${file.path}.mime').writeAsString('audio/mpeg');
      await cache.prune();
      return file.path;
    }

    test('本机已有更高档那一份 —— 装的是那个文件,不再走网络', () async {
      final original = await write('original');

      await handler.setQueue(const [song], index: 0);

      expect(
        (player.loaded.first as ProgressiveAudioSource).uri.toFilePath(),
        original,
        reason: '白拿的音质:那一份已经在磁盘上,拿它播既不花流量也不会再写一份',
      );
    });

    test('所选档自己也有缓存时,更高档那份照样接管', () async {
      // 「先按均衡听过」(于是均衡那份落了盘)、「后来原音那份也完整了」——
      // 这是最容易漏的一种顺序。早先只在**所选档没有**缓存时才去找更高档,
      // 于是这一刻会一直播着均衡那份,而原音那份躺在盘上吃灰。
      final medium = QualityOption.medium;
      final original = await write('original');
      await write(medium.id, format: medium.format);

      await handler.setQueue(const [song], index: 0);

      expect(
        (player.loaded.first as ProgressiveAudioSource).uri.toFilePath(),
        original,
        reason: '手上有更好的那一份,就不该再拿低档的播',
      );
    });

    test('更高档那份完整之后,同曲更低档那几份让位', () async {
      final original = await write('original');
      final low = await write('low', format: 'mp3');
      expect(File(low).existsSync(), isTrue);

      await handler.setQueue(const [song], index: 0);
      // 换歌那一下:缓存那边据此记「正在听的是哪一份」并把更低档的丢掉。
      player.events.add(PlaybackEvent(currentIndex: 0));
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(File(low).existsSync(), isFalse, reason: '同一首只留最高那一份');
      expect(File(original).existsSync(), isTrue, reason: '正在听的是它,动不得');
    });
  });
}

/// 可摆布的播放器 —— 位置监察那条护栏只吃这几样(位置流、下标、循环模式、
/// 有没有下一首、几个命令),给个假的就够测,不必碰平台通道。
///
/// 继承真的 [AudioPlayer] 而不是另写一个接口:处理器要的就是这个类型,而它的
/// 构造函数在测试环境里本来就是惰性的(见上面那条「播放层无条件在场」)。
class _FakePlayer extends AudioPlayer {
  final positions = StreamController<Duration>.broadcast();

  /// 处理器订阅的那条播放事件流 —— 只用来推「换到第几首」这类事件
  /// (缓存那边「正在听的是哪一份」就挂在这条流上)。
  final events = StreamController<PlaybackEvent>.broadcast();

  /// 最近一次装载进去的播放源 —— 用来断言「装的是哪一份」。
  List<AudioSource> loaded = const [];

  int seekToNextCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  bool playing = true;

  @override
  int? currentIndex = 0;

  @override
  bool hasNext = true;

  @override
  LoopMode loopMode = LoopMode.off;

  @override
  Duration position = Duration.zero;

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    loaded = audioSources;
    return null;
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> seekToNext() async {
    seekToNextCalls++;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<void> dispose() async {
    await positions.close();
    await events.close();
  }
}