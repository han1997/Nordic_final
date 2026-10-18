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
                _QualityOptionRow(
                  option: option,
                  selected: option.id == current.id,
                  onTap: () async {
                    Navigator.of(context).pop();
                    // 同时写进设置(下次启动沿用)并让播放器立刻换档。
                    await appState.setQuality(option);
                    await playable.setQuality(option);
                  },
                ),
              const SizedBox(height: NordicSpace.s2),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityOptionRow extends StatelessWidget {
  const _QualityOptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final QualityOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    // 玻璃里的行**不能用 InkWell**:涟漪画在 Material 的墨层上,而那一层在这张
    // 纸的玻璃底下 —— 按下去屏幕上什么都不动。原型的 `.qopt:hover` 本来就是
    // 换一层底色,这里照它来。
    return Pressable(
      onTap: onTap,
      pressedDecoration: BoxDecoration(color: t.fill1),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NordicSpace.s5, vertical: NordicSpace.s4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        option.name,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: selected ? context.accentSafe : t.fg,
                            ),
                      ),
                      if (option.tag != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: t.fill2,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            option.tag!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: t.fg3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: t.fg3,
                          height: 1.5,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NordicSpace.s3),
            NordicTick(selected: selected),
          ],
        ),
      ),
    );
  }
}