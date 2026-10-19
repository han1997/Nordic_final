import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../playback/playback_controller.dart';
import '../../playback/quality.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../widgets/components.dart';
import '../widgets/rows.dart';

/// 歌曲信息 —— 歌曲「⋯」菜单里那条。
///
/// 铺的全是**这一首真有的字段**:服务器随曲目给下来的格式 / 码率 / 体积 /
/// 年份 / 流派 / 入库时间(见 `subsonic_mapper.dart`)。**缺哪一项就整行不印** ——
/// 写一行「未知」是拿假东西凑数,那比没有更糟。
///
/// 歌名与「艺人 · 专辑」在标题那一行(与其它弹层同款),正文里不再重复。
Future<void> showSongInfoSheet(BuildContext context, Song song) {
  final t = context.nordic;
  // 「实际播放」问的是**播放层**,不是这一首自己的字段 —— 所以只有正在放的那一首
  // 问得出答案:别的曲子根本不在现场,那一行就不印(见 playbackOriginLabel)。
  final playable = context.read<PlaybackController>();
  final playing = playable.state.song?.id == song.id;
  final loaded = playing ? playable.loadedQuality : null;
  final local = playing ? playable.loadedLocal : null;
  // 选中的那一档与播放层是**同一个对象**(main.dart 把同一个 QualityController
  // 交给两边),所以从播放层问就够了 —— 这一张纸因此只依赖一个 provider。
  final selected = playable.quality;

  final rows = <(String, String)>[
    if (song.track != null) ('曲序', '第 ${song.track} 首'),
    ('时长', formatDuration(song.duration)),
    if (song.formatLine.isNotEmpty) ('格式', song.formatLine),
    if (song.sizeBytes != null && song.sizeBytes! > 0)
      ('文件大小', formatBytes(song.sizeBytes!)),
    if (song.year != null) ('年份', '${song.year}'),
    if (song.genre != null && song.genre!.isNotEmpty) ('流派', song.genre!),
    if (song.created != null) ('入库时间', formatDay(song.created!)),
    if (playing)
      ('实际播放', playbackOriginLabel(loaded ?? selected, local: local)),
  ];

  return showNordicSheet<void>(
    context: context,
    builder: (sheetContext) => NordicScrim(
      onTap: () => Navigator.of(sheetContext).pop(),
      child: NordicSheet(
        title: song.title,
        subtitle: '${song.artist} · ${song.album}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NordicSpace.s5, NordicSpace.s3, NordicSpace.s5, NordicSpace.s2),
              child: Column(
                children: [
                  for (final (label, value) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            label,
                            style: Theme.of(sheetContext)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: t.fg3),
                          ),
                          const SizedBox(width: NordicSpace.s4),
                          Expanded(
                            child: Text(
                              value,
                              textAlign: TextAlign.right,
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: t.fg,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // 两处去路 —— 看信息的人多半正想「这张专辑还有什么」。
            // 艺人 id 缺了(库里没有这位艺人)就不给那一行,不假装能点。
            NordicMenuRow(
              icon: Icons.album_outlined,
              label: '查看专辑',
              onTap: () {
                Navigator.of(sheetContext).pop();
                AppRoutes.openAlbum(context, song.albumId);
              },
            ),
            if (song.artistId != null)
              NordicMenuRow(
                icon: Icons.person_outline,
                label: '查看艺人',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  AppRoutes.openArtist(context, song.artistId!);
                },
              ),
            const SizedBox(height: NordicSpace.s2),
          ],
        ),
      ),
    ),
  );
}