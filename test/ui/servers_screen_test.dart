import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/config_transfer.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/library_cache.dart';
import 'package:nordic/data/media_cache.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/servers_screen.dart';
import 'package:nordic/ui/widgets/components.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_credentials.dart';
import 'pump_real_io.dart';

/// 这一屏管的是「我的服务器」:线路、**账号 / 密码 / 地址**、移除。
///
/// 2026-10-17 用户报「服务器相关功能没有入口了,只有线路选择」——
/// 根因是录入表单只在「还没配过服务器」时出现,连上之后再想改账号 / 密码 / 地址
/// 就没有路了(这一屏只剩线路)。这组测试钉住「改配置的入口一直在」。
/// 音频缓存。**单独一个目录** —— 与下载、与库快照都不共用:
/// 它按自己的上限淘汰,混在一起会把别人的文件数进「已用空间」。
Future<MediaCache> openAudioCache(Directory root) => MediaCache.open(
      limitBytes: CacheLimit.gb1.bytes,
      root: Directory('${root.path}${Platform.pathSeparator}audio'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  late Directory root;
  late MediaCache audioCache;
  late AppState state;
  late MemoryCredentials credentials;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-servers-ui');
    audioCache = await openAudioCache(root);
    credentials = MemoryCredentials();

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
      mediaCache: audioCache,
      dio: dio,
    );
    state = appState;
    state.adoptServer(config);
    state.attachRepository(config, 'p');
  });

  tearDown(() async {
    // 扫码那条用例要真跑一次 `connect`,而它末尾那次库快照的写会挂在真实事件
    // 循环上(假时钟不替它推进,见 `pump_real_io.dart`),Windows 上那个
    // `library.json.tmp` 于是还占着句柄 —— 目录删不掉。删得掉就删,删不掉留给系统。
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // 见上。
    }
  });

  Future<void> pumpServers(
    WidgetTester tester, {
    bool startInForm = false,
    TransferredServer? prefill,
  }) async {
    // 这一屏比一屏高(表单有四组字段、管理页有一张概览卡 + 线路表),
    // 默认 800×600 的测试视口装不下 —— 装不下的部分**不会被建出来**,
    // `find` 就找不到,那会把「控件在不在」测成假阴性。给一块够高的画布。
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: ServersScreen(startInForm: startInForm, prefill: prefill),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('已配置时，管理页上有「服务器设置」这条入口', (tester) async {
    await pumpServers(tester);

    // 管理页的正文:线路那一栏在。
    expect(find.text('线路'), findsOneWidget);
    // 而没有这条的话,账号 / 密码 / 地址就再也改不了了。
    expect(find.text('服务器设置'), findsOneWidget);
    expect(find.text('添加线路地址'), findsOneWidget);
    expect(find.text('移除该服务器'), findsOneWidget);
  });

  testWidgets('点「服务器设置」进表单，字段是现有配置，按钮说的是「保存」', (tester) async {
    await pumpServers(tester);
    await tester.tap(find.text('服务器设置'));
    await tester.pumpAndSettle();

    // 表单那一套控件都在,而且**填的是现有值**(改一处,不是重填一遍)。
    expect(find.text('接入类型'), findsOneWidget);
    expect(find.text('账户'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, '客厅 Navidrome'),
      findsOneWidget,
      reason: '显示名称该预填现有配置',
    );
    expect(
      find.widgetWithText(TextField, 'http://nas.example.com'),
      findsOneWidget,
    );
    expect(find.text('保存并重新连接'), findsOneWidget);
    expect(find.text('连接'), findsNothing);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('取消回到管理页，不留下任何改动', (tester) async {
    await pumpServers(tester);
    await tester.tap(find.text('服务器设置'));
    await tester.pumpAndSettle();

    // 改一处再取消 —— 扔掉的那半份不该留在输入框里:再进表单看到它、
    // 又一次误点「保存并重新连接」,那半份就真存下去了。
    await tester.enterText(
      find.widgetWithText(TextField, '客厅 Navidrome'),
      '改了一半的名字',
    );
    await tester.pump();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('添加线路地址'), findsOneWidget);
    expect(state.server!.name, '客厅 Navidrome');

    // 再进来一次:填的还是现有配置,不是刚才那半份。
    await tester.tap(find.text('服务器设置'));
    await tester.pumpAndSettle();

    expect(find.text('改了一半的名字'), findsNothing, reason: '取消要把输入框也还原');
    expect(find.widgetWithText(TextField, '客厅 Navidrome'), findsOneWidget);
  });

  testWidgets('startInForm（设置页的「添加服务器」）一进来就在表单上', (tester) async {
    await pumpServers(tester, startInForm: true);

    expect(find.text('账户'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('添加线路地址'), findsNothing);
  });

  testWidgets('「添加服务器」给的是一张**空**表单，不是现有那台的配置', (tester) async {
    // 用户点的是「用另一个账号或另一台机器」,预填上现有那台会让他以为在改
    // 现有那台 —— 而按下去确实会把它换掉。原型那条路(`screenAddServer`)
    // 也是空表单 + 先选接入类型。
    await pumpServers(tester, startInForm: true);

    expect(find.text('添加服务器'), findsOneWidget);
    expect(find.text('服务器设置'), findsNothing);
    expect(
      find.widgetWithText(TextField, '客厅 Navidrome'),
      findsNothing,
      reason: '不该预填现有服务器的名字',
    );
    expect(find.widgetWithText(TextField, 'http://nas.example.com'), findsNothing);
    expect(find.text('连接'), findsOneWidget);
    expect(find.text('保存并重新连接'), findsNothing);
  });

  testWidgets('还没配置过时表单就是正文，没有多余的「取消」', (tester) async {
    final fresh = AppState(
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

    await pumpServers(tester);

    expect(find.text('接入类型'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
    expect(find.text('取消'), findsNothing, reason: '没配置过时没有「管理页」可退回');
  });

  /// 「扫码同步」读出来的那份配置。三条线路 —— 这一组测试的重点正是
  /// **最容易出的那个坑**:表单只有一个地址框,3 条线路进来很容易被静默丢掉 2 条。
  TransferredServer imported() => const TransferredServer(
        kind: ServerKind.subsonic,
        name: '卧室 Navidrome',
        username: 'demo',
        routes: [
          ServerRoute(id: 'r0', name: '局域网', url: 'http://bedroom.local:4533'),
          ServerRoute(
            id: 'r1',
            name: '外网',
            url: 'https://bedroom.example.com',
            tag: RouteTag.wan,
          ),
          ServerRoute(id: 'r2', name: '备用', url: 'http://10.0.0.9:4533'),
        ],
      );

  testWidgets('扫码带进来一份配置：除密码以外都填好，而且当场说明白了', (tester) async {
    await pumpServers(tester, prefill: imported());

    // 名字 / 账号 / 地址都填的是**载荷里那份**,不是本机现有那台。
    expect(find.widgetWithText(TextField, '卧室 Navidrome'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'demo'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'http://bedroom.local:4533'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, '客厅 Navidrome'), findsNothing);

    // 密码那一格是空的 —— 而「连接」要求密码非空,所以此刻它是暗的。
    // 不说清楚的话用户会以为这一屏卡住了(所以那句话本身就是判据)。
    expect(find.textContaining('只差密码'), findsOneWidget);
    expect(find.textContaining('有 3 条线路'), findsOneWidget);
    expect(find.text('服务器设置'), findsNothing);
    expect(
      tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
      isNull,
    );
  });

  testWidgets('扫码带进来那几条线路：提交之后三条都还在，第一条被表单里那条地址替换', (tester) async {
    await pumpServers(tester, prefill: imported());

    // 表单里那条地址对应**第一条**线路 —— 改它就等于改第一条。
    await tester.enterText(
      find.widgetWithText(TextField, 'http://bedroom.local:4533'),
      'http://bedroom-edited.local:4533',
    );
    await tester.enterText(find.widgetWithText(TextField, '服务器密码'), 's3cret');
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接'));
    await pumpRealIo(tester);

    final server = state.server;
    expect(server?.name, '卧室 Navidrome');
    expect(server?.kind, ServerKind.subsonic);
    expect(server?.username, 'demo');
    expect(
      server?.routes.map((r) => r.url).toList(),
      [
        'http://bedroom-edited.local:4533',
        'https://bedroom.example.com',
        'http://10.0.0.9:4533',
      ],
      reason: '表单那条地址改的是第一条，载荷里其余几条**一条都不该少**',
    );
    expect(server?.routes[1].tag, RouteTag.wan, reason: '其余几条连标记一起原样留着');
  });
}
