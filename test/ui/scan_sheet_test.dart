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
import 'package:nordic/data/server_route.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/scan_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「曲库扫描」那张纸。
///
/// 它要回答的是「服务器上那次扫描到哪一步了」,以及**发起一次扫描**。
/// 三条判据:
///
///   1. 状态与上次扫描时间照服务器说的印;
///   2. 「开始扫描」真的打到 `startScan` 上,扫完(轮询到 scanning=false)
///      把音乐库重取一遍 —— 「扫完就能看见新歌」是这件事的全部意义;
///   3. **非管理员时把服务器那句话转述出来**,不假装扫上了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  /// 记下每个端点被问了几次。
  late List<String> endpoints;

  /// 扫描状态:测试按需改它(fake 服务器每次读的都是当下这一份)。
  late Map<String, dynamic> scanStatus;

  /// startScan 的应答 —— null 就是「这个账号不让扫」。
  Map<String, dynamic>? startScanResponse;

  Dio fakeDio() {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        final endpoint = options.uri.pathSegments.last.replaceAll('.view', '');
        endpoints.add(endpoint);
        final body = switch (endpoint) {
          'getScanStatus' => _ok({'scanStatus': scanStatus}),
          // 没有应答 = 这个账号不让扫(真实世界里 Navidrome 对非管理员
          // 回的就是这一句失败)。
          'startScan' => startScanResponse ??
              {
                'subsonic-response': {
                  'status': 'failed',
                  'version': '1.16.1',
                  'error': {'code': 50, 'message': 'not authorized'},
                }
              },
          _ => _ok(const {}),
        };
        interceptor.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode(body),
        ));
      },
    ));
    return dio;
  }

  late Directory root;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    endpoints = [];
    scanStatus = {
      'scanning': false,
      'count': 522,
      'lastScan': '2026-10-19T11:19:15Z',
    };
    startScanResponse = null;

    root = await Directory.systemTemp.createTemp('nordic-scan-ui');
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
    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } on FileSystemException {
      // Windows 上临时目录偶尔被抢住(句柄还没松)—— 与别的用例同一条口径,
      // 系统自己会清。
    }
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<QualityController>.value(value: state.quality),
        ],
        child: MaterialApp(
          theme: NordicTheme.build(NordicTokens.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showScanSheet(context),
                  child: const Text('开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开'));
    // 两张都得等:那张纸**升起来**要 250ms(升到一半时按钮还在屏幕外,
    // 点不着),而它一开就去问一次状态(Dio 的拦截器链落在零延迟的 Timer 上,
    // 裸 pump() 推不动)。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  testWidgets('状态与上次扫描时间照服务器说的印', (tester) async {
    await pumpSheet(tester);

    expect(endpoints, contains('getScanStatus'));
    expect(find.text('曲库扫描'), findsWidgets);
    expect(find.text('未在扫描'), findsOneWidget);
    expect(find.text('522 首'), findsOneWidget);
    // 上了本地时区的那一天那一刻(测试机在 +08,所以是 19 日 19:19)。
    expect(find.textContaining('月'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开始扫描：打到 startScan 上，扫完把库重取一遍', (tester) async {
    await pumpSheet(tester);
    endpoints.clear();

    // 一开始就扫着(服务器把它设成 true 的那一瞬间)。
    scanStatus = {
      'scanning': true,
      'count': 12,
      'lastScan': '2026-10-19T11:19:15Z',
    };
    // 点下去之后的状态由服务器给 —— 这里让它下一次轮询就报「扫完了」。
    startScanResponse = _ok({'scanStatus': scanStatus});

    await tester.tap(find.text('开始扫描'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(endpoints, contains('startScan'));
    // 扫着的时候按钮换成「正在扫描…」,不让再点。
    expect(find.text('正在扫描…'), findsOneWidget);

    // 服务器那边扫完了(下一次轮询读到的新状态)。
    scanStatus = {
      'scanning': false,
      'count': 523,
      'lastScan': '2026-10-19T11:31:02Z',
    };
    endpoints.clear();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('未在扫描'), findsOneWidget);
    expect(find.text('523 首'), findsOneWidget);
    // **扫完要重取一次库** —— 不然「扫完就能看见新歌」是句空话。
    expect(endpoints, contains('search3'));
    expect(endpoints, contains('getAlbumList2'));
  });

  testWidgets('非管理员：把服务器那句话摆出来，不假装扫上了', (tester) async {
    await pumpSheet(tester);

    // 没有 startScan 应答 → 假服务器回一句失败(真实世界里 Navidrome 对
    // 非管理员就是这一句)。
    await tester.tap(find.text('开始扫描'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.textContaining('not authorized'), findsOneWidget);
    // 按钮仍然是「开始扫描」—— 没扫上就不该显示成扫着。
    expect(find.text('开始扫描'), findsOneWidget);
  });
}

Map<String, dynamic> _ok(Map<String, dynamic> body) => {
      'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...body}
    };