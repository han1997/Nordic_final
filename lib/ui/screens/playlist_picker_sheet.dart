import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/rows.dart';

/// 「加入歌单」—— 列出库里的歌单,点一条就把这首歌加进去。
///
/// 用底部纸而不是单独一屏:这是「顺手把这首塞进某个歌单」的小动作,
/// 走进去再退出来会打断正在听的东西(点它的时候多半还在放歌)。
///
/// 歌单列表取自本地快照([AppState.library]),不为这一个动作再打一次服务器 ——
/// 库里那份就是用户在歌单页看到的同一份,两处不同步比慢一点更糟。
Future<void> showPlaylistPicker(BuildContext context, {required Song song}) {
  final state = context.read<AppState>();

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => NordicScrim(
      onTap: () => Navigator.of(sheetContext).pop(),
      child: NordicSheet(
        title: '加入歌单',
        subtitle: '${song.title} · ${song.artist}',
        child: _PickerBody(
          playlists: state.library.playlists,
          ready: state.phase == LoadPhase.ready,
          onPick: (playlist) => _add(context, sheetContext, playlist, song),
        ),
      ),
    ),
  );
}

Future<void> _add(
  BuildContext context,
  BuildContext sheetContext,
  Playlist playlist,
  Song song,
) async {
  Navigator.of(sheetContext).pop();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final state = context.read<AppState>();

  try {
    await state.addSongToPlaylist(playlist.id, song.id);
    messenger?.showSnackBar(SnackBar(
      content: Text('已加入「${playlist.name}」'),
      duration: const Duration(seconds: 2),
    ));
  } catch (e) {
    // 失败要说出来 —— 点了「加入歌单」却什么都没发生,用户会以为加上了。
    messenger?.showSnackBar(SnackBar(
      content: Text('没能加入「${playlist.name}」:$e'),
      duration: const Duration(seconds: 3),
    ));
  }
}

class _PickerBody extends StatelessWidget {
  const _PickerBody({
    required this.playlists,
    required this.ready,
    required this.onPick,
  });

  final List<Playlist> playlists;

  /// 曲库加载好了没有 —— 没好之前「没有歌单」是个假结论。
  final bool ready;

  final void Function(Playlist) onPick;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s6),
        child: Text(
          ready ? '库里还没有歌单。到「音乐库 · 歌单」里新建一个。' : '曲库还在加载,稍等一下再试。',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.nordic.fg3, height: 1.6),
        ),
      );
    }

    return ConstrainedBox(
      // 歌单多了要能滑,但不能把整张纸撑到屏幕外。
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: NordicSpace.s4),
        itemCount: playlists.length,
        itemBuilder: (context, i) {
          final playlist = playlists[i];
          return NordicRow(
            height: 60,
            leading: SettingIcon(
              icon: Icons.queue_music,
              color: context.accentSafe,
            ),
            title: playlist.name,
            subtitle: '${playlist.songCount} 首',
            trailing: Icon(Icons.add, size: 18, color: context.nordic.fg3),
            onTap: () => onPick(playlist),
          );
        },
      ),
    );
  }
}
