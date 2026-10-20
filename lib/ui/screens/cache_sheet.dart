import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/media_cache.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/rows.dart';

/// 揭开缓存上限面板 —— 设置页里那行「歌曲缓存」。
void showCacheSheet(BuildContext context) {
  showNordicSheet<void>(
    context: context,
    builder: (sheetContext) => const _CacheSheet(),
  );
}

/// 上限档位面板。**与转码质量同一副骨架**(选项行 + 勾),
/// 不另造一种弹层 —— 这一屏里两者都是「选一档,立刻生效并记住」。
class _CacheSheet extends StatelessWidget {
  const _CacheSheet();

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = context.watch<AppState>();
    final current = state.cacheLimit;

    return NordicScrim(
      onTap: () => Navigator.of(context).pop(),
      child: NordicSheet(
        title: '歌曲缓存',
        // 上限只有跟占用摆在一起才有意义 —— 否则用户改完数字不知道是松了还是紧了。
        subtitle: '已用 ${formatBytes(state.cacheUsedBytes)}',
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s4),
                child: Text(
                  '听过的歌会在本机留一份，再听直接从本机取，断网也能放。'
                  '上限到了会先扔掉最久没听的；下载是用户点名要的，'
                  '不在这里面，永远不会被扔掉。开着「仅 Wi-Fi 下载」时，'
                  '流量下不留新的缓存（已经留着的照旧能听）。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.fg3, height: 1.6),
                ),
              ),
              for (final option in CacheLimit.all)
                NordicOptionRow(
                  label: option.name,
                  description: option.description,
                  selected: option.id == current.id,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await state.setCacheLimit(option);
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
