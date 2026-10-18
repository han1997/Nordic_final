import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/playback/audio_handler.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/home_screen.dart';
import 'package:nordic/ui/screens/library_screen.dart';
import 'package:nordic/ui/widgets/album_rail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 重建的**范围**。
///
/// `AppState` 把下载进度(最多每秒四次)与音频缓存的淘汰**原样转发**给全应用
/// (见 `app_state.dart`:界面只订阅它一个对象),所以「下载在跑」或者「切了一首歌」
/// 这类事,本来会让四百多张专辑的网格跟着重建一遍 —— 而它们一点都不关心下载。
/// 首页与音乐库因此改成只 `select` 自己真正读到的那几件。
///
/// 这一组把边界钉在两处,缺一不可:
///   - 进度跳动**不该**重建它们(否则等于没优化);
///   - 它们真正订阅的东西变了**必须**重建(否则就是把界面收成了不更新)。
/// 判据用「同一个 Widget 实例还在树上吗」—— 父级没重建时,框架保留原实例。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  /// 货架上的专辑名。**每次取库都可能换一个** —— 「真正订阅的东西变了
  /// 必须重建」那一半就靠它翻面。
  var tag = 'A';

  Map<String, dynamic> ok(Map<String, dynamic> body) => {
        'subsonic-response': {
          'status': 'ok',
          'version': '1.16.1',
          ...body,
        }
      };

  Map<String, dynamic> albumsPayload(String type) => ok({
        'albumList2': {
          'album': [
            {
              'id': 'al-$tag-$type',
              'name': '$tag-$type',
              'artist': '艺人',
              'artistId': 'ar-1',
              'songCount': 1,
            }
          ]
        }
      });

  Map<String, dynamic> songsPayload() => ok({
        'searchResult3': {
          'song': [
            {
              'id': 's-1',
              'title': '可能',
              'artist': '程响',
              'album': '可能',
              'albumId': 'al-1',
              'duration': 200,
              'created': '2026-10-12T00:00:00.000Z',
            }
          ]
        }
      });

  Dio fakeDio() {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        final endpoint = options.uri.pathSegments.last.replaceAll('.view', '');
        final type = options.uri.queryParameters['type'];
        final payload = switch (endpoint) {
          'getAlbumList2' => albumsPayload(switch (type) {
              'recent' => '最近播放',
              'frequent' => '最常播放',
              _ => '全部专辑',
            }),
          'search3' => songsPayload(),
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
  late MediaCache audioCache;
  late AppState state;
  late PlaybackController playable;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tag = 'A';
    root = await Directory.systemTemp.createTemp('nordic-rebuild-scope');
    audioCache = await MediaCache.open(
      limitBytes: CacheLimit.gb1.bytes,
      root: Directory('${root.path}${Platform.pathSeparator}audio'),
    );

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
      mediaCache: audioCache,
      dio: fakeDio(),
    );
    state = appState;
    state.adoptServer(config);
    state.attachRepository(config, 'p');

    playable = PlaybackController(
      NordicAudioHandler(() => state.repository, QualityController()),
    );
  });

  tearDown(() async {
    playable.dispose();
    playable.handler.player.dispose();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// 拉一次库。**必须走 `runAsync`**:`loadLibrary` 要真写一次缓存文件,
  /// 而 `testWidgets` 的假时钟下真 I/O 等不回来。
  Future<void> loadLibrary(WidgetTester tester) =>
      tester.runAsync(() => state.loadLibrary());

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<PlaybackController>.value(value: playable),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: screen,
        ),
      ),
    );
    // 不用 pumpAndSettle:转圈指示器永远在动,settle 不下来。
    await tester.pump();
    await tester.pump();
  }

  /// 货架上的第一条曲目名 —— 用**文本**当判据,而不是只看实例:
  /// 这样「真的画出了新数据」与「压根没重建」两种失败都会露出来。
  String firstRailName(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(of: find.byType(AlbumRail), matching: find.byType(Text)),
      )
      .first
      .data!;

  AlbumRail firstRail(WidgetTester tester) =>
      tester.widgetList<AlbumRail>(find.byType(AlbumRail)).first;

  testWidgets('首页：下载进度跳动不重建货架', (tester) async {
    await loadLibrary(tester);
    await pump(tester, const HomeScreen());
    expect(firstRailName(tester), contains('A-最近播放'));

    final before = firstRail(tester);
    state.downloadManager.notifyListeners();
    await tester.pump();

    expect(identical(firstRail(tester), before), isTrue,
        reason: '首页没有订阅下载，进度跳动不该把它重建一遍');
    expect(firstRailName(tester), contains('A-最近播放'));
  });

  testWidgets('首页：缓存淘汰的播报也不重建货架', (tester) async {
    await loadLibrary(tester);
    await pump(tester, const HomeScreen());

    final before = firstRail(tester);
    audioCache.notifyListeners();
    await tester.pump();

    expect(identical(firstRail(tester), before), isTrue,
        reason: '首页不显示缓存占用，它不该跟着缓存的播报重建');
  });

  testWidgets('首页：库真的换了照旧重建 —— 收窄不能收成「不更新」', (tester) async {
    await loadLibrary(tester);
    await pump(tester, const HomeScreen());
    expect(firstRailName(tester), contains('A-最近播放'));

    tag = 'B';
    await loadLibrary(tester);
    await tester.pump();

    expect(firstRailName(tester), contains('B-最近播放'));
  });

  testWidgets('音乐库：下载进度跳动不重建，库换了照旧重建', (tester) async {
    await loadLibrary(tester);
    await pump(tester, const LibraryScreen());
    expect(find.text('B-全部专辑'), findsNothing);

    // 默认落在「歌曲」那一栏,先切到专辑才看得见网格。
    await tester.tap(find.text('专辑'));
    await tester.pump();
    expect(find.text('A-全部专辑'), findsOneWidget);

    final before = tester.widget<Text>(find.text('A-全部专辑'));
    state.downloadManager.notifyListeners();
    await tester.pump();
    expect(identical(tester.widget<Text>(find.text('A-全部专辑')), before), isTrue,
        reason: '这一栏不显示下载进度，不该跟着它重建');

    tag = 'B';
    await loadLibrary(tester);
    await tester.pump();
    expect(find.text('B-全部专辑'), findsOneWidget);
  });
}