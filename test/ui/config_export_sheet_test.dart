import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/config_transfer.dart';
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
import 'package:nordic/ui/screens/config_export_sheet.dart';
import 'package:nordic/ui/widgets/components.dart';
import 'package:nordic/ui/widgets/qr_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_credentials.dart';

/// 「导出配置」那张纸。
///
/// 三条判据,一条比一条要紧:
///   1. **「包含密码」默认关** —— 开口的那串必须等于 `ConfigTransfer.encode`
///      的「不带密码」那一版,不是「大概不带」;
///   2. 打开之后,二维码与下面那串文本**一起**换成带密码的那一版 —— 两处若
///      各说一套,扫出来与复制走的就是两份不同的配置;
///   3. 点「复制文本」送到剪贴板的,就是**屏幕上那一串**(逐字符相等)。
///
/// 还有一条不算判据但要说清:本机没存过密码时,那颗开关**整个不出现** ——
/// 没东西可选的时候摆一个开关只是骗人。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'demo',
    routes: [
      ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com'),
      ServerRoute(
        id: 'wan',
        name: '外网',
        url: 'https://nas.example.com:4533',
        tag: RouteTag.wan,
      ),
    ],
  );

  late Directory root;
  late MemoryCredentials credentials;
  late AppState state;
  late List<String> copied;

  /// 屏幕上该显示的那一串。**由一个地方算出来**,不然「显示的对不对」
  /// 会退化成把编出来的串再抄一遍。
  String expected({String? password}) => ConfigTransfer.encode(
        kind: config.kind,
        name: config.name,
        username: config.username,
        routes: config.routes,
        password: password,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nordic-export-ui');
    credentials = MemoryCredentials('pw-123');

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
    );
    state = appState;
    state.adoptServer(config);
    state.attachRepository(config, 'pw-123');

    copied = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // 删不掉只是临时目录留到系统清理为止,与这一轮的判据无关。
    }
  });

  /// 打开那张弹层。从设置页那一行进来是**同一条路**(`showConfigExportSheet`),
  /// 这里只省掉「先滚到设置页再点」。
  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

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
                  onPressed: () => showConfigExportSheet(context),
                  child: const Text('打开导出'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导出'));
    await tester.pumpAndSettle();
  }

  /// 屏幕上那串文本(可选中的那一块)。
  String shownPayload(WidgetTester tester) =>
      tester.widget<SelectableText>(find.byType(SelectableText)).data!;

  /// 复制按下去之后**先别急着把提示推走**:那句「已复制到剪贴板」本身也是判据。
  /// 这条路走完,再把它的那两个定时器推完 —— 不推的话测试收尾会撞上
  /// 「还有定时器没跑完」。
  Future<void> pumpCopyDone(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  testWidgets('打开就是二维码 + 同一串文本，「包含密码」默认关', (tester) async {
    await pumpSheet(tester);

    final payload = expected();
    // 二维码里那串与下面那串**是同一个字符串** —— 这正是「有相机的扫码、
    // 没相机的复制粘贴」两条路能互相顶上的原因。
    expect(tester.widget<QrView>(find.byType(QrView)).data, payload);
    expect(shownPayload(tester), payload);

    expect(tester.widget<NordicSwitch>(find.byType(NordicSwitch)).value, isFalse,
        reason: '默认不带密码 —— 与「落盘不带密码」同一口径');
    expect(find.textContaining('只带地址与账号'), findsOneWidget);
    expect(find.textContaining('就等于密码本身'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('打开「包含密码」：二维码与文本一起换成带密码的那一版', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byType(NordicSwitch));
    await tester.pumpAndSettle();

    final payload = expected(password: 'pw-123');
    expect(tester.widget<QrView>(find.byType(QrView)).data, payload);
    expect(shownPayload(tester), payload);
    // 打开之后那句话必须变 —— 这张码等于密码本身,得当场说。
    expect(find.textContaining('就等于密码本身'), findsOneWidget);
    expect(find.textContaining('可以直接连上'), findsOneWidget);
  });

  testWidgets('点「复制文本」：剪贴板收到的就是屏幕上那一串', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('复制文本'));
    await tester.pumpAndSettle();

    expect(copied, [expected()]);
    expect(find.text('已复制到剪贴板'), findsOneWidget);
    await pumpCopyDone(tester);
  });

  testWidgets('带密码时复制出去的就是带密码的那一串', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byType(NordicSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制文本'));
    await tester.pumpAndSettle();

    expect(copied, [expected(password: 'pw-123')]);
    await pumpCopyDone(tester);
  });

  testWidgets('本机没存过密码时，那颗开关整个不出现', (tester) async {
    // 换一个「密钥库里是空的」的 AppState,连的那台服务器照旧。
    // **必须走 runAsync**:开这几个 store 是真碰文件系统,而 `testWidgets`
    // 的假时钟不替真 I/O 推进(同 `settings_screen_test` 里那条注释)。
    await tester.runAsync(() async {
      credentials = MemoryCredentials();
      state = AppState(
        configStore: await ConfigStore.open(),
        credentialStore: credentials,
        quality: QualityController(),
        downloadManager: DownloadManager(
          store: await DownloadStore.open(root: root),
          repository: () => state.repository,
          wifiOnly: () => false,
        ),
        libraryCache: await LibraryCache.open(root: root),
        mediaCache: await MediaCache.open(
          limitBytes: 1 << 20,
          root: Directory('${root.path}${Platform.pathSeparator}audio'),
        ),
      );
      state.adoptServer(config);
      state.attachRepository(config, '');
    });

    await pumpSheet(tester);

    // 没东西可选的时候给一颗开关,点了也生不出密码来。
    expect(find.byType(NordicSwitch), findsNothing);
    expect(find.text('包含密码'), findsNothing);
    expect(shownPayload(tester), expected());
  });
}