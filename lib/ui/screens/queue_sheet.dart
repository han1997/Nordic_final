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

/// 短队列按内容撑高、长队列懒加载的分界:40 行建出来大约几毫秒,
/// 再往上(从一张五百首的专辑开播就是五百行)就开始掉帧了。
const _shrinkWrapLimit = 40;

/// 揭开播放队列面板。
void showQueueSheet(BuildContext context) {
  showNordicSheet<void>(
    context: context,
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
    // 显示顺序 → 原始下标。随机开着时 just_audio 按**自己的**顺序播,而 queue
    // 仍是装载时的顺序 —— 照 queue 铺,面板写的「下一首」就是假的。
    final order = playable.queueOrder;
    final shuffled = playable.state.shuffle;

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
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 随机开着时**不给拖动排序**:拖的是原始列表,和眼前这份
                  // 顺序对不上,拖完只会莫名其妙。说明一句,免得以为是坏了。
                  if (shuffled)
                    const ListNote('随机播放中，这里按实际播放顺序列出（这一档不能拖动排序）。'),
                  Flexible(
                    child: ReorderableListView.builder(
                      // 短队列按内容撑高(三个条目不该占满整屏),长的则**懒加载** ——
                      // 从一张五百首的专辑开播时,一次把这五百行建出来是能看出来的卡。
                      shrinkWrap: order.length <= _shrinkWrapLimit,
                      padding: const EdgeInsets.only(bottom: NordicSpace.s4),
                      itemCount: order.length,
                      // onReorderItem 已经替我们算好了移除旧项之后的插入下标,
                      // 所以不需要在手柄里再 `newIndex > oldIndex ? -1 : 0` 一次。
                      // 随机时给一个空实现(把手已经藏了,拖不起来)—— 这个参数
                      // 与 onReorder 必须恰好给一个,不能两个都不给。
                      onReorderItem: shuffled ? (_, _) {} : playable.reorder,
                      itemBuilder: (context, position) {
                        // 行显示在 position,歌本身是原始队列里的 index。
                        final index = order[position];
                        final song = queue[index];
                        final isCurrent = song.id == playable.state.song?.id;
                        return _QueueRow(
                          // ReorderableListView 要求稳定的 key。
                          key: ValueKey('${song.id}-$index'),
                          index: position,
                          draggable: !shuffled,
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
                ],
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
    required this.draggable,
    required this.song,
    required this.isCurrent,
    required this.playing,
    required this.coverUri,
    required this.onTap,
    required this.onRemove,
  });

  /// 这一行在**列表里**的位置(拖动把手要它)。
  final int index;

  /// 随机播放中不给拖 —— 拖的是原始列表,与所见顺序对不上。
  final bool draggable;

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
    // 原先这里是 `Material(color: transparent) + InkWell` —— 为了让涟漪在玻璃
    // 上看得见专门垫了一层。走 [Pressable] 就不必了(与全应用同一套反馈)。
    return Pressable(
      onTap: onTap,
      pressedDecoration: BoxDecoration(color: t.fill1),
      child: SizedBox(
        height: 64,
        child: Row(
            children: [
              // 拖动把手。原型的队列也支持长按拖动,这里用显式把手 ——
              // 列表本身还要点选,长按与点击的手势会打架。
              // 随机播放中藏起来(见 [draggable]):能拖但拖不动最难受。
              if (draggable)
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NordicSpace.s3, vertical: NordicSpace.s4),
                    child: Icon(Icons.drag_handle, size: 18, color: t.fg4),
                  ),
                )
              else
                const SizedBox(width: NordicSpace.s3 + 18 + NordicSpace.s3),
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
    );
  }
}