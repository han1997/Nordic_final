import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/download_manager.dart';
import 'package:nordic/data/download_store.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/subsonic_client.dart';
import 'package:nordic/data/subsonic_payload.dart';
import 'package:nordic/playback/quality.dart';
import 'package:nordic/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 歌单写操作在**状态层**的效果:服务器那边发对了,本地快照也要跟着对。
///
/// 两件事各自都能错:写完不更新本地,用户看到的是旧数字(以为没成功);
/// 或者反过来乐观更新,失败之后本地留着服务器并不认的状态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 按端点回不同载荷的假 Dio,顺带记下每个请求的完整 Uri。
  Dio payloadDio(List<Uri> seen, Map<String, Map<String, dynamic>> byEndpoint) {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, interceptor) {
        seen.add(options.uri);
        final endpoint =
            options.uri.pathSegments.last.replaceAll('.view', '');
        final payload = byEndpoint[endpoint] ?? _ok(const {});
        interceptor.resolve(Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode(payload),
        ));
      },
    ));
    return dio;
  }

  late List<Uri> seen;
  late Map<String, Map<String, dynamic>> endpoints;
  late AppState state;
  late Directory root;

  const config = ServerConfig(
    id: 's1',
    name: '客厅 Navidrome',
    kind: ServerKind.navidrome,
    username: 'u',
    routes: [ServerRoute(id: 'lan', name: '局域网', url: 'http://nas.example.com')],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    seen = [];
    endpoints = {
      'getPlaylists': _ok({
        'playlists': {
          'playlist': [
            {'id': 'pl-1', 'name': '深夜驾驶', 'songCount': 3},
            {'id': 'pl-2', 'name': '通勤', 'songCount': 0},
          ]
        }
      }),
      'getAlbumList2': _ok({'albumList2': {'album': []}}),
      'getArtists': _ok({'artists': {'index': []}}),
      'search3': _ok({'searchResult3': {'song': []}}),
      'getStarred2': _ok({'starred2': {}}),
    };

    root = await Directory.systemTemp.createTemp('nordic-pl-state');
    final configStore = await ConfigStore.open();
    final downloads = await DownloadStore.open(root: root);

    late final AppState appState;
    appState = AppState(
      configStore: configStore,
      credentialStore: CredentialStore(),
      quality: QualityController(),
      downloadManager: DownloadManager(
        store: downloads,
        repository: () => appState.repository,
        wifiOnly: () => false,
      ),
      dio: payloadDio(seen, endpoints),
    );
    state = appState;

    appState.adoptServer(config);
    appState.attachRepository(config, 'p');
    await appState.loadLibrary();
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('库里那份歌单是服务器给的那两条', () {
    expect(state.library.playlists.map((p) => p.name), ['深夜驾驶', '通勤']);
  });

  test('加一首进歌单:本地条数立刻跟着变', () async {
    await state.addSongToPlaylist('pl-1', 'song-9');

    final write = seen.last;
    expect(write.path, '/rest/updatePlaylist.view');
    expect(write.queryParameters['songIdToAdd'], 'song-9');
    // 不重拉整库(那会打断浏览),但数字不能停在旧的 —— 否则「已加入」
    // 与列表里的「3 首」互相打脸。
    expect(state.library.playlists.first.songCount, 4);
    expect(state.library.playlists.last.songCount, 0, reason: '没被点到的歌单不该跟着变');
  });

  test('从歌单移除一首:本地条数减一', () async {
    await state.removeSongFromPlaylist('pl-1', 1);

    expect(seen.last.queryParameters['songIndexToRemove'], '1');
    expect(state.library.playlists.first.songCount, 2);
  });

  test('重命名:首尾空格去掉,本地名字立刻跟着改', () async {
    await state.renamePlaylist('pl-1', '  夜间驾驶  ');

    expect(seen.last.queryParameters['name'], '夜间驾驶');
    expect(state.library.playlists.first.name, '夜间驾驶');
  });

  test('删除:本地列表里也就不再有它', () async {
    await state.deletePlaylist('pl-1');

    expect(seen.last.path, '/rest/deletePlaylist.view');
    expect(state.library.playlists.map((p) => p.id), ['pl-2']);
  });

  test('服务器拒绝时本地不留假象', () async {
    endpoints['updatePlaylist'] = _failed('Not allowed');

    await expectLater(
      state.addSongToPlaylist('pl-1', 'song-9'),
      throwsA(isA<SubsonicException>()),
    );
    // 先改本地再发请求的乐观更新在这里是错的:服务器没答应,列表却已经变了。
    expect(state.library.playlists.first.songCount, 3);
  });

  test('还没连服务器时说人话,而不是静默失败', () async {
    final bare = AppState(
      configStore: state.configStore,
      credentialStore: state.credentialStore,
      quality: state.quality,
      downloadManager: state.downloadManager,
    );

    await expectLater(
      bare.addSongToPlaylist('pl-1', 'song-9'),
      throwsA(isA<SubsonicException>()
          .having((e) => e.message, 'message', contains('还没有连接服务器'))),
    );
  });
}

Map<String, dynamic> _ok(Map<String, dynamic> body) => {
      'subsonic-response': {
        'status': 'ok',
        'version': '1.16.1',
        ...body,
      }
    };

Map<String, dynamic> _failed(String message) => {
      'subsonic-response': {
        'status': 'failed',
        'version': '1.16.1',
        'error': {'code': 50, 'message': message},
      }
    };
