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
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/search_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_playback.dart';

/// 搜索打的是**服务器**(`search3`)。这一组只钉一件事:同一个词再打一遍
/// 不该再打一次服务器 —— 「删一个字再打回来」是最常见的改字方式,而那样
/// 服务器白跑一趟、用户白等一次往返。
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
    title: '可能',
    artist: '程响',
    album: '可能',
    albumId: 'al-1',
    duration: Duration(seconds: 200),
  );

  late Directory root;
  late AppState state;
  late List<Uri> seen;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-search');
    seen = [];

    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        seen.add(options.uri);
        final query = options.uri.queryParameters['query'] ?? '';
        interceptor.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'version': '1.16.1',
              'searchResult3': {
                'song': [
                  {
                    'id': 'hit-$query',
                    'title': '命中 $query',
                    'artist': '艺人',
                    'album': '专辑',
                    'albumId': 'al-1',
                    'duration': 200,
                  },
                ],
              },
            },
          }),
        ));
      },
    ));

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
      dio: dio,
    );
    appState.adoptServer(config);
    appState.attachRepository(config, 'p');
    state = appState;
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  int searches() => seen.where((u) => u.path.contains('search3')).length;

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    // 去抖 300ms —— 推过去它才会真的发请求。
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('同一个词再打一遍不再打服务器', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<PlaybackController>.value(
              value: playingController(song)),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: const SearchScreen(),
        ),
      ),
    );

    await type(tester, 'ab');
    expect(searches(), 1);
    expect(find.text('命中 ab'), findsOneWidget);

    // 删一个字 —— 那是另一个词,该问。
    await type(tester, 'a');
    expect(searches(), 2);

    // 再打回来:**同一个词**,盘上/服务器上都没有新东西可问。
    await type(tester, 'ab');
    expect(searches(), 2, reason: '同一个词刚问过，不该再打一次服务器');
    expect(find.text('命中 ab'), findsOneWidget, reason: '结果照旧铺出来');
  });
}
