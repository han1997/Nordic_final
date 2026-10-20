import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/models.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/routes.dart';
import 'package:nordic/ui/screens/about_screen.dart';
import 'package:nordic/ui/screens/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置页里新加的「缓存」那一栏。
///
/// 它要回答用户两个问题:**上限是多少、现在用了多少**,以及**怎么清掉**。
/// 三者的数字必须对得上 —— 显示的占用得是真的占用,清完得真的变 0,
/// 上限改小得真的把旧的扔掉。
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
    id: 'song-1',
    title: '可能',
    artist: '程响',
    album: '可能',
    albumId: 'al-1',
    suffix: 'flac',
  );

  late Directory root;
  late MediaCache audioCache;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-settings-ui');
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
    );
    state = appState;
    state.adoptServer(config);
    state.attachRepository(config, 'p');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// 往缓存里塞一份「已经听过」的曲子。**必须在 setUp / runAsync 里做** ——
  /// `testWidgets` 的时钟下真 I/O 永远等不回来。
  Future<void> seedCacheFile({int bytes = 2 * 1024 * 1024}) async {
    final file = audioCache.fileFor(song, qualityId: 'medium', format: 'mp3')!;
    await file.writeAsBytes(List<int>.filled(bytes, 7));
    await audioCache.prune();
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<QualityController>.value(value: state.quality),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          // 「关于」那一条是**推入的路由** —— 路由表得在场,与产品里同一份。
          onGenerateRoute: (settings) =>
              settings.name == Navigator.defaultRouteName
                  ? MaterialPageRoute<void>(builder: (_) => const SettingsScreen())
                  : AppRoutes.generate(settings),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('缓存那一栏说清了上限与占用', (tester) async {
    await tester.runAsync(seedCacheFile);
    await pumpSettings(tester);

    await tester.dragUntilVisible(
      find.text('歌曲缓存'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(find.text('歌曲缓存'), findsOneWidget);
    expect(find.text('听过的歌留在本机，再听不用重新拉'), findsOneWidget);
    // 上限的档位名在行尾。
    expect(find.text('1 GB'), findsOneWidget);
    expect(find.text('占用 2 MB · 上限 1 GB'), findsOneWidget);
    expect(find.text('清除'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('还没缓存过东西时，行里说的是「还没有东西」，也不给清除按钮', (tester) async {
    await pumpSettings(tester);

    await tester.dragUntilVisible(
      find.text('已用空间'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(find.text('缓存里还没有东西'), findsOneWidget);
    // 一个空缓存配一颗「清除」按钮,点了什么也不会发生 —— 不如不给。
    expect(find.text('清除'), findsNothing);
  });

  testWidgets('点开「歌曲缓存」是那张上限面板，当前档位打着勾', (tester) async {
    await pumpSettings(tester);

    await tester.dragUntilVisible(
      find.text('歌曲缓存'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    // 与下面那条同一件事:半截在屏幕上时点击会落空(点了没反应,不报错)——
    // 「存储」合并成一栏之后这一行离屏幕下沿更近了,不先摆正就点不着。
    await tester.ensureVisible(find.text('歌曲缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌曲缓存'));
    await tester.pumpAndSettle();

    // 六个档位,「不缓存」在第一格。
    expect(find.text('不缓存'), findsOneWidget);
    expect(find.text('512 MB'), findsOneWidget);
    expect(find.text('4 GB'), findsOneWidget);
    expect(find.text('约 100 首 · 默认'), findsOneWidget);
    // 讲解里那句要紧的前提:**下载不在缓存里,不会被扔掉**。
    expect(
      find.textContaining('永远不会被扔掉'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('清除先问一句，问的是「会少掉什么」而不是「确定吗」', (tester) async {
    await tester.runAsync(seedCacheFile);
    await pumpSettings(tester);

    await tester.dragUntilVisible(
      find.text('已用空间'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    // 让它整颗都落进视口 —— 半截在屏幕上时点击会落空(点了没反应,不报错)。
    await tester.ensureVisible(find.text('清除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    expect(find.text('清除歌曲缓存？'), findsOneWidget);
    expect(find.textContaining('断网时还能听的那些就听不到了'), findsOneWidget);
    expect(find.textContaining('点名下好的内容不受影响'), findsOneWidget);

    // 取消:缓存一份都不动。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.cacheUsedBytes, 2 * 1024 * 1024);
  });

  test('换上限：落盘 + 当场淘汰到新额度之下', () async {
    await seedCacheFile(bytes: 3 * 1024 * 1024);
    expect(state.cacheUsedBytes, 3 * 1024 * 1024);

    await state.setCacheLimit(CacheLimit.mb256);

    expect(state.cacheLimit, CacheLimit.mb256, reason: '下次启动还得是这个档');
    expect(
      state.cacheUsedBytes,
      lessThanOrEqualTo(CacheLimit.mb256.bytes),
      reason: '改完数字就该看见占用跟着降',
    );

    // 换个 AppState(等于重启一次)也还是这个档 —— 存的是档位名。
    expect(state.configStore.loadCacheLimit(), CacheLimit.mb256.id);
  });

  test('关掉缓存：本机留着的音频全清掉', () async {
    await seedCacheFile();
    expect(state.cacheUsedBytes, greaterThan(0));

    await state.setCacheLimit(CacheLimit.off);

    expect(state.cacheUsedBytes, 0);
    expect(audioCache.enabled, isFalse);
  });

  test('清除缓存报出释放了多少，而且不动下载', () async {
    await seedCacheFile(bytes: 5 * 1024 * 1024);

    // 下载目录里放一份「点名要的」东西 —— 清缓存绝不能碰它。
    final downloadsDir = Directory('${root.path}${Platform.pathSeparator}dl-album-1');
    await downloadsDir.create(recursive: true);
    final kept = File('${downloadsDir.path}${Platform.pathSeparator}01 - 曲目.flac');
    await kept.writeAsBytes(List<int>.filled(1024, 3));

    final freed = await state.clearCache();

    expect(freed, 5 * 1024 * 1024);
    expect(state.cacheUsedBytes, 0);
    expect(kept.existsSync(), isTrue, reason: '下载是点名要的，清缓存不该动它');
  });

  testWidgets('服务器那一栏：扫码同步与导出配置两条都在', (tester) async {
    await pumpSettings(tester);

    await tester.dragUntilVisible(
      find.text('扫码同步'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(find.text('扫码同步'), findsOneWidget);
    expect(find.text('扫码或粘贴，把服务器与线路带到这台设备'), findsOneWidget);
    expect(find.text('导出配置'), findsOneWidget);
    expect(find.text('二维码 · 可复制成一段文本'), findsOneWidget);
  });

  testWidgets('没连服务器时不给「导出配置」那一行', (tester) async {
    // 那一行只在**真有配置可导出**时出现:`_SettingRow` 没有禁用态,一颗
    // `onTap: null` 的行既不置灰也不回弹,读起来就是个坏按钮。
    //
    // 造一个没接管服务器的实例 —— 而不是调 `disconnect()`:那条路要碰系统
    // 密钥库(测试里没有那个插件)。开这几个 store 是真碰文件系统,所以走
    // `runAsync`(`testWidgets` 的假时钟不替真 I/O 推进)。
    await tester.runAsync(() async {
      late final AppState fresh;
      fresh = AppState(
        configStore: await ConfigStore.open(),
        credentialStore: CredentialStore(),
        quality: QualityController(),
        downloadManager: DownloadManager(
          store: await DownloadStore.open(root: root),
          repository: () => null,
          wifiOnly: () => false,
        ),
        libraryCache: await LibraryCache.open(root: root),
        mediaCache: audioCache,
      );
      state = fresh;
    });

    await pumpSettings(tester);

    await tester.dragUntilVisible(
      find.text('扫码同步'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pump();

    // 扫码那一行一直在 —— 没连服务器时它正是要用的那一条。
    expect(find.text('扫码同步'), findsOneWidget);
    expect(find.text('导出配置'), findsNothing);
  });

testWidgets('「存储」把缓存与下载收在一栏里', (tester) async {
    await pumpSettings(tester);

    await tester.dragUntilVisible(
      find.text('仅 Wi-Fi 下载'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pump();

    // 四条在一栏:手动的(下载)与顺手的(缓存)摆在一起 ——「清缓存会不会连下载
    // 一起清掉」这件事于是不用靠一行小字解释。
    expect(find.text('存储'), findsOneWidget);
    expect(find.text('歌曲缓存'), findsOneWidget);
    expect(find.text('已用空间'), findsOneWidget);
    expect(find.text('下载管理'), findsOneWidget);
    expect(find.text('仅 Wi-Fi 下载'), findsOneWidget);

    // 原先那两栏的名字不该再各占一个标题,「隐私」那一栏整个没了
    // (那两条陈述搬去了「关于」)。
    expect(find.text('缓存'), findsNothing);
    expect(find.text('下载'), findsNothing);
    expect(find.text('隐私'), findsNothing);
  });

  testWidgets('「关于」那一栏在，点进去是那一页', (tester) async {
    await pumpSettings(tester);

    await tester.dragUntilVisible(
      find.text('关于 Nordic'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(find.text('关于'), findsOneWidget);
    expect(find.text('关于 Nordic'), findsOneWidget);

    await tester.tap(find.text('关于 Nordic'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
  });

testWidgets('服务器那一栏里有「曲库扫描」—— 三处空态那句承诺落在这儿', (tester) async {
    await pumpSettings(tester);

    await tester.dragUntilVisible(
      find.text('曲库扫描'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(find.text('曲库扫描'), findsOneWidget);
    // 还没点过那一行时它**如实说不知道** —— 进设置页不该悄悄打一次服务器,
    // 而编一个「未在扫描」出来是假的(见 settings_screen 里那一行)。
    expect(find.text('看看服务器上有没有新加的歌'), findsOneWidget);
  });

}
