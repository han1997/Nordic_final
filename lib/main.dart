import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
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

  final savedConfig = configStore.loadServer();
  final savedPassword = await credentialStore.readPassword();

  // 质量档位要先于播放服务建好 —— 处理器在构造时就会读它。
  final quality = QualityController(
    QualityOption.byId(configStore.loadQuality()),
  );

  // 应用状态先建 —— 播放服务需要它给出**当前**的仓库,
  // 因为服务器配置可以在运行时变。
  final appState = AppState(
    configStore: configStore,
    credentialStore: credentialStore,
    quality: quality,
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
        Provider<ConfigStore>.value(value: configStore),
        Provider<CredentialStore>.value(value: credentialStore),
      ],
      child: const NordicApp(),
    ),
  );
}