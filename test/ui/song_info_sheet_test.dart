import 'dart:io';

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
import 'package:nordic/ui/screens/song_info_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_playback.dart';

/// 歌曲信息那张纸。
///
/// 它要回答的是「这一首到底是什么」:格式 / 码率 / 体积 / 年份 / 流派 / 入库时间 /
/// 此刻按什么在放。两条判据最重要:
///
///   1. **有的字段一个不少** —— 用户点开它就是为了看全;
///   2. **没有的字段整行不印** —— 写一行「未知」是拿假东西凑数,比没有更糟
///      (服务器确实可能不给年份 / 入库时间)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  /// 字段齐全的一首。
  const full = Song(
    id: 's1',
    title: '可能',
    artist: '程响',
    album: '可能',
    albumId: 'al-1',
    artistId: 'ar-1',
    track: 4,
    duration: Duration(seconds: 258),
    suffix: 'flac',
    bitRate: 798,
    sizeBytes: 26 * 1024 * 1024,
    year: 2022,
    genre: '流行',
    created: null,
  );

  /// 服务器什么都没多给的一首 —— 只有最基本的三件。
  const bare = Song(
    id: 's2',
    title: '没细节的那首',
    artist: '艺人',
    album: '专辑',
    albumId: 'al-2',
  );

  late Directory root;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-songinfo-ui');
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
    state.attachRepository(config, 'p');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// 揭开那张纸。**播放层按调用点给** —— 「实际播放」那一行只对正在放的那一首
  /// 才有答案,所以两种情形(是 / 不是当前这一首)都得能摆出来。
  Future<void> pumpSheet(WidgetTester tester, Song song,
      {PlaybackController? playable}) async {
    final layer = playable ?? playingController(const Song(
      id: 'other',
      title: '别的那首',
      artist: '别人',
      album: '别的专辑',
      albumId: 'al-9',
    ));
    addTearDown(() {
      layer.dispose();
      layer.handler.player.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<PlaybackController>.value(value: layer),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showSongInfoSheet(context, song),
                  child: const Text('看信息'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('看信息'));
    await tester.pumpAndSettle();
  }

  testWidgets('字段齐的那一首：每一件都印出来，格式与码率在同一行', (tester) async {
    await pumpSheet(tester, full);

    for (final label in ['曲序', '时长', '格式', '文件大小', '年份', '流派']) {
      expect(find.text(label), findsOneWidget, reason: '少了「$label」这一行');
    }
    expect(find.text('第 4 首'), findsOneWidget);
    expect(find.text('4:18'), findsOneWidget);
    expect(find.text('FLAC · 798 kbps'), findsOneWidget);
    expect(find.text('26 MB'), findsOneWidget);
    expect(find.text('2022'), findsOneWidget);
    expect(find.text('流行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没给的字段整行不印 —— 不写「未知」凑数', (tester) async {
    await pumpSheet(tester, bare);

    expect(find.text('没细节的那首'), findsOneWidget);
    for (final label in ['曲序', '格式', '文件大小', '年份', '流派', '入库时间']) {
      expect(find.text(label), findsNothing, reason: '「$label」服务器没给，不该印');
    }
    // 时长是必有的(至少是 0:00),它不该跟着一起消失。
    expect(find.text('时长'), findsOneWidget);
  });

  testWidgets('入库时间按「年 月 日」印，不是照搬 ISO 串', (tester) async {
    await pumpSheet(
      tester,
      Song(
        id: full.id,
        title: full.title,
        artist: full.artist,
        album: full.album,
        albumId: full.albumId,
        created: DateTime(2026, 10, 12, 9, 30),
      ),
    );

    expect(find.text('入库时间'), findsOneWidget);
    expect(find.text('2026 年 10 月 12 日'), findsOneWidget);
  });

  testWidgets('正在放的那一首才有「实际播放」，别的曲子不给这一行', (tester) async {
    // 不是当前这一首 —— 播放层答不出「它现在按什么在放」,那就别印。
    await pumpSheet(tester, full);
    expect(find.text('实际播放'), findsNothing);
  });

  testWidgets('「实际播放」报的是**这一趟实际用的那一份**', (tester) async {
    final playingSong = Song(
      id: full.id,
      title: full.title,
      artist: full.artist,
      album: full.album,
      albumId: full.albumId,
      suffix: full.suffix,
    );
    await pumpSheet(
      tester,
      playingSong,
      playable: playingController(
        playingSong,
        loadedQuality: QualityOption.high,
        loadedLocal: true,
      ),
    );

    expect(find.text('实际播放'), findsOneWidget);
    // 设置里选的是「均衡」(默认),而这一趟装的是本机那份、档位是高质量 ——
    // 报的必须是后者:用户拿这一行判断「现在到底听的是什么」。
    expect(find.text('高质量 · 本机'), findsOneWidget);
  });

  testWidgets('两条去路都在：查看专辑 / 查看艺人', (tester) async {
    await pumpSheet(tester, full);

    expect(find.text('查看专辑'), findsOneWidget);
    expect(find.text('查看艺人'), findsOneWidget);
  });

  testWidgets('库里没有这位艺人时，不给「查看艺人」那一行', (tester) async {
    await pumpSheet(tester, bare);

    expect(find.text('查看专辑'), findsOneWidget);
    expect(find.text('查看艺人'), findsNothing);
  });
}