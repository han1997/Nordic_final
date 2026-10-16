import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/subsonic_payload.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';

/// 底部常驻区:播放坞 + 标签栏 —— `.bottomstack`。
///
/// 用 [Stack] 浮在内容之上而不是放进正常流:玻璃**身后必须有内容**才有东西
/// 可模糊,放流里的话后面是空的,模糊出来只是一块灰。
///
/// 内容区要自己留出下边距,免得最后一行被压在坞下面(见 [bottomInset])。
class BottomStack extends StatelessWidget {
  const BottomStack({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    this.showDock = true,
  });

  final AppTab activeTab;
  final ValueChanged<AppTab> onTabSelected;

  /// 沉浸页(播放 / 歌词)不显示坞 —— 那一屏整屏都是播放控制。
  final bool showDock;

  /// 列表需要留出的底部空间。坞 62 + 间距 8 + 标签栏 66 + 四周留白。
  static const bottomInset = 150.0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: EdgeInsets.only(
          left: 10,
          right: 10,
          bottom: MediaQuery.paddingOf(context).bottom + 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDock) ...[
              const _PlayerDock(),
              const SizedBox(height: 8),
            ],
            _TabBar(active: activeTab, onSelected: onTabSelected),
          ],
        ),
      ),
    );
  }
}

/// 播放坞 —— `.dock`。点它进播放页。
class _PlayerDock extends StatelessWidget {
  const _PlayerDock();

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final appState = context.watch<AppState>();
    final playback = context.watch<PlaybackController>();
    final song = playback.state.song;

    // 还没放过任何东西时不占位 —— 空坞是一块没有意义的玻璃。
    if (song == null) return const SizedBox.shrink();

    final playing = playback.state.playing;
    final progress = playback.state.progress / 100;

    return NordicGlass(
      panel: NordicGlassPanel.nav,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pushNamed('/player'),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 62,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Cover(
                      coverArtId: song.coverArtId,
                      seed: song.albumId,
                      uri: _coverUriFor(appState, song),
                      size: 46,
                      radius: 13,
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
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${song.artist} · ${song.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: t.fg3),
                          ),
                        ],
                      ),
                    ),
                    IconButtonRound(
                      icon: playing ? Icons.pause : Icons.play_arrow,
                      iconSize: 25,
                      onPressed: playback.toggle,
                    ),
                    IconButtonRound(
                      icon: Icons.skip_next,
                      iconSize: 23,
                      onPressed: playback.next,
                    ),
                  ],
                ),
              ),
              // 坞底那条细线 —— 「现在就播着」的进度。
              Positioned(
                left: 12,
                right: 12,
                bottom: 0,
                child: ProgressLine(progress: progress, height: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Uri? _coverUriFor(AppState state, Song song) {
    final repo = state.repository;
    final id = song.coverArtId;
    if (repo == null || id == null) return null;
    try {
      return repo.coverUri(id, size: 128);
    } on SubsonicException {
      // 还没配好线路时取不到 —— 坞里退回渐变兜底即可,不必报错。
      return null;
    }
  }
}

/// 标签栏 —— `.tabbar`。选中项做成一颗凹进去的玻璃胶囊:记住的是位置,不是颜色。
class _TabBar extends StatelessWidget {
  const _TabBar({required this.active, required this.onSelected});

  final AppTab active;
  final ValueChanged<AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent.accent;

    return NordicGlass(
      panel: NordicGlassPanel.nav,
      child: SizedBox(
        height: 66,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              for (final tab in AppTab.values)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onSelected(tab),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        color: tab == active
                            ? accent.withValues(alpha: 0.17)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(NordicRadius.full),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            tab.icon,
                            size: 21,
                            color: tab == active ? context.accentSafe : t.fg3,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tab.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: tab == active ? t.fg : t.fg3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 三个一级页面 —— 原型 tabbar 的取值。
enum AppTab {
  library('/library', '音乐库', Icons.menu_book_outlined),
  search('/search', '搜索', Icons.search),
  settings('/settings', '设置', Icons.settings_outlined);

  const AppTab(this.route, this.label, this.icon);

  final String route;
  final String label;
  final IconData icon;

  static AppTab? forRoute(String route) =>
      values.where((t) => t.route == route).firstOrNull;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}