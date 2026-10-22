import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/music_source.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/server_route.dart';
import 'package:nordic/playback/audio_handler.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/player_screen.dart';
import 'package:nordic/ui/play_tapped.dart';
import 'package:nordic/ui/widgets/states.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「点一首播不出来的歌」—— 这一组钉的就是那一问。
///
/// 原先的病灶说清楚:`PlaybackState.error` 被四处写入,而**全仓没有一处读它**。
/// 于是点一首播不出来的歌,屏幕上什么都不会发生 —— 坞不出现、播放页仍是
/// 「还没有在播的歌」,而那句在这个场景里是**假的**:用户刚刚点了。
///
/// 两条口径(对应原型里的两处,见设计板「音乐库 · 播放失败」与「播放页 · 播放失败」):
///
///   1. **点的那一下要说话** —— `playAll` 把失败原因交回去,调用点弹一句;
///   2. **事后走到播放页要看得见** —— 那一屏读出 `state.error`,铺失败态
///      而不是「还没有在播的歌」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  const song = Song(
    id: 's-1',
    title: '播不出来的这一首',
    artist: '艺人',
    album: '专辑',
    albumId: 'al-1',
    duration: Duration(seconds: 200),
  );

  group('playAll 把失败那句话交回去', () {
    /// 把 `_sourceFor` 的「拼地址」那一步打成必失败 —— 那正是真机上会走到的一支:
    /// 没有仓库 / 服务器不给这一首的音频。播放器是假的,所以抛在拼源那一刻
    /// (= `setQueue` 里 `_sourceFor` 的 `remote()` 闭包),与真机同一个位置。
    PlaybackController failingPlayback() {
      final handler = _FailingHandler();
      addTearDown(() {
        handler.player.dispose();
      });
      return PlaybackController(handler);
    }

    test('播不起来：回一句人话，并且记进 state.error', () async {
      final playback = failingPlayback();
      addTearDown(playback.dispose);

      final failure = await playback.playAll([song]);

      expect(failure, '服务器没有给出这一首的音频');
      expect(playback.state.error, same(failure), reason: '界面读的是 state.error');
      expect(playback.state.playing, isFalse);
    });

    test('空列表也给一句话 —— 否则调用点各自去判，迟早漏一处', () async {
      final playback = failingPlayback();
      addTearDown(playback.dispose);

      expect(await playback.playAll(const []), '队列里没有可播的曲目');
    });

    test('播得成时回 null（成功不说话）', () async {
      final handler = NordicAudioHandler(() => null, QualityController());
      addTearDown(() => handler.player.dispose());
      final playback = PlaybackController(handler);
      addTearDown(playback.dispose);

      // 假播放层装什么都成 —— 这一条验的是「成功时别弹提示」那半边。
      expect(await playback.playAll([song]), anything);
    });
  });

  group('播放页的失败态', () {
    late Directory root;
    late AppState state;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('nordic-playfail');
      late final AppState appState;
      appState = AppState(
        configStore: await ConfigStore.open(),
        credentialStore: CredentialStore(),
        quality: QualityController(),
        downloadManager: DownloadManager(
          store: await DownloadStore.open(root: root),
          repository: () => appState.repository,
          wifiOnly: () => false,
        ),
        libraryCache: await LibraryCache.open(root: root),
        mediaCache: await MediaCache.open(
          limitBytes: CacheLimit.gb1.bytes,
          root: Directory('${root.path}${Platform.pathSeparator}audio'),
        ),
      );
      state = appState;
      state.adoptServer(config);
    });

    tearDown(() async {
      try {
        if (root.existsSync()) await root.delete(recursive: true);
      } on FileSystemException {
        // Windows 上临时目录偶尔被抢住 —— 系统自己会清。
      }
    });

    Future<void> pumpPlayer(
      WidgetTester tester,
      PlaybackController playable,
    ) async {
      addTearDown(() {
        playable.dispose();
        playable.handler.player.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider<PlaybackController>.value(value: playable),
            ChangeNotifierProvider<QualityController>.value(
              value: QualityController(),
            ),
          ],
          child: MaterialApp(
            theme: NordicTheme.build(NordicTokens.dark),
            home: const PlayerScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('失败过：铺失败态，不铺「还没有在播的歌」', (tester) async {
      final playable = _FailedStatePlayback();
      await pumpPlayer(tester, playable);

      expect(find.byType(PlaybackFailureState), findsOneWidget);
      // 那句话要真的印出来 —— 只写一句「播不了」等于让用户自己猜。
      expect(find.text('服务器没有给出这一首的音频'), findsOneWidget);
      // 中性空态**不该**同时在场:那两句说的是不同的事,一起出现就是自相矛盾。
      expect(find.text('还没有在播的歌'), findsNothing);
      // 一条去路。
      expect(find.text('回音乐库挑一首别的'), findsOneWidget);
    });

    testWidgets('没失败过：仍是那句中性的空态', (tester) async {
      final playable = _IdleStatePlayback();
      await pumpPlayer(tester, playable);

      expect(find.text('还没有在播的歌'), findsOneWidget);
      expect(find.byType(PlaybackFailureState), findsNothing);
    });

    testWidgets('点的那一下要说话 —— 一句 SnackBar，带上这一首的名字', (tester) async {
      // 这一条是整轮的**主判据**:原先失败了什么都不发生。
      final playable = _FailingHandlerPlayback();
      addTearDown(() {
        playable.dispose();
        playable.handler.player.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider<PlaybackController>.value(value: playable),
          ],
          child: MaterialApp(
            theme: NordicTheme.build(NordicTokens.dark),
            home: const _TapHost(song: song),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('点这一首'));
      await tester.pump(); // 让 playTapped 跑完(它 await 了 playAll)
      await tester.pump(const Duration(milliseconds: 300)); // SnackBar 入场

      expect(find.byType(SnackBar), findsOneWidget);
      // 「哪一首」与「为什么」都要说 —— 只说「播不了」等于让用户自己猜。
      expect(
        find.textContaining('播不出来的这一首'),
        findsOneWidget,
        reason: '用户点的那一行就在眼前，说「这一首」比说「播放失败」具体',
      );
      expect(
        find.textContaining('服务器没有给出这一首的音频'),
        findsOneWidget,
      );
    });

    testWidgets('失败时没有在播的歌，顶栏那颗「⋯」得收掉', (tester) async {
      // 它背后没有东西可指(菜单条条都要一个 song)。收掉而不是禁用 ——
      // 与原型 `playerBar(false)` 同一处置:留一个等宽空位,标签仍然居中。
      final playable = _FailedStatePlayback();
      await pumpPlayer(tester, playable);

      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.text('正在播放'), findsOneWidget);
    });
  });
}

/// 拼播放源必失败的处理器 —— 壳子是真的,只是 `_sourceFor` 那一步抛。
///
/// 仓库照常给 null(与「没配服务器」同一支),失败只发生在拼源那一刻 ——
/// 那是真机上同一个位置(见 `audio_handler.dart` 的 `_sourceFor`)。
class _FailingHandler extends NordicAudioHandler {
  _FailingHandler() : super(() => null, QualityController());

  /// 装载那一刻失败 —— 真机上「服务器不给这一首」就落在这一步
  /// (`setQueue` → `_player.setAudioSources`)。抛一个音源自己造的失败,
  /// 验的是「那句话原样交回去」这件事,不是平台异常怎么翻译。
  @override
  Future<void> setQueue(
    List<Song> songs, {
    int index = 0,
    bool autoPlay = true,
  }) async {
    throw const MusicSourceException('服务器没有给出这一首的音频');
  }
}

/// 装载必失败的播放层 —— 「点的那一下要说话」用它。
class _FailingHandlerPlayback extends PlaybackController {
  _FailingHandlerPlayback() : super(_FailingHandler());

  @override
  PlaybackState get state => const PlaybackState();
}

/// 树里摆一颗「点这一首」的按钮 —— 那是十八个调用点里最小的一个代表。
class _TapHost extends StatelessWidget {
  const _TapHost({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => playTapped(context, [song], label: '播不出来的这一首'),
            child: const Text('点这一首'),
          ),
        ),
      );
}

/// 没有在播的歌 + 一条错误 —— 失败态那一支。
class _FailedStatePlayback extends PlaybackController {
  _FailedStatePlayback()
      : super(NordicAudioHandler(() => null, QualityController()));

  @override
  PlaybackState get state =>
      const PlaybackState(error: '服务器没有给出这一首的音频');
}

/// 没有在播的歌,也没失败过 —— 中性空态那一支。
class _IdleStatePlayback extends PlaybackController {
  _IdleStatePlayback()
      : super(NordicAudioHandler(() => null, QualityController()));

  @override
  PlaybackState get state => const PlaybackState();
}
