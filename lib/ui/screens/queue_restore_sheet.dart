import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/rows.dart';

/// 服务器上留下的那一份队列(见 `state/app_state.dart` 的 `pendingQueueRestore`)。
typedef PendingQueueRestore = ({
  List<Song> songs,
  String? currentId,
  Duration position,
  String mark,
});

/// 「接着上次听?」—— 启动时读到服务器上有一份**别的设备**留下的队列。
///
/// **为什么要问一句**:换设备、隔了几天再打开,应用自己闷声把队列摆上、还开始
/// 出声,是很奇怪的事。而这条记录本身是服务器上的**共享状态**,谁都能改,
/// 所以「不问就恢复」和「每次都问」都不对 —— 判据在状态层(指纹比对,见
/// `AppState.checkPlayQueue`),这里只负责问。
///
/// 返回 true = 用户按了「继续」(调用点负责装载,**不自动开声**)。
Future<bool> showQueueRestoreSheet(
  BuildContext context,
  PendingQueueRestore pending,
) async {
  final t = context.nordic;
  final current = _currentOf(pending);
  final position = pending.position;

  final answer = await showNordicSheet<bool>(
    context: context,
    builder: (sheetContext) => NordicScrim(
      // 点空白 = 忽略这一次(与「忽略」那颗按钮同一条路:都记下这个指纹,
      // 下次换个队列才会再问)。
      onTap: () => Navigator.of(sheetContext).pop(false),
      child: NordicSheet(
        title: '接着上次听？',
        subtitle: '${pending.songs.length} 首 · 第 ${queueRestoreIndex(pending) + 1} 首',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s4),
              child: Text(
                '服务器上还留着一份播放队列，停在'
                '「${current?.title ?? '某一首'}」的 ${formatDuration(position)}。'
                '这一份是**别的设备**留下的 —— 要不要接着放？',
                style: Theme.of(sheetContext)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: t.fg3, height: 1.6),
              ),
            ),
            NordicMenuRow(
              icon: Icons.play_circle_outline,
              label: '继续',
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            NordicMenuRow(
              icon: Icons.close,
              label: '忽略',
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
            const SizedBox(height: NordicSpace.s2),
          ],
        ),
      ),
    ),
  );
  return answer ?? false;
}

/// 当前那一首在名单里的第几位。找不到(服务器给了个不在名单里的 current)
/// 就是第 1 首 —— 与装载时用的同一条兜底。
/// **公开**:调用点装载时用的也是它,两处各写一份迟早会对不上。
int queueRestoreIndex(PendingQueueRestore pending) {
  final id = pending.currentId;
  if (id == null) return 0;
  final index = pending.songs.indexWhere((s) => s.id == id);
  return index < 0 ? 0 : index;
}

Song? _currentOf(PendingQueueRestore pending) {
  final songs = pending.songs;
  if (songs.isEmpty) return null;
  return songs[queueRestoreIndex(pending)];
}