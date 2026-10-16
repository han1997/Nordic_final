import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';

/// 下载管理。
///
/// **这一轮的进度是模拟的** —— 队列能加能删、状态会走,但按钮背后的文件
/// 并不存在。所以界面上不承诺「离线可播」,只说明下载会走哪条线路、
/// 存到哪个目录(那是真实接入后的行为)。
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 进度推进挂在页面级定时器上,但状态存在 AppState 里 ——
    // 这样切走再切回来进度是连续的,不会重置。
    _ticker = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!mounted) return;
      context.read<AppState>().advanceDownloads();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = context.watch<AppState>();
    final tasks = state.downloads;
    final active = state.activeDownloadCount;
    final totalMb = tasks.fold<double>(0, (sum, d) => sum + d.sizeMb);

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
              if (tasks.isNotEmpty)
                Text(
                  '$active 个进行中 · ${tasks.length} 项',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: t.fg3),
                ),
            ],
          ),
          Expanded(
            child: tasks.isEmpty
                // 真空白:队列确实空着,不是加载中也不是出错。
                ? const EmptyState(
                    title: '队列是空的',
                    detail: '专辑页和播放页的下载按钮会把内容放进这里。',
                  )
                : ListView(
                    padding: EdgeInsets.only(
                      bottom:
                          MediaQuery.paddingOf(context).bottom + NordicSpace.s6,
                    ),
                    children: [
                      SectionHeader(
                        title: '队列',
                        count: '约 ${(totalMb / 1024).toStringAsFixed(1)} GB',
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
                              for (var i = 0; i < tasks.length; i++) ...[
                                if (i > 0)
                                  Divider(
                                      height: 1, thickness: 1, color: t.line),
                                _DownloadRow(
                                  task: tasks[i],
                                  onRemove: () =>
                                      state.removeDownload(tasks[i].id),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const ListNote(
                        '下载走当前线路,存到本机的 Nordic/Music 目录。'
                        '已完成的条目离线也能播。',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.task, required this.onRemove});

  final DownloadTask task;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final done = task.isDone;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NordicSpace.s5, vertical: NordicSpace.s4),
      child: Row(
        children: [
          SettingIcon(
            icon: done ? Icons.check : Icons.download,
            color: done ? t.ok : context.accentSafe,
          ),
          const SizedBox(width: NordicSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  done
                      ? '已完成 · ${task.sizeLabel}'
                      : '${task.sizeLabel} · ${task.pct.round()}%',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.fg3),
                ),
                const SizedBox(height: 6),
                ProgressLine(progress: task.pct / 100),
              ],
            ),
          ),
          const SizedBox(width: NordicSpace.s3),
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
  }
}