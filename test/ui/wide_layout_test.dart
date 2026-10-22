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
import 'package:nordic/ui/adaptive/window.dart';
import 'package:nordic/ui/routes.dart';
import 'package:nordic/ui/screens/library_screen.dart';
import 'package:nordic/ui/screens/player_screen.dart';
import 'package:nordic/ui/screens/settings_screen.dart';
import 'package:nordic/ui/widgets/album_grid.dart';
import 'package:nordic/ui/widgets/cover.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_playback.dart';

/// 宽屏的具体版面:网格列数、播放页两栏、设置页限宽。
///
/// 网格与设置都在**主壳里**量 —— 竖栏那 104 的让位是壳给出来的,单独 pump
/// 那一屏量到的宽度不是线上看到的;播放页没有竖栏,直接 pump。
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
        'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...body}
      };

  /// 8 张专辑 —— 够在 1280 下铺满第一行(4 列)并分组。
  /// **不给封面 id**:这一组不接网络图片(与 library_screen_test 同一条)。
  List<Map<String, dynamic>> albums() => [
        for (var i = 0; i < 8; i++)
          {
            'id': 'al-$i',
            'name': '专辑 $i',
            'artist': '艺人',
            'artistId': 'ar-1',
            'songCount': 3,
          }
      ];

  Dio fakeDio() {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        final endpoint = options.uri.pathSegments.last.replaceAll('.view', '');
        final payload = switch (endpoint) {
          'getAlbumList2' => ok({
              'albumList2': {'album': albums()},
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
  late QualityController quality;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-wide-layout-ui');
    quality = QualityController();
    late final AppState appState;
    appState = AppState(
      configStore: await ConfigStore.open(),
      credentialStore: CredentialStore(),
      quality: quality,
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

  /// 拉一次库(**先于** pump 主壳):`loadLibrary` 要真写缓存文件,得走
  /// `runAsync`;拉完 phase 不再是 idle,主壳首帧那条取库路径就会短路 ——
  /// 否则 FakeAsync 时钟会在真 I/O 上挂住(与 library_screen_test 同一条)。
  Future<void> loadLibrary(WidgetTester tester) =>
      tester.runAsync(() => state.loadLibrary());

  void windowAt(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
  }

  List<ChangeNotifierProvider> providers(PlaybackController playable) => [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<PlaybackController>.value(value: playable),
        ChangeNotifierProvider<QualityController>.value(value: quality),
      ];

  /// 音乐库「专辑」栏 —— 外面套着**壳给的同款让位**([NavGutter]):竖栏那
  /// 104 是壳统一给出的几何,这里用同一只 widget 复现;单独 pump 主壳会带起
  /// 它首帧的取库与队列恢复检查(FakeAsync 下留下 pending Timer),
  /// 那不是这一组要验的版面。
  Future<void> pumpLibraryAlbums(WidgetTester tester) async {
    final playable = idleController();
    addTearDown(() {
      playable.dispose();
      playable.handler.player.dispose();
    });
    await tester.pumpWidget(MultiProvider(
      providers: providers(playable),
      child: MaterialApp(
        theme: NordicTheme.build(NordicTokens.dark),
        onGenerateRoute: AppRoutes.generate,
        home: const NavGutter(child: LibraryScreen()),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // 默认落在「歌曲」栏,切到「专辑」才有网格。
    await tester.tap(find.text('专辑'));
    await tester.pump();
    await tester.pump();
  }

  /// 网格第一行有几格 —— 按 AlbumTile 的 top 分组数(误差 1px 以内算同一行)。
  int firstRowTiles(WidgetTester tester) {
    final finder = find.byType(AlbumTile);
    final n = finder.evaluate().length;
    if (n == 0) return 0;
    final firstTop = tester.getTopLeft(finder.first).dy;
    var count = 0;
    for (var i = 0; i < n; i++) {
      if ((tester.getTopLeft(finder.at(i)).dy - firstTop).abs() < 1) count++;
    }
    return count;
  }

  testWidgets('专辑网格：1280 四列；800 与 390 仍是两列', (tester) async {
    addTearDown(tester.view.reset);
    await loadLibrary(tester);

    windowAt(tester, const Size(1280, 800));
    await pumpLibraryAlbums(tester);
    expect(firstRowTiles(tester), 4,
        reason: '1280 − 104（竖栏让位）− 40（格内边距）= 1136 → ceil(1136 / 296) = 4');

    // medium 恒两列 —— 单靠除式,800 宽会算出 3 列;那是不允许发生的。
    windowAt(tester, const Size(800, 1000));
    await pumpLibraryAlbums(tester);
    expect(firstRowTiles(tester), 2);

    windowAt(tester, const Size(390, 844));
    await pumpLibraryAlbums(tester);
    expect(firstRowTiles(tester), 2);
    expect(tester.takeException(), isNull);
  });

  const playing = Song(
    id: 's-1',
    title: '两栏里的歌',
    artist: '艺人',
    album: '专辑',
    albumId: 'al-1',
    duration: Duration(seconds: 200),
  );

  Future<void> pumpPlayer(WidgetTester tester) async {
    final playable = playingController(playing);
    addTearDown(() {
      playable.dispose();
      playable.handler.player.dispose();
    });
    await tester.pumpWidget(MultiProvider(
      providers: providers(playable),
      child: MaterialApp(
        theme: NordicTheme.build(NordicTokens.dark),
        onGenerateRoute: AppRoutes.generate,
        home: const PlayerScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('播放页：1280 两栏（封面整块在信息左侧）；800 仍是单列居中', (tester) async {
    addTearDown(tester.view.reset);

    windowAt(tester, const Size(1280, 800));
    await pumpPlayer(tester);
    final coverWide = tester.getRect(find.byType(Cover));
    final titleWide = tester.getRect(find.text(playing.title));
    expect(coverWide.right, lessThanOrEqualTo(titleWide.left),
        reason: '两栏：封面整块落在信息左侧');

    windowAt(tester, const Size(800, 900));
    await pumpPlayer(tester);
    final coverNarrow = tester.getRect(find.byType(Cover));
    expect((coverNarrow.center.dx - 400).abs(), lessThan(1),
        reason: '单列：封面水平居中（与历史形态一致）');
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    final playable = idleController();
    addTearDown(() {
      playable.dispose();
      playable.handler.player.dispose();
    });
    await tester.pumpWidget(MultiProvider(
      providers: providers(playable),
      child: MaterialApp(
        theme: NordicTheme.build(NordicTokens.dark),
        onGenerateRoute: AppRoutes.generate,
        home: const SettingsScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('设置页：1600 正文收成一栏 720；800 仍是满宽', (tester) async {
    addTearDown(tester.view.reset);

    windowAt(tester, const Size(1600, 900));
    await pumpSettings(tester);
    expect(tester.getSize(find.byType(ListView)).width,
        lessThanOrEqualTo(720.0));

    windowAt(tester, const Size(800, 900));
    await pumpSettings(tester);
    expect(tester.getSize(find.byType(ListView)).width, 800.0);
    expect(tester.takeException(), isNull);
  });
}
