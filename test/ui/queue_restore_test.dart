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
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:nordic/theme/nordic_theme.dart';
import 'package:nordic/theme/tokens.dart';
import 'package:nordic/ui/screens/queue_restore_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「接着上次听?」—— 什么时候问、问了之后怎么办。
///
/// 这一问的判据是**指纹**:服务器上那份队列要是我们自己刚写回去的,就不该问
/// (每次启动都问一遍是很烦的);另一台设备改过才问。问了之后,**继续**与**忽略**
/// 都要记下这个指纹 —— 前者是「这一份已经装载过了」,后者是「他刚说了不要」。
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

  /// 服务器上那一份队列(测试按需改)。
  late Map<String, dynamic> queue;

  Dio fakeDio() {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        final endpoint = options.uri.pathSegments.last.replaceAll('.view', '');
        final body = endpoint == 'getPlayQueue' ? ok({'playQueue': queue}) : ok(const {});
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
    // 两台设备各留下一份队列的样子:一份「别的设备写的」,一份「我们自己写的」。
    queue = {
      'entry': [
        {
          'id': 's1',
          'title': '一',
          'artist': '甲',
          'album': 'A',
          'albumId': 'al-1',
          'duration': 200,
        },
        {
          'id': 's2',
          'title': '二',
          'artist': '乙',
          'album': 'A',
          'albumId': 'al-1',
          'duration': 180,
        },
      ],
      'current': 's2',
      'position': 92000,
      'changed': '2026-10-19T21:30:00Z',
    };

    root = await Directory.systemTemp.createTemp('nordic-resume-ui');
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
      // Windows 上临时目录偶尔被抢住 —— 与别的用例同一条口径。
    }
  });

  group('该不该问', () {
    test('服务器上有队列、本机没记过 → 该问', () async {
      await state.checkPlayQueue();

      final pending = state.pendingQueueRestore;
      expect(pending, isNotNull);
      expect(pending!.songs.map((s) => s.id), ['s1', 's2']);
      expect(pending.currentId, 's2');
      expect(pending.position, const Duration(seconds: 92));
    });

    test('空队列 → 不问', () async {
      queue = {'username': 'u', 'changed': '0001-01-01T00:00:00Z'};
      await state.checkPlayQueue();

      expect(state.pendingQueueRestore, isNull);
    });

    test('我们自己刚写的那一份（指纹一样）→ 不问', () async {
      // 第一次:问,并记下指纹(用户按了继续 / 忽略都会记)。
      await state.checkPlayQueue();
      await state.forgetPendingQueue();

      // 第二次(比如下一次启动):同一份队列,不该再问一遍。
      await state.checkPlayQueue();
      expect(state.pendingQueueRestore, isNull);
    });

    test('另一台设备改过（指纹变了）→ 再问', () async {
      await state.checkPlayQueue();
      await state.forgetPendingQueue();

      // 另一台设备把队列改了(多了尾巴上一首、当前那首也换了)。
      queue = {
        'entry': [
          ...(queue['entry'] as List),
          {
            'id': 's3',
            'title': '三',
            'artist': '丙',
            'album': 'A',
            'albumId': 'al-1',
            'duration': 220,
          },
        ],
        'current': 's3',
        'position': 5000,
        'changed': '2026-10-20T09:00:00Z',
      };
      await state.checkPlayQueue();

      expect(state.pendingQueueRestore, isNotNull);
      expect(state.pendingQueueRestore!.currentId, 's3');
    });
  });

  group('那张纸', () {
    const songs = [
      Song(id: 's1', title: '一', artist: '甲', album: 'A', albumId: 'al-1'),
      Song(id: 's2', title: '二', artist: '乙', album: 'A', albumId: 'al-1'),
    ];
    const pending = (
      songs: songs,
      currentId: 's2',
      position: Duration(seconds: 92),
      mark: '2:s1:s2:s2',
    );

    /// 揭开那张纸,并把「用户点的是哪一颗」记下来。
    Future<ValueNotifier<bool?>> openSheet(WidgetTester tester) async {
      final answer = ValueNotifier<bool?>(null);
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider<AppState>.value(value: state)],
          child: MaterialApp(
            theme: NordicTheme.build(NordicTokens.dark),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      answer.value = await showQueueRestoreSheet(context, pending);
                    },
                    child: const Text('开'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开'));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('说的是哪一首、听到哪儿了；「继续」回 true', (tester) async {
      final answer = await openSheet(tester);

      expect(find.text('接着上次听？'), findsOneWidget);
      expect(find.text('2 首 · 第 2 首'), findsOneWidget);
      // 那一句里要能看见**停在哪儿**:歌名 + 时间。
      expect(find.textContaining('二'), findsWidgets);
      expect(find.textContaining('1:32'), findsOneWidget);
      expect(find.text('继续'), findsOneWidget);
      expect(find.text('忽略'), findsOneWidget);

      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(answer.value, isTrue);
      // 点完就收掉 —— 它是「问一句」,不是常驻的一层。
      expect(find.text('接着上次听？'), findsNothing);
    });

    testWidgets('「忽略」回 false，纸也收掉', (tester) async {
      final answer = await openSheet(tester);

      await tester.tap(find.text('忽略'));
      await tester.pumpAndSettle();

      expect(answer.value, isFalse);
      expect(find.text('接着上次听？'), findsNothing);
    });
  });
}
