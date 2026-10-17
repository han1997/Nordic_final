import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/lyrics_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_playback.dart';

/// 歌词页 —— 三件事,每一件都对应真机上的一次报障:
///
/// 1. **刚点进歌词页停在第一句**(当前句离屏幕远时永远跳不过去);
/// 2. **点某一句不能跳到那一段**(点句子原先只当「回封面」);
/// 3. **跳转动画一顿一顿** —— 位置每跳一下就整屏重建一次(含上百行歌词)。
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
    id: 's-lyrics-ui',
    title: '带时间轴的一首',
    artist: '艺人',
    album: '专辑',
    albumId: 'al-1',
    duration: Duration(seconds: 400),
  );

  /// 40 句、每 10 秒一句的时间轴歌词。
  String lyricsPayload() => jsonEncode({
        'subsonic-response': {
          'status': 'ok',
          'version': '1.16.1',
          'lyricsList': {
            'structuredLyrics': [
              {
                'synced': true,
                'line': [
                  for (var i = 0; i < 40; i++)
                    {'value': '第 $i 句', 'start': i * 10000},
                ],
              },
            ],
          },
        },
      });

  Dio fakeDio() {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        final wantsLyrics =
            options.uri.toString().contains('getLyricsBySongId');
        interceptor.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: wantsLyrics
              ? lyricsPayload()
              : jsonEncode({
                  'subsonic-response': {'status': 'ok', 'version': '1.16.1'}
                }),
        ));
      },
    ));
    return dio;
  }

  late Directory root;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-lyrics-ui');

    // 歌词的磁盘缓存要找「应用支持目录」(`path_provider`)。这个插件在 widget
    // 测试里**既不给结果也不抛错**(那条平台通道的回执要真事件循环才送得回来,
    // 而 testWidgets 的时间是假的)—— 于是 `lyricsFor` 会一直挂着,页面停在
    // 「正在读取歌词」。给它一个真的目录:顺便把 `cache/` 先建出来,
    // 免得 `_lyricsCacheFile` 走 `create`(那也是一次异步 IO,同样卡住)。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => root.path,
    );
    Directory('${root.path}${Platform.pathSeparator}cache').createSync();

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
      dio: fakeDio(),
    );
    state = appState;
    state.adoptServer(config);
    state.attachRepository(config, 'p');
  });

  tearDown(() async {
    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } on FileSystemException {
      // Windows 上临时目录偶尔被抢住(文件句柄还没松)—— 系统自己会清。
    }
  });

  /// 推一屏歌词页上去。**底下要留一屏** —— 「点空白回封面」那条要有东西可回。
  Future<RecordingPlayback> pumpLyrics(
    WidgetTester tester, {
    Duration at = Duration.zero,
  }) async {
    final playable = recordingController(song);
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
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    // **建完树再摆位置**:替身背后那个真的 `AudioPlayer` 一被订阅就会把 0 送进来
    // (那条流先发一个初值),早设的话会被它盖掉 —— 于是「歌已经放到中段」这件事
    // 在测试里根本没发生,断言出来的全是第一句。
    //
    // 位置先摆好、歌词页再推上来,正是真机上的那一程:人进来时歌已经放了一半。
    playable.position.value = at;

    Navigator.of(tester.element(find.byType(Scaffold).first)).push(
      MaterialPageRoute<void>(builder: (_) => const LyricsScreen()),
    );
    await tester.pumpAndSettle();
    return playable;
  }

  /// 某一句现在被画成什么颜色 —— 高亮(亮 / 暗 / 过去)全在颜色上。
  /// 取的是那个 `AnimatedDefaultTextStyle` 的**目标**样式,不跟着动画等。
  Color lineColor(WidgetTester tester, String text) => tester
      .widget<AnimatedDefaultTextStyle>(find
          .ancestor(
            of: find.text(text),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first)
      .style
      .color!;

  testWidgets('刚进页就把当前句带到框中央 —— 不是停在第一句', (tester) async {
    // 放到 305 秒:该高亮的是第 30 句(起点 300 秒)。进歌词页时歌已经放了一半
    // 是常态,而这时候当前句离屏幕远得很。
    await pumpLyrics(tester, at: const Duration(seconds: 305));

    final list = tester.getRect(find.byType(SingleChildScrollView));
    final line = tester.getCenter(find.text('第 30 句'));
    expect(
      line.dy,
      closeTo(list.center.dy, 1.5),
      reason: '当前句要落在框中央。停在第一句(或者压根找不到这一行)都是'
          '「离屏幕远的行没被建出来」—— 那样 ensureVisible 无从下手',
    );
  });

  testWidgets('点某一句跳到那一段,高亮跟着过去', (tester) async {
    final playable = await pumpLyrics(tester);
    expect(playable.seeks, isEmpty);

    final activeBefore = lineColor(tester, '第 0 句');
    await tester.tap(find.text('第 1 句'));
    await tester.pumpAndSettle();

    expect(playable.seeks, [const Duration(seconds: 10)],
        reason: '点了第 1 句就该跳到它的起点(第 0 句是 0 秒、第 1 句是 10 秒)');
    expect(lineColor(tester, '第 1 句'), activeBefore,
        reason: '高亮要落到被点的那一句上 —— 这是「点第三句、高亮停第二句」的护栏');
    expect(find.byType(LyricsScreen), findsOneWidget, reason: '点句子是跳转,不是返回');
  });

  testWidgets('点行以外的空白仍是回封面', (tester) async {
    await pumpLyrics(tester);
    final list = tester.getRect(find.byType(SingleChildScrollView));

    // 框上缘那截内边距里没有句子 —— 那里是「回封面」那一下。
    await tester.tapAt(Offset(list.center.dx, list.top + 6));
    await tester.pumpAndSettle();

    expect(find.byType(LyricsScreen), findsNothing,
        reason: '「点封面看歌词」的回头路不能因为「点句子跳转」被吃掉');
  });

  testWidgets('换行只重画那两行,整列歌词不重建', (tester) async {
    final playable = await pumpLyrics(tester, at: const Duration(seconds: 305));
    final listBefore = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    final activeBefore = lineColor(tester, '第 30 句');

    playable.position.value = const Duration(seconds: 315);
    await tester.pumpAndSettle();

    expect(
      identical(tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)), listBefore),
      isTrue,
      reason: '位置跳一下就重建了整列歌词(上百行)—— 那正是自动滚动那 260ms '
          '动画里掉帧的来源之一',
    );
    expect(lineColor(tester, '第 31 句'), activeBefore, reason: '高亮要跟到新那一句');
    expect(lineColor(tester, '第 30 句'), isNot(activeBefore),
        reason: '上一句要暗下去(过去那一档)');
  });
}