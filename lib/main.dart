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

  // 只有配置与密码都在时才起播放服务并建仓库 —— 否则界面进「添加服务器」,
  // 不该有一个连不上任何东西的播放器在那儿。
  final hasServer = savedConfig != null && savedPassword != null;
  final repository = hasServer
      ? SubsonicRepository(
          clientFor(config: savedConfig, password: savedPassword),
        )
      : null;

  NordicAudioHandler? audioHandler;
  PlaybackController? playback;
  if (repository != null) {
    audioHandler = await startAudioService(
      repository: repository,
      quality: quality,
    );
    await audioHandler.configureSession();
    playback = PlaybackController(audioHandler);
  }

  final appState = AppState(
    configStore: configStore,
    credentialStore: credentialStore,
    quality: quality,
  );
  if (savedConfig != null) appState.adoptServer(savedConfig);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        // QualityController 是 ValueNotifier(即 ChangeNotifier),
        // 必须走 ChangeNotifierProvider —— 放 Provider 会被 debug 检查拦下。
        ChangeNotifierProvider<QualityController>.value(value: quality),
        Provider<ConfigStore>.value(value: configStore),
        Provider<CredentialStore>.value(value: credentialStore),
        if (playback != null)
          ChangeNotifierProvider<PlaybackController>.value(value: playback),
      ],
      child: const NordicApp(),
    ),
  );
}