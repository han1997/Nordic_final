import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/sorting.dart';
import '../../data/subsonic_repository.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';

/// 排序面板 —— 与转码面板同一副骨架(选项行 + 勾),不另造一种弹层。
///
/// 一次只排一栏:[albums] 为真就是「全部专辑」那一栏,否则是「全部歌曲」。
Future<void> showSortSheet(BuildContext context, {required bool albums}) {
  final state = context.read<AppState>();

  // 两个枚举各排各的栏,先拍平成同一副样子再铺 —— 面板不该知道它铺的是哪一种。
  final rows = albums
      ? [
          for (final sort in AlbumSort.values)
            _Option(name: sort.name, label: '按${sort.label}',
                selected: sort == state.albumSort),
        ]
      : [
          for (final sort in SongSort.values)
            _Option(name: sort.name, label: '按${sort.label}',
                selected: sort == state.songSort),
        ];

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => NordicScrim(
      onTap: () => Navigator.of(sheetContext).pop(),
      child: NordicSheet(
        title: albums ? '专辑排序' : '歌曲排序',
        subtitle: '只影响「${albums ? '全部专辑' : '全部歌曲'}」这一栏',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in rows)
              _SortOptionRow(
                label: row.label,
                selected: row.selected,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pick(context, state, albums, row.name);
                },
              ),
            const SizedBox(height: NordicSpace.s2),
          ],
        ),
      ),
    ),
  );
}

/// 换口径。专辑那一栏要重打一次服务器(「最近播放 / 常听」本地算不出来),
/// 所以失败是可能的 —— 说一声,别让列表静静地没变。
Future<void> _pick(
  BuildContext context,
  AppState state,
  bool albums,
  String name,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (albums) {
      await state.setAlbumSort(AlbumSort.byName(name));
    } else {
      await state.setSongSort(SongSort.byName(name));
    }
  } catch (e) {
    messenger?.showSnackBar(SnackBar(
      content: Text('没能换排序:$e'),
      duration: const Duration(seconds: 3),
    ));
  }
}

class _Option {
  const _Option({
    required this.name,
    required this.label,
    required this.selected,
  });

  final String name;
  final String label;
  final bool selected;
}

class _SortOptionRow extends StatelessWidget {
  const _SortOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NordicSpace.s5, vertical: NordicSpace.s4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? context.accentSafe : null,
                    ),
              ),
            ),
            NordicTick(selected: selected),
          ],
        ),
      ),
    );
  }
}
