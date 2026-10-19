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
///
/// 再加上 2026-10-19 那一轮:**点两句才跳** —— 第一下只选中(行尾浮出
/// 「跳到这句 · 2:30」),同一句再点一下才落下去;点别的句子只是改选。
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

  /// 40 句、每 10 秒一句的时间轴歌词。第 [noStartAt] 句故意**不给起点** ——
/// 那是「整份有时间轴、偏偏这一句没有」的混合时间轴:那种行跳不到哪儿,
/// 界面就不该给它可以跳的样子。
  String lyricsPayload({bool synced = true}) => jsonEncode({
        'subsonic-response': {
          'status': 'ok',
          'version': '1.16.1',
          'lyricsList': {
            'structuredLyrics': [
              {
                'synced': synced,
                'line': [
                  for (var i = 0; i < 40; i++)
                    {
                      'value': '第 $i 句',
                      // 没有时间轴的那一份一句起点都不给 —— 高亮退回「按整首摊行」,
                      // 跳转也只能按时长反推(见 seekTargetForLine)。
                      if (synced) 'start': i * 10000,
                    },
                ],
              },
            ],
          },
        },
      });

  /// 这一次要吐哪份歌词 —— 绝大多数用例用默认那份。在 `fakeDio()` 建好之后
  /// 改它照样生效:拦截器是**请求那一刻**才读的。每条用例开头在 `setUp` 里归位。
  String Function() lyricsJson = lyricsPayload;

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
              ? lyricsJson()
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
    lyricsJson = lyricsPayload;
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
    Song? track,
  }) async {
    final playable = recordingController(track ?? song);
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

  /// 某一行那一整块(含上下行距)的盒子 —— 「选中不许把行顶高」那条靠它量。
  Rect rowBox(WidgetTester tester, String text) => tester.getRect(
        find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first,
      );

  testWidgets('刚进页就把当前句带到框中央 —— 不是停在第一句', (tester) async {
    // 放到 305 秒:该高亮的是第 30 句(起点 300 秒)。进歌词页时歌已经放了一半
    // 是常态,而这时候当前句离屏幕远得很。
    await pumpLyrics(tester, at: const Duration(seconds: 305));

    final list = tester.getRect(find.byType(SingleChildScrollView));
    final line = tester.getCenter(find.text('第 30 句'));
    expect(
      line.dy,
      closeTo(list.center.dy, 1.5),
      reason: '当前句要落在框中央。停在第一句（或者压根找不到这一行）都是'
          '「离屏幕远的行没被建出来」—— 那样 ensureVisible 无从下手',
    );
  });

  testWidgets('点某一句：先选中，同一句再点一下才跳，高亮跟着过去', (tester) async {
    final playable = await pumpLyrics(tester);
    expect(playable.seeks, isEmpty);

    final activeBefore = lineColor(tester, '第 0 句');
    final rowBefore = rowBox(tester, '第 1 句');

    // 第一下 = 只选中:行尾浮出「跳到这句」那颗胶囊,报出要落到哪儿。
    await tester.tap(find.text('第 1 句'));
    await tester.pumpAndSettle();

    expect(playable.seeks, isEmpty,
        reason: '跳转不可逆：第一下只该选中，不该跳走');
    expect(find.text('跳到这句 · 0:10'), findsOneWidget,
        reason: '第 1 句的起点是 10 秒 —— 胶囊要把落点报出来，'
            '否则「确认」只是个多余的点击');
    expect(rowBox(tester, '第 1 句').height, rowBefore.height,
        reason: '胶囊不许把行顶高（高 26 ≤ 文字盒高 30.8):'
            '点一句歌词不该让整列歌词挪位');

    // 第二下 = 跳。
    await tester.tap(find.text('第 1 句'));
    await tester.pumpAndSettle();

    expect(playable.seeks, [const Duration(seconds: 10)],
        reason: '点了第 1 句就该跳到它的起点（第 0 句是 0 秒、第 1 句是 10 秒）');
    expect(find.textContaining('跳到这句'), findsNothing, reason: '跳完胶囊收掉');
    expect(lineColor(tester, '第 1 句'), activeBefore,
        reason: '高亮要落到被点的那一句上 —— 这是「点第三句、高亮停第二句」的护栏');
    expect(find.byType(LyricsScreen), findsOneWidget, reason: '点句子是跳转，不是返回');
  });

  testWidgets('点另一句只是改选：胶囊搬家，还是不跳', (tester) async {
    final playable = await pumpLyrics(tester);

    await tester.tap(find.text('第 1 句'));
    await tester.pumpAndSettle();
    expect(find.text('跳到这句 · 0:10'), findsOneWidget);

    await tester.tap(find.text('第 3 句'));
    await tester.pumpAndSettle();

    expect(playable.seeks, isEmpty, reason: '改选不是跳');
    expect(find.text('跳到这句 · 0:10'), findsNothing, reason: '旧那颗胶囊要收掉');
    expect(find.text('跳到这句 · 0:30'), findsOneWidget);
    expect(find.byType(LyricsScreen), findsOneWidget);
  });

  testWidgets('句子上下那截行距也算点这一句', (tester) async {
    // 一行 = 文字框 + 上下各 11px 行距。看着还在这一行里,但默认的
    // `HitTestBehavior.deferToChild` 只命中文字本身 —— 那半截会漏给外层
    // 「点空白回封面」,症状是「点歌词没反应,还把歌词页关了」。
    final playable = await pumpLyrics(tester);

    // 一行 = 文字 + 上下各 11px 行距;那层行距属于**这一行**(Opacity 那块
    // 就是整行的盒子),但不属于文字。取行顶那 2px —— 一定在行距里。
    final text = tester.getRect(find.text('第 1 句'));
    final row = rowBox(tester, '第 1 句');
    expect(row.top, lessThan(text.top), reason: '行比文字高，上面那截就是行距');

    // 两下都点在行距上:确认那半截既算「选中」也算「确认」。
    await tester.tapAt(Offset(row.center.dx, row.top + 2));
    await tester.pumpAndSettle();
    expect(find.text('跳到这句 · 0:10'), findsOneWidget);
    expect(playable.seeks, isEmpty);

    await tester.tapAt(Offset(row.center.dx, row.top + 2));
    await tester.pumpAndSettle();

    expect(playable.seeks, [const Duration(seconds: 10)],
        reason: '行距上那半截也要算「点了这一句」');
    expect(find.byType(LyricsScreen), findsOneWidget,
        reason: '不能漏给外层，那一下会把歌词页关掉');
  });

  testWidgets('没有时间轴、连时长都还不知道时，点哪一句都不接', (tester) async {
    // 无时间轴的歌词本来就只能按时长摊行反推,而时长还不知道(播放器还没报回来)——
    // 那一刻纯属瞎猜。「跳不到就别装成跳了」:既不出现胶囊,也不跳。
    lyricsJson = () => lyricsPayload(synced: false);
    final playable = await pumpLyrics(
      tester,
      track: const Song(
        id: 's-lyrics-ui',
        title: '时长未知的一首',
        artist: '艺人',
        album: '专辑',
        albumId: 'al-1',
      ),
    );

    await tester.tap(find.text('第 1 句'));
    await tester.pumpAndSettle();

    expect(playable.seeks, isEmpty, reason: '不知道跳到哪儿，就别跳');
    expect(find.textContaining('跳到这句'), findsNothing,
        reason: '跳不了的地方不该装出「可以跳」的样子');
  });

  testWidgets('翻过歌词之后，宽限一过还是会把当前句拉回来', (tester) async {
    // 「让用户看一眼」不该变成「永远不回来」:长句子、间奏里几十秒不换行是
    // 常态,那时唯一会把视线拉回去的机会就是位置那几跳。
    //
    // 宽限比的是**真实时钟**,假时钟推不动它 —— 直接把宽限调没。
    addTearDown(() => lyricBrowseGrace = const Duration(seconds: 4));

    final playable = await pumpLyrics(tester, at: const Duration(seconds: 305));
    final list = tester.getRect(find.byType(SingleChildScrollView));


    // 手指翻一段(拖动手势才算「用户在翻」)。
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('第 30 句')).dy,
      isNot(closeTo(list.center.dy, 1.5)),
      reason: '刚翻过时确实让着他',
    );

    // 宽限过了,歌还在同一句上放着(位置在动、行没换)。
    lyricBrowseGrace = Duration.zero;
    playable.position.value = const Duration(seconds: 306);
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.text('第 30 句')).dy,
      closeTo(list.center.dy, 1.5),
      reason: '行没换也要把人拉回当前句上 —— 否则高亮一直停在屏幕外',
    );
  });

  testWidgets('点行以外的空白仍是回封面 —— 选中的那一句也一起没了', (tester) async {
    final playable = await pumpLyrics(tester);
    final list = tester.getRect(find.byType(SingleChildScrollView));

    // 先选中一句:「回封面」那条路不能因为多了一层确认就被吃掉。
    await tester.tap(find.text('第 1 句'));
    await tester.pumpAndSettle();
    expect(find.text('跳到这句 · 0:10'), findsOneWidget);

    // 框上缘那截内边距里没有句子 —— 那里是「回封面」那一下。
    await tester.tapAt(Offset(list.center.dx, list.top + 6));
    await tester.pumpAndSettle();

    expect(playable.seeks, isEmpty, reason: '空白那一下是退出，不是跳转');
    expect(find.byType(LyricsScreen), findsNothing,
        reason: '「点封面看歌词」的回头路不能因为「点句子跳转」被吃掉');
  });

  testWidgets('换行只重画那两行，整列歌词不重建', (tester) async {
    final playable = await pumpLyrics(tester, at: const Duration(seconds: 305));
    final listBefore = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    final activeBefore = lineColor(tester, '第 30 句');

    playable.position.value = const Duration(seconds: 315);
    await tester.pumpAndSettle();

    expect(
      identical(tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)), listBefore),
      isTrue,
      reason: '位置跳一下就重建了整列歌词（上百行）—— 那正是自动滚动那 260ms '
          '动画里掉帧的来源之一',
    );
    expect(lineColor(tester, '第 31 句'), activeBefore, reason: '高亮要跟到新那一句');
    expect(lineColor(tester, '第 30 句'), isNot(activeBefore),
        reason: '上一句要暗下去（过去那一档）');
  });
}
