import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/server_route.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/library_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_playback.dart';

/// 音乐库「回到正在播放」。
///
/// 这一颗按钮要解决的是**上千行的列表里回不去**那件事:从专辑 / 歌单 / 随机播起来的
/// 那一首,可能在任何一页上。三条判据:
///
///   1. 只在**歌曲栏**、而且**有在播的歌**时才出现(禁用态读起来像坏按钮);
///   2. 点一下真的滚到那一行(落点在视口里,不是「滚了个大概」);
///   3. 那一首还没取回来时,**如实说一句**,不假装跳过去了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  /// 库里有多少首 —— 要**足够长**,长到一屏铺不下(默认视口 800×600,
  /// 一行 64),否则「滚过去」这件事根本无从验起。
  const songCount = 60;

  Map<String, dynamic> ok(Map<String, dynamic> body) => {
        'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...body}
      };

  /// 曲目:**不给封面 id** —— 这一组不接网络图片(带了 id 就会去建 HttpClient)。
  /// 标题带序号,好按标题找那一行。
  List<Map<String, dynamic>> songs() => [
        for (var i = 0; i < songCount; i++)
          {
            'id': 's$i',
            'title': '第 $i 首',
            'artist': '艺人',
            'album': '专辑',
            'albumId': 'al-1',
            'duration': 200,
          }
      ];

  Dio fakeDio() {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        final endpoint = options.uri.pathSegments.last.replaceAll('.view', '');
        final payload = switch (endpoint) {
          'search3' => ok({
              'searchResult3': {'song': songs()},
            }),
          'getAlbumList2' => ok({
              'albumList2': {
                'album': [
                  {
                    'id': 'al-1',
                    'name': '专辑',
                    'artist': '艺人',
                    'artistId': 'ar-1',
                    'songCount': songCount,
                  }
                ]
              }
            }),
          _ => ok(const {}),
        };
        interceptor.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode(payload),
        ));
      },
    ));
    return dio;
  }

  late Directory root;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-library-ui');
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
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// 拉一次库。**必须走 `runAsync`**:`loadLibrary` 要真写一次缓存文件,
  /// 而 `testWidgets` 的 FakeAsync 时钟下真 I/O 永远等不回来。
  Future<void> loadLibrary(WidgetTester tester) =>
      tester.runAsync(() => state.loadLibrary());

  /// 一首「在别处播起来的」曲子 —— [id] 取库里的某一首,或者库里没有的。
  Song playingSong({String id = 's30', String title = '第 30 首'}) => Song(
        id: id,
        title: title,
        artist: '艺人',
        album: '专辑',
        albumId: 'al-1',
        duration: const Duration(seconds: 200),
      );

  Future<void> pumpLibrary(WidgetTester tester, Song? playing) async {
    // 没在播时给**一份 song 为 null 的播放层**,而不是随便塞一首 —— 这一屏
    // 看的就是 `currentSongId` 是不是 null。
    final playable = playing == null
        ? idleController()
        : playingController(playing, playing: true);
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
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// 「定位」那一下的收尾:切栏 + 一帧布局 + 估一步跳 + 对齐那 260ms 的动画。
  /// **不能用 `pumpAndSettle`** —— 转圈指示器与播放中的跳动条一直在动。
  Future<void> settleLocate(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets('没在播任何东西时，这颗按钮不出现', (tester) async {
    await loadLibrary(tester);
    await pumpLibrary(tester, null);

    expect(find.byIcon(Icons.my_location), findsNothing);
  });

  testWidgets('在播时它出现在歌曲栏；切到别的栏就没有它', (tester) async {
    await loadLibrary(tester);
    await pumpLibrary(tester, playingSong());

    expect(find.byIcon(Icons.my_location), findsOneWidget);

    // 专辑栏管的是「库里有什么」,这一颗按钮在那里没有意义(它只回答
    // 「正在放的那一首在列表的哪儿」)。
    await tester.tap(find.text('专辑'));
    await tester.pump();
    expect(find.byIcon(Icons.my_location), findsNothing);
  });

  testWidgets('点一下：滚到正在播放那一行，而它在视口里', (tester) async {
    await loadLibrary(tester);
    await pumpLibrary(tester, playingSong());

    // 起点:那一行离得很远(第 30 首 × 64 ≈ 1900px,一屏 600)。
    final viewport = tester.getRect(find.byType(LibraryScreen));
    expect(find.text('第 30 首'), findsNothing, reason: '它本就不该一开始就在屏幕上');

    await tester.tap(find.byIcon(Icons.my_location));
    await settleLocate(tester);

    final row = find.text('第 30 首');
    expect(row, findsOneWidget, reason: '滚过去之后这一行该建出来了');
    final rect = tester.getRect(row);
    expect(rect.top >= viewport.top - 1 && rect.bottom <= viewport.bottom + 1, isTrue,
        reason: '落点该在视口里（实测 ${rect.top}–${rect.bottom}，视口 $viewport)');
  });

  testWidgets('正在放的那一首不在已取回的列表里：如实说一句', (tester) async {
    await loadLibrary(tester);
    // 「全部歌曲」是一页页取的,而在别处(歌单 / 专辑 / 随机)播起来的曲子
    // 完全可能落在还没取到的那些页里 —— 那时不能假装跳过去了。
    await pumpLibrary(tester, playingSong(id: 's-并不存在', title: '不在库里的那首'));

    await tester.tap(find.byIcon(Icons.my_location));
    await settleLocate(tester);

    expect(find.textContaining('不在已经取回来的曲目里'), findsOneWidget);
  });
}