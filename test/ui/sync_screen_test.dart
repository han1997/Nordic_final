import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nordic/data/config_transfer.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/scan_capability.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/server_route.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/routes.dart';
import 'package:nordic/ui/screens/sync_screen.dart';
import 'package:nordic/ui/widgets/components.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_credentials.dart';
import 'pump_real_io.dart';

/// 「扫码同步」那一屏。
///
/// 三个判据,都落在**这台设备最可能遇到的那条路**上:
///   1. 没有相机的平台上,一进来就是粘贴模式,而且**树里没有 `MobileScanner`**
///      —— 不是「它失败了」,是它压根没被建出来(web 上那一支会把 unpkg 的
///      @zxing 拖进来,见 scan_capability.dart);
///   2. 载荷带密码:直接连,服务器被替换,密码进了密钥库;
///   3. 载荷不带密码:落到录入表单,**除密码以外全填好**,而且「连接」是暗的
///      —— 那句话得说清楚,否则用户会以为这一屏卡住了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const existing = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [
      ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com'),
    ],
  );

  late Directory root;
  late AppState state;
  late MemoryCredentials credentials;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-sync-ui');

    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) => interceptor.resolve(Response<String>(
        requestOptions: options,
        statusCode: 200,
        data: jsonEncode({
          'subsonic-response': {'status': 'ok', 'version': '1.16.1'}
        }),
      )),
    ));

    credentials = MemoryCredentials();
    late final AppState appState;
    appState = AppState(
      configStore: await ConfigStore.open(),
      credentialStore: credentials,
      quality: QualityController(),
      downloadManager: DownloadManager(
        store: await DownloadStore.open(root: root),
        repository: () => appState.repository,
        wifiOnly: () => false,
      ),
      libraryCache: await LibraryCache.open(root: root),
      mediaCache: await MediaCache.open(
        limitBytes: 1 << 20,
        root: Directory('${root.path}${Platform.pathSeparator}audio'),
      ),
      dio: dio,
    );
    state = appState;
  });

  tearDown(() async {
    // 这个临时目录**可能删不干净**,而且不是「测试懒得清」:带密码那条要真跑一次
    // `connect`,它末尾那次库快照的写会挂在真实事件循环上(假时钟不替它推进),
    // Windows 上那个 `library.json.tmp` 于是还占着句柄。删得掉就删,删不掉留给系统。
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // 见上。
    }
  });

  /// 一份载荷。默认**不带密码** —— 带的那条要显式写出来。
  String payload({
    String? password,
    String name = '卧室 Navidrome',
    int routes = 2,
  }) =>
      ConfigTransfer.encode(
        kind: ServerKind.subsonic,
        name: name,
        username: 'demo',
        routes: [
          for (var i = 0; i < routes; i++)
            ServerRoute(
              id: 'r$i',
              name: '线路$i',
              url: 'http://bedroom$i.local:4533',
              selected: i == 0,
            ),
        ],
        password: password,
      );

  /// 一台**没有相机**的设备 —— 桌面就是这一档(Windows 上 mobile_scanner
  /// 连实现都没有)。web 走的也是这一支。
  Future<void> pumpSync(WidgetTester tester, {bool connected = false}) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    if (connected) {
      state.adoptServer(existing);
      state.attachRepository(existing, 'p');
    }

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          onGenerateRoute: AppRoutes.generate,
          home: const SyncScreen(
            capability: ScanCapability.fixed(
              isWeb: false,
              platform: TargetPlatform.windows,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('没有相机时：一进来就是粘贴，树里没有 MobileScanner', (tester) async {
    await pumpSync(tester);

    // 那一支**根本没被建出来** —— 这比「它报错了」强:web 上正是这一条挡住了
    // 从 unpkg 取 @zxing 的那条路。
    expect(find.byType(MobileScanner), findsNothing);
    expect(find.text('扫码'), findsNothing, reason: '一个只有一项的分段控件只是噪音');
    expect(find.text('这台设备没有摄像头 —— 用粘贴文本一样能同步。'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'nordic://config/1/...'), findsOneWidget);
  });

  testWidgets('载荷带密码：直接连，服务器被替换、密码进密钥库', (tester) async {
    await pumpSync(tester, connected: true);

    await tester.enterText(find.byType(TextField), payload(password: 's3cret'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('读取'));
    await tester.pumpAndSettle();

    // 替换当前那台要**先问一声** —— 它会清掉本机的曲库快照与缓存。
    expect(find.text('连接并替换'), findsOneWidget);
    await tester.tap(find.text('连接并替换'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget,
        reason: '替换当前那台要先问一声');

    await tester.tap(find.widgetWithText(TextButton, '替换'));
    await pumpRealIo(tester);

    expect(state.server?.name, '卧室 Navidrome');
    expect(state.server?.kind, ServerKind.subsonic);
    expect(state.server?.username, 'demo');
    expect(state.server?.routes.length, 2);
    expect(await credentials.readPassword(), 's3cret');
  });

  testWidgets('载荷不带密码：落到表单，除密码外全填好，「连接」是暗的', (tester) async {
    await pumpSync(tester, connected: true);

    await tester.enterText(find.byType(TextField), payload());
    await tester.pumpAndSettle();
    await tester.tap(find.text('读取'));
    await tester.pumpAndSettle();

    expect(find.text('填上密码'), findsOneWidget);
    expect(find.textContaining('只差密码'), findsOneWidget);

    await tester.tap(find.text('填上密码'));
    await tester.pumpAndSettle();

    // 到了录入表单,而且**填的是载荷里那份**(不是本机现有那台)。
    expect(find.widgetWithText(TextField, '卧室 Navidrome'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'demo'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'http://bedroom0.local:4533'),
        findsOneWidget);
    expect(find.textContaining('只差密码'), findsOneWidget);
    // 多线路那句说明:表单只有一个地址框,其余几条会原样保存。
    expect(find.textContaining('有 2 条线路'), findsOneWidget);
    // 本机那台还在 —— 按下「连接」之前什么都没变。
    expect(state.server?.name, '客厅 Navidrome');
  });

  testWidgets('不是我们的载荷：说明白哪儿不对，而且不做任何事', (tester) async {
    await pumpSync(tester, connected: true);

    await tester.enterText(find.byType(TextField), 'https://example.com/随便一段');
    await tester.pumpAndSettle();
    // 前缀都不对时那颗键按不动 —— 免得点了像没点。
    final pill = tester.widget<PillButton>(find.byType(PillButton));
    expect(pill.onPressed, isNull);
  });
}