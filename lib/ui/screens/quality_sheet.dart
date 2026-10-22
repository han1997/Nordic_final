import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../playback/playback_controller.dart';
import '../../playback/quality.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';

/// 揭开转码质量面板 —— 播放页与设置页共用同一张。
void showQualitySheet(BuildContext context) {
  showNordicSheet<void>(
    context: context,
    builder: (sheetContext) => const _QualitySheet(),
  );
}

class _QualitySheet extends StatelessWidget {
  const _QualitySheet();

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final current = context.watch<QualityController>().value;
    final appState = context.read<AppState>();
    final playable = context.read<PlaybackController>();
    final song = playable.state.song;

    // 面板要说明「原文件长什么样」,用户才知道切档会损失多少。
    final originalLine = song == null
        ? '当前没有在播的曲目'
        : [
            if (song.suffix != null) song.suffix!.toUpperCase(),
            if (song.bitRate != null) '${song.bitRate} kbps',
          ].join(' ');

    return NordicScrim(
      onTap: () => Navigator.of(context).pop(),
      child: NordicSheet(
        title: '转码质量',
        subtitle: originalLine.isEmpty ? null : '原文件 $originalLine',
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s4),
                child: Text(
                  '档位由服务器实时转码后推送。切到转码档后拖动进度会重新请求音频，'
                  '可能有短暂停顿。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.fg3, height: 1.6),
                ),
              ),
              for (final option in QualityOption.all)
                NordicOptionRow(
                  label: option.name,
                  tag: option.tag,
                  description: option.description,
                  selected: option.id == current.id,
                  onTap: () => _pick(
                    context,
                    appState,
                    playable,
                    option,
                  ),
                ),
              const SizedBox(height: NordicSpace.s2),
            ],
          ),
        ),
      ),
    );
  }
}


/// 选一档。**失败要说话** —— 换档会整队重装,那一步会失败(没有仓库 /
/// 服务器不给这一首),而原先这里是裸 await:异常从那颗选项的 `onTap`
/// 冒出去,用户看到的是「点了一档、没有任何反应,档位也还是旧的」。
Future<void> _pick(
  BuildContext context,
  AppState appState,
  PlaybackController playable,
  QualityOption option,
) async {
  Navigator.of(context).pop();
  final messenger = ScaffoldMessenger.maybeOf(context);
  // 同时写进设置(下次启动沿用)并让播放器立刻换档。
  await appState.setQuality(option);
  final failure = await playable.setQuality(option);
  if (failure == null) return;
  messenger?.showSnackBar(SnackBar(
    content: Text('没能切到「${option.name}」 —— $failure'),
    duration: const Duration(seconds: 3),
  ));
}