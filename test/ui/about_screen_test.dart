import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/server_route.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/about_screen.dart';
import 'package:nordic/ui/screens/servers_screen.dart';
import 'package:nordic/ui/routes.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「关于」那一页。
///
/// 它唯一要回答的问题是「**这一页上的版本,是不是我装的那个**」—— 所以版本号
/// 必须从包里读出来(PackageInfo),而这条用例把包里的版本钉成 1.0.42+43,
/// 验的就是「显示的是它,而不是某个写死的串」。
///
/// 另外两条是这一页存在的理由:隐私那两条陈述在(它们原先和开关混在设置里),
/// 以及**开源许可真的点得开**(那是 Flutter 自带那一页,不是我们自己画的一张图)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [
      ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com'),
      ServerRoute(id: 'ddns', name: '外网', url: 'https://music.example.com'),
    ],
  );

  late Directory root;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Nordic',
      packageName: 'fun.han1997.nordic',
      version: '1.0.42',
      buildNumber: '43',
      buildSignature: '',
    );
    root = await Directory.systemTemp.createTemp('nordic-about-ui');
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

  Future<void> pumpAbout(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<QualityController>.value(value: state.quality),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          // 「服务器」那一条是**推入的路由** —— 路由表得在场(与产品里同一份)。
          onGenerateRoute: (settings) =>
              settings.name == Navigator.defaultRouteName
                  ? MaterialPageRoute<void>(builder: (_) => const AboutScreen())
                  : AppRoutes.generate(settings),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('版本号从**包里**读出来，与产物名里那一份逐字相同', (tester) async {
    await pumpAbout(tester);

    expect(find.text('Nordic'), findsOneWidget);
    expect(find.text('多平台 NAS 音乐播放器'), findsOneWidget);
    // 两处都报同一个值(顶部与卡片里那一行):一处带 build 号、一处不带是要出事的。
    expect(find.text('1.0.42+43'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('隐私那两条在里面 —— 它们是陈述，不是开关', (tester) async {
    await pumpAbout(tester);

    // 这一条在页面下头 —— 列表是懒建的,不滚过去它根本没建出来。
    await tester.dragUntilVisible(
      find.text('凭据仅存本机'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(find.text('凭据仅存本机'), findsOneWidget);
    expect(find.text('播放记录'), findsOneWidget);
    // 这一页上不该出现任何开关:能关掉的话就成了骗人的东西。
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('服务器那一行报的是当前配置，点得进服务器与线路', (tester) async {
    await pumpAbout(tester);

    expect(find.text('客厅 Navidrome'), findsOneWidget);
    expect(find.text('Navidrome · 2 条线路'), findsOneWidget);

    await tester.tap(find.text('客厅 Navidrome'));
    await tester.pumpAndSettle();
    expect(find.byType(ServersScreen), findsOneWidget);
  });

  testWidgets('「开源许可」点开的是 Flutter 那一页，不是自己画的', (tester) async {
    await pumpAbout(tester);

    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Nordic'), findsWidgets);
    // 许可页会去读各个包的 LICENSE —— 那是真读,不是占位。
    expect(find.textContaining('Flutter'), findsWidgets);
  });
}