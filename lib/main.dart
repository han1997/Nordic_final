import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/download_manager.dart';
import 'data/download_store.dart';
import 'data/library_cache.dart';
import 'data/server_config.dart';
import 'data/subsonic_repository.dart';
import 'playback/audio_handler.dart';
import 'playback/playback_controller.dart';
import 'playback/quality.dart';
import 'state/app_state.dart';
import 'ui/widgets/cover.dart';

Future<void> main() async {
  // 起后台播放服务前必须先初始化绑定 —— AudioService.init 会调平台通道。
  WidgetsFlutterBinding.ensureInitialized();

  // 封面磁盘缓存的额度(默认只留 200 个对象,大库上会来回淘汰)。
  configureCoverCache();

  final credentialStore = CredentialStore();

  // 这几件事互不依赖,所以**并行**做:串起来就是把四次 I/O 往返(两次
  // SharedPreferences、一次目录索引、一次系统密钥库)全加在第一帧前面。
  //
  // 三条兜底:下载的与缓存的存储建不出来时各自退化成「用不了」(照常起);
  // 密码读不出来就等于「没配过」(见 server_config 的说明),不该把启动拖塌。
  final (configStore, downloads, libraryCache, savedPassword) = await (
    ConfigStore.open(),
    DownloadStore.open(),
    LibraryCache.open(),
    credentialStore.readPassword().catchError((Object _) => null),
  ).wait;

  final savedConfig = configStore.loadServer();

  // 质量档位要先于播放服务建好 —— 处理器在构造时就会读它。
  final quality = QualityController(
    QualityOption.byId(configStore.loadQuality()),
  );

  // 应用状态先建 —— 播放服务需要它给出**当前**的仓库,
  // 因为服务器配置可以在运行时变。
  //
  // 用 late 局部变量是为了让「下载器读应用状态」与「应用状态持有下载器」
  // 不打架:下载器拿到的是取值函数,真正求值要等到第一次下载,
  // 那时 appState 早就建好了。
  late final AppState appState;

  final downloadManager = DownloadManager(
    store: downloads,
    repository: () => appState.repository,
    wifiOnly: configStore.loadWifiOnlyDownload,
  );

  appState = AppState(
    configStore: configStore,
    credentialStore: credentialStore,
    quality: quality,
    downloadManager: downloadManager,
    libraryCache: libraryCache,
  );

  // 已存过配置就把仓库接上(密码可能为空 —— 那种情况视为「未配置」)。
  final configured = savedConfig != null && savedPassword != null;
  if (configured) {
    appState.adoptServer(savedConfig);
    appState.attachRepository(savedConfig, savedPassword);
  }

  // 播放服务与「铺缓存」**并行**:前者要等平台把前台服务与媒体会话拉起来
  // (这一步通常是启动里的大头),后者只是一次文件读 —— 串起来等于白等。
  final service = _startPlayback(appState, quality, downloads);

  if (configured) {
    // 先把上次的库铺出来:冷启动不必空等一次全量拉取,随后主壳会静默刷新
    // (见 shell.dart 的 post-frame 那一段)。
    await appState.loadCachedLibrary();
  }

  final audioHandler = await service;
  final playback = PlaybackController(audioHandler);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        // QualityController 是 ValueNotifier(即 ChangeNotifier),
        // 必须走 ChangeNotifierProvider —— 放 Provider 会被 debug 检查拦下。
        ChangeNotifierProvider<QualityController>.value(value: quality),
        // 播放层**无条件在场**(见上面的兜底)—— 界面各处都按「它一定有」取用。
        // 早先这里挂过一份可空的注册,好让查询不抛异常;那是错的:
        // `Provider` 不监听 notifier,谁按可空那份 watch,播放状态变化时
        // 就不会重建 —— 播放坞正是这么消失的。
        ChangeNotifierProvider<PlaybackController>.value(value: playback),
        Provider<ConfigStore>.value(value: configStore),
        Provider<CredentialStore>.value(value: credentialStore),
      ],
      child: const NordicApp(),
    ),
  );
}

/// 起播放层。**返回的处理器一定有** —— 界面处处按「它在场」取用
/// (坞、播放页、歌曲菜单),真给了 null 就是整屏报错。
///
/// 两道兜底:
///   1. `AudioService.init` 挂住(平台侧缺权限 / service 声明时它会**静默不返回**,
///      不抛错,界面就停在启动图上无从查起)—— 加超时;
///   2. 超时或失败时退到**直接建一个处理器**(绕过 AudioService.init):
///      队列 / 播放 / 本地文件都能用,少的只是通知栏与锁屏那层控制。
Future<NordicAudioHandler> _startPlayback(
  AppState appState,
  QualityController quality,
  DownloadStore downloads,
) async {
  try {
    final handler = await startAudioService(
      repository: () => appState.repository,
      quality: quality,
      // 播放时先查这份索引:下过的曲子直接播本机文件,不再走网络。
      downloads: downloads,
    ).timeout(const Duration(seconds: 8));
    await handler.configureSession();
    return handler;
  } on TimeoutException catch (e) {
    debugPrint('后台播放服务启动超时,退到没有通知栏控制的播放层:$e');
  } catch (e) {
    debugPrint('后台播放服务启动失败,退到没有通知栏控制的播放层:$e');
  }

  return NordicAudioHandler(
    () => appState.repository,
    quality,
    downloads: downloads,
  );
}
