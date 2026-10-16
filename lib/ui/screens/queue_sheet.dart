import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/subsonic_payload.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';

/// 揭开播放队列面板。
void showQueueSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => const _QueueSheet(),
  );
}

/// 播放队列 —— 可拖动重排、可移除。
///
/// **正在播放的那一首不给移除** —— 移掉它播放器会停,用户会以为
/// 「点一下把歌停了」。所以那一行的删除按钮置灰,并在拖动时放行
/// (拖动改变的是顺序,不是播放对象)。
class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final playable = context.watch<PlaybackController>();
    final appState = context.watch<AppState>();
    final queue = playable.queue;
    final currentIndex = playable.state.song == null
        ? -1
        : queue.indexWhere((s) => s.id == playable.state.song!.id);

    return NordicScrim(
      onTap: () => Navigator.of(context).pop(),
      child: NordicSheet(
        title: '播放队列',
        subtitle: queue.isEmpty
            ? null
            : '${queue.length} 首 · 还有约 ${formatRemaining(playable.remaining)}',
        child: queue.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: NordicSpace.s7),
                child: EmptyState(
                  title: '队列是空的',
                  detail: '从音乐库点一首歌会开始排队。',
                  topPadding: 0,
                ),
              )
            : Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: NordicSpace.s4),
                  itemCount: queue.length,
                  // onReorderItem 已经替我们算好了移除旧项之后的插入下标,
                  // 所以不需要在手柄里再 `newIndex > oldIndex ? -1 : 0` 一次。
                  onReorderItem: playable.reorder,
                  itemBuilder: (context, index) {
                    final song = queue[index];
                    final isCurrent = index == currentIndex;
                    return _QueueRow(
                      // ReorderableListView 要求稳定的 key。
                      key: ValueKey('${song.id}-$index'),
                      index: index,
                      song: song,
                      isCurrent: isCurrent,
                      playing: playable.state.playing,
                      coverUri: _coverUri(appState, song.coverArtId),
                      onTap: () => playable.jumpTo(index),
                      onRemove: isCurrent
                          ? null
                          : () => playable.removeAt(index),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Uri? _coverUri(AppState state, String? artId) {
    final repo = state.repository;
    if (repo == null || artId == null) return null;
    try {
      return repo.coverUri(artId, size: 128);
    } on SubsonicException {
      return null;
    }
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.index,
    required this.song,
    required this.isCurrent,
    required this.playing,
    required this.coverUri,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final Song song;
  final bool isCurrent;
  final bool playing;
  final Uri? coverUri;
  final VoidCallback onTap;

  /// null 表示当前在播的那一首 —— 不给移除。
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              // 拖动把手。原型的队列也支持长按拖动,这里用显式把手 ——
              // 列表本身还要点选,长按与点击的手势会打架。
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NordicSpace.s3, vertical: NordicSpace.s4),
                  child: Icon(Icons.drag_handle, size: 18, color: t.fg4),
                ),
              ),
              SizedBox(
                width: 18,
                child: isCurrent && playing
                    ? PlayingBars(size: 15, color: context.accentSafe)
                    : null,
              ),
              const SizedBox(width: NordicSpace.s2),
              Cover(
                coverArtId: song.coverArtId,
                seed: song.albumId,
                uri: coverUri,
                size: 46,
                radius: 12,
                showShadow: false,
              ),
              const SizedBox(width: NordicSpace.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isCurrent ? context.accentSafe : t.fg,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.fg3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NordicSpace.s2),
              Text(
                formatDuration(song.duration),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: t.fg3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(width: NordicSpace.s2),
              SizedBox(
                width: 40,
                child: onRemove == null
                    // 在播的那一首留空位而不是不给按钮 —— 行高与对齐保持一致。
                    ? const SizedBox.shrink()
                    : IconButtonRound(
                        icon: Icons.close,
                        size: 32,
                        iconSize: 16,
                        quiet: true,
                        onPressed: onRemove,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}