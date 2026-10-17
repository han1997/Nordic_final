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
import 'package:nordic/ui/screens/playlist_screen.dart';
import 'package:nordic/ui/widgets/cover.dart';
import 'package:nordic/ui/widgets/rows.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 歌单详情把曲目铺成带**封面**的行 —— 真机反馈过「歌单里没有歌曲封面图」。
/// 这一组钉住那条:每一首歌都要有自己的封面([Cover])。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  Map<String, dynamic> ok(Map<String, dynamic> body) => {
        'subsonic-response': {
          'status': 'ok',
          'version': '1.16.1',
          ...body,
        }
      };

  /// `getPlaylist` 回几首。默认三首;惰性列表那条用例会把它调大。
  var playlistSongs = 3;

  /// `getPlaylist` 给若干首带封面的曲子。
  Dio fakeDio() {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        final endpoint = options.uri.pathSegments.last.replaceAll('.view', '');
        final payload = switch (endpoint) {
          'getPlaylist' => ok({
              'playlist': {
                'id': 'pl-1',
                'name': '深夜通勤',
                'songCount': playlistSongs,
                'entry': [
                  for (var i = 1; i <= playlistSongs; i++)
                    {
                      'id': 's$i',
                      'title': '第 $i 首',
                      'artist': '艺人',
                      'album': '专辑',
                      'albumId': 'al-1',
                      'coverArt': 'c$i',
                      'duration': 200,
                    }
                ],
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
  late PlaybackController playable;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    playlistSongs = 3;
    root = await Directory.systemTemp.createTemp('nordic-playlist-ui');

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

    playable = PlaybackController(
      NordicAudioHandler(() => state.repository, QualityController()),
    );
  });

  tearDown(() async {
    playable.dispose();
    playable.handler.player.dispose();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  testWidgets('歌单里每首歌都带封面', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<PlaybackController>.value(value: playable),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: const PlaylistScreen(playlistId: 'pl-1'),
        ),
      ),
    );
    // 这一屏是「挂完帧再去拉」的(见 playlist_screen 的 addPostFrameCallback),
    // 而 Dio 的拦截器链条最后落在**零延迟定时器**上 —— 光 pump() 推不动它,
    // 得让假时钟真的走一点时间。少这一下,屏上会一直停在「正在读取歌单」。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));

    // 三首歌 → 三张行内封面(头图那张也在,所以至少 4)。
    expect(find.byType(Cover), findsAtLeast(4));
    expect(find.text('第 1 首'), findsOneWidget);
    expect(find.text('第 3 首'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// 歌单是一张**能滚的懒列表**,不是一次性铺完的容器。
  ///
  /// 说清楚这条**守的是什么、不守什么**:`ListView(children: [...])` 在元素
  /// 层面本来就是懒的(实测 40 行同样只建 11 个元素),所以这条**分不出**
  /// `children:` 与 `.builder` 的区别;它拦的是哪天有人把列表换成
  /// `Column` / `shrinkWrap: true` 那种真的会把每一行都建出来的写法。
  testWidgets('几十首的歌单不会一次把每一行都建出来', (tester) async {
    playlistSongs = 40;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<PlaybackController>.value(value: playable),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: const PlaylistScreen(playlistId: 'pl-1'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));

    // 40 首确实在数据里(标题按服务器报的首数写)……
    expect(find.textContaining('40 首'), findsOneWidget);

    // ……但铺到屏幕上的只有一屏那么多。
    final built = tester.widgetList(find.byType(SongRow)).length;
    expect(built, greaterThan(0), reason: '一首都没建出来说明列表坏了');
    expect(built, lessThan(40), reason: '每一行都建出来了 —— 列表退化成了一次性铺完');
    expect(tester.takeException(), isNull);
  });
}
