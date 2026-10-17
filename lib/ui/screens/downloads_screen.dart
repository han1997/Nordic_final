import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/download_manager.dart';
import '../../data/download_store.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';

/// 下载管理。
///
/// 队列是真队列:下载按钮会把曲目真的拉到本机(见 [DownloadManager]),
/// 进度与体积来自实际的传输,失败会带上服务器给的原因。
/// **已完成的条目播放时走本机文件** —— 断网也能听,那份索引同时喂给
/// 播放层(见 `playback/audio_handler.dart` 的 `playbackOriginFor`)。
///
/// 这一屏也是**断网时的落脚点**:库刷不出来时,已下好的东西从这里点开就能播,
/// 曲目清单来自下载记录自带的元信息(见 [DownloadRecord.tracks])。
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = context.watch<AppState>();
    final jobs = state.downloads;
    final active = state.activeDownloadCount;
    final bytes = jobs.fold<int>(
      0,
      (sum, j) => sum + (j.record?.bytes ?? j.receivedBytes),
    );

    return ImmersiveScaffold(
      accent: context.accent,
      showAmbient: false,
      child: Column(
        children: [
          NordicAppBar(
            title: '下载管理',
            big: false,
            leading: IconButtonRound(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              if (jobs.isNotEmpty)
                Text(
                  '${active > 0 ? '正在下载' : '空闲'} · ${jobs.length} 项',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: t.fg3),
                ),
            ],
          ),
          Expanded(
            child: jobs.isEmpty
                // 真空白:队列确实空着,不是加载中也不是出错。
                ? const EmptyState(
                    title: '队列是空的',
                    detail: '专辑页、艺人页和歌曲菜单的下载按钮会把内容放进这里。',
                  )
                : ListView(
                    padding: EdgeInsets.only(
                      bottom:
                          MediaQuery.paddingOf(context).bottom + NordicSpace.s6,
                    ),
                    children: [
                      SectionHeader(
                        title: '队列',
                        count: '约 ${formatBytes(bytes)}',
                        padding: const EdgeInsets.fromLTRB(
                          NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s3),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NordicSpace.s5),
                        child: Container(
                          decoration: BoxDecoration(
                            color: t.glass3,
                            borderRadius:
                                BorderRadius.circular(NordicRadius.lg),
                            border: Border.all(color: t.line2),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < jobs.length; i++) ...[
                                if (i > 0)
                                  Divider(
                                      height: 1, thickness: 1, color: t.line),
                                _DownloadRow(
                                  job: jobs[i],
                                  onOpen: _openable(jobs[i])
                                      ? () => _openTask(context, jobs[i].record!)
                                      : null,
                                  onRemove: () =>
                                      _remove(context, state, jobs[i]),
                                  onRetry: () =>
                                      state.retryDownload(jobs[i].request.id),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      ListNote(
                        '下载走当前线路,存到本机的 ${DownloadStore.label} 目录。'
                        '已完成的条目点开就能播,断网也一样。',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 这条任务能不能点开 —— 下完了、而且记下了曲目清单才算数。
  /// (老版本的记录里没有 tracks,那些条目只显示进度,点了没反应不如不给点。)
  static bool _openable(DownloadJob job) =>
      job.isDone && (job.record?.tracks.isNotEmpty ?? false);

  /// 点开一条已下好的内容:列出它带着的曲目,点哪首从哪首开始放。
  ///
  /// 队列就是这一整条,所以「从第一首开始」不用另设一个按钮 ——
  /// 列表本身就摆在那里。
  void _openTask(BuildContext context, DownloadRecord record) {
    showNordicSheet<void>(
      context: context,
      builder: (sheetContext) => NordicScrim(
        onTap: () => Navigator.of(sheetContext).pop(),
        child: NordicSheet(
          title: record.name,
          subtitle: '${record.detail} · 已完成 · ${record.sizeLabel}',
          child: _OfflineTracks(record: record),
        ),
      ),
    );
  }

  /// 删掉一条任务。**已下好的会连同文件一起删**,所以先问一句 ——
  /// 几百 MB 重新拉一遍要花流量,不该点错一次就没了。
  Future<void> _remove(
    BuildContext context,
    AppState state,
    DownloadJob job,
  ) async {
    if (job.isDone) {
      final record = job.record;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: dialogContext.nordic.glass3,
          title: const Text('删除本机文件?'),
          content: Text(
            '『${job.request.name}』在本机的 ${record?.files.length ?? 0} 个文件'
            '会被删掉,释放约 ${record?.sizeLabel ?? '这些'} 空间。'
            '以后还能重新下载。',
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('删除', style: TextStyle(color: context.nordic.bad)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await state.removeDownload(job.request.id);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(job.isDone ? '已删除本机文件' : '已取消这条下载'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.job,
    required this.onRemove,
    required this.onRetry,
    this.onOpen,
  });

  final DownloadJob job;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  /// 点开这一条(下好了才有)。null 表示这条打不开 —— 没下完的点了也没东西可听。
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accentSafe = context.accentSafe;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NordicSpace.s5, vertical: NordicSpace.s4),
      child: Row(
        children: [
          SettingIcon(
            icon: _icon,
            color: switch (job.state) {
              DownloadState.done => t.ok,
              DownloadState.failed => t.bad,
              _ => accentSafe,
            },
          ),
          const SizedBox(width: NordicSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.request.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  job.statusLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: job.state == DownloadState.failed
                          ? t.bad
                          : t.fg3),
                ),
                const SizedBox(height: 6),
                // 失败的那条也留着进度 —— 它说明「下到哪儿断的」,
                // 比一条空线更能解释重试会从哪儿接着走。
                ProgressLine(progress: job.pct / 100),
              ],
            ),
          ),
          const SizedBox(width: NordicSpace.s3),
          // 能点开的给一个「进得去」的记号 —— 一行能点的东西看不出来能点,
          // 等于没做。
          if (onOpen != null)
            Icon(Icons.chevron_right, size: 18, color: t.fg3),
          if (job.state == DownloadState.failed)
            IconButtonRound(
              icon: Icons.refresh,
              size: 32,
              iconSize: 16,
              quiet: true,
              onPressed: onRetry,
            ),
          IconButtonRound(
            icon: Icons.close,
            size: 32,
            iconSize: 16,
            quiet: true,
            onPressed: onRemove,
          ),
        ],
      ),
    );

    if (onOpen == null) return row;
    // 这张卡在玻璃上,InkWell 的涟漪会被玻璃盖住(理由见 quality_sheet.dart)。
    return Pressable(
      onTap: onOpen,
      pressedDecoration: BoxDecoration(
        color: t.fill1,
        borderRadius: BorderRadius.circular(NordicRadius.lg),
      ),
      child: row,
    );
  }

  IconData get _icon => switch (job.state) {
        DownloadState.done => Icons.check,
        DownloadState.failed => Icons.error_outline,
        DownloadState.active => Icons.download,
        DownloadState.waitingWifi => Icons.wifi_off,
        DownloadState.waitingNetwork => Icons.cloud_off,
        DownloadState.queued => Icons.schedule,
      };
}

/// 短列表按内容撑高、长列表懒加载的分界(与队列面板同一套口径)。
const _shrinkWrapLimit = 40;

/// 一条已下好的内容里的曲目 —— 从下载记录自带的元信息里读,
/// **不查服务器**:断网时它得照样列得出来,这正是这一屏存在的理由。
class _OfflineTracks extends StatelessWidget {
  const _OfflineTracks({required this.record});

  final DownloadRecord record;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final playable = context.watch<PlaybackController>();
    final currentId = playable.state.song?.id;

    return ConstrainedBox(
      // 一张专辑几十首,纸不能长到屏幕外。
      constraints: const BoxConstraints(maxHeight: 380),
      child: ListView.builder(
        // 与队列面板同一套:短的按内容撑高,长的懒加载(整张专辑可能有几百首)。
        shrinkWrap: record.tracks.length <= _shrinkWrapLimit,
        padding: const EdgeInsets.only(bottom: NordicSpace.s4),
        itemCount: record.tracks.length,
        itemBuilder: (context, i) {
          final song = record.tracks[i];
          final isCurrent = song.id == currentId;
          return NordicRow(
            height: 60,
            leading: Cover(
              coverArtId: song.coverArtId,
              seed: song.albumId,
              // 本机那份封面优先 —— 这张图就在隔壁目录里。
              uri: state.coverUriFor(song.coverArtId, size: 128),
              size: 42,
              radius: 10,
              showShadow: false,
            ),
            title: song.title,
            titleColor: isCurrent ? context.accentSafe : null,
            subtitle: song.artist,
            onTap: () {
              Navigator.of(context).pop();
              playable.playAll(record.tracks, index: i);
            },
          );
        },
      ),
    );
  }
}
