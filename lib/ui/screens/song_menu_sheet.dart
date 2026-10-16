import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../playback/playback_controller.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../widgets/components.dart';
import 'playlist_picker_sheet.dart';

/// 歌曲的「⋯」背后那张纸 —— 播放页 / 艺人页 / 歌单页 / 歌词页共用一份。
///
/// 原型只有一张(`sheetMenu('song')`,四处菜单底板同一个)。几个页面各写一份
/// 的日子到此为止:它们的差别只有一条 —— 歌单页多一个「从这个歌单移除」,
/// 其余一字不差,而各写一份的结果是同一个动作在不同页面给的措辞不一样。
///
/// [onRemoveFromPlaylist] 非空时,那张纸会多出这一条(放在最前,因为在这种
/// 场景里它就是用户点开「⋯」的目的)。
Future<void> showSongMenu(
  BuildContext context,
  Song song, {
  VoidCallback? onRemoveFromPlaylist,
}) {
  final appState = context.read<AppState>();
  final playable = context.read<PlaybackController>();
  final starred = appState.isSongStarred(song.id);
  final downloaded = appState.isDownloaded(song.id);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      void close() => Navigator.of(sheetContext).pop();

      return NordicScrim(
        onTap: close,
        child: NordicSheet(
          title: song.title,
          subtitle: '${song.artist} · ${song.album}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRemoveFromPlaylist != null)
                NordicMenuRow(
                  icon: Icons.playlist_remove,
                  label: '从这个歌单移除',
                  onTap: () {
                    close();
                    onRemoveFromPlaylist();
                  },
                ),
              NordicMenuRow(
                icon: starred ? Icons.favorite : Icons.favorite_border,
                label: starred ? '取消收藏' : '收藏这首歌',
                onTap: () {
                  close();
                  appState.toggleSongStar(song.id);
                },
              ),
              NordicMenuRow(
                icon: downloaded
                    ? Icons.download_done
                    : Icons.download_outlined,
                // 已经在本机的那首不必再装作能下 —— 图标与文案直接说清楚。
                label: downloaded ? '已下载到本机' : '下载到本机（FLAC）',
                onTap: () {
                  close();
                  if (!downloaded) _download(context, song, appState);
                },
              ),
              NordicMenuRow(
                icon: Icons.playlist_add,
                label: '加入歌单',
                onTap: () {
                  close();
                  showPlaylistPicker(context, song: song);
                },
              ),
              NordicMenuRow(
                icon: Icons.playlist_play,
                label: '下一首播放',
                onTap: () {
                  close();
                  playable.playNext(song);
                },
              ),
              NordicMenuRow(
                icon: Icons.queue_music,
                label: '加入播放队列',
                onTap: () {
                  close();
                  playable.append(song);
                },
              ),
              NordicMenuRow(
                icon: Icons.album_outlined,
                label: '查看专辑',
                onTap: () {
                  close();
                  AppRoutes.openAlbum(context, song.albumId);
                },
              ),
              const SizedBox(height: NordicSpace.s2),
            ],
          ),
        ),
      );
    },
  );
}

/// 下载这首。失败要有话说 —— 按了没反应比报错更糟。
Future<void> _download(
  BuildContext context,
  Song song,
  AppState state,
) async {
  String message;
  try {
    final job = await state.downloadSong(song);
    message = job.queuedNotice;
  } catch (e) {
    message = '$e';
  }

  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}
