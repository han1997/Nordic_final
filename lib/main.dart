import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/download_manager.dart';
import 'data/download_store.dart';
import 'data/server_config.dart';
import 'data/subsonic_repository.dart';
import 'playback/audio_handler.dart';
import 'playback/playback_controller.dart';
import 'playback/quality.dart';
import 'state/app_state.dart';

Future<void> main() async {
  // 起后台播放服务前必须先初始化绑定 —— AudioService.init 会调平台通道。
  WidgetsFlutterBinding.ensureInitialized();

  final configStore = await ConfigStore.open();
  final credentialStore = CredentialStore();

  // 下载内容的落盘处与下载器。存储不可用时它会退化成一块「用不了」的
  // 索引(见 DownloadStore.open),应用照常起 —— 只是下载入口会给人话。
  final downloads = await DownloadStore.open();

  final savedConfig = configStore.loadServer();
  final savedPassword = await credentialStore.readPassword();

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
  );

  // 已存过配置就把仓库接上(密码可能为空 —— 那种情况视为「未配置」)。
  if (savedConfig != null && savedPassword != null) {
    appState.adoptServer(savedConfig);
    appState.attachRepository(savedConfig, savedPassword);
  }

  // 播放服务**无条件启动**。它必须有:
  //   1. 界面在任何时候都可能渲染播放坞与播放页,提供者缺席会直接崩;
  //   2. audio_service 的前台服务与媒体会话是应用级资源,
  //      按「有没有配服务器」来决定它存不存在,会让配置变更时状态难收拾。
  // 未配置时它就是个空队列的处理器,不会发任何请求。
  //
  // 加超时兜底:平台侧若因权限 / service 声明缺失而挂住,`AudioService.init`
  // 会**静默不返回**(不抛错),界面就停在启动图上无从查起。
  // 兜底成一个空处理器后应用照样能用,只是没有通知栏控制。
  NordicAudioHandler? audioHandler;
  try {
    audioHandler = await startAudioService(
      repository: () => appState.repository,
      quality: quality,
      // 播放时先查这份索引:下过的曲子直接播本机文件,不再走网络。
      downloads: downloads,
    ).timeout(const Duration(seconds: 8));
    await audioHandler.configureSession();
  } on TimeoutException catch (e) {
    debugPrint('后台播放服务启动超时,应用继续但没有通知栏控制:$e');
  } catch (e) {
    debugPrint('后台播放服务启动失败:$e');
  }

  final playback = audioHandler == null
      ? null
      : PlaybackController(audioHandler);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        // QualityController 是 ValueNotifier(即 ChangeNotifier),
        // 必须走 ChangeNotifierProvider —— 放 Provider 会被 debug 检查拦下。
        ChangeNotifierProvider<QualityController>.value(value: quality),
        if (playback != null)
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
        // 可空的那一份给「应用退到后台」这条规则用:播放层起不来时它是 null,
        // 那件事得有地方表达,而不是让查询抛一个「找不到 provider」。
        Provider<PlaybackController?>.value(value: playback),
        Provider<ConfigStore>.value(value: configStore),
        Provider<CredentialStore>.value(value: credentialStore),
      ],
      child: const NordicApp(),
    ),
  );
}