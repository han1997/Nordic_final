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
/// **合成一颗托盘**(参考飞牛播放器那种下方一体):原先两块各自一颗胶囊、
/// 中间留一道缝 —— 两层玻璃、两条边框、两道光影,读起来是两个各自独立的
/// 东西,而它们本来就是同一件事:现在在听什么,以及去哪儿。合成之后只有
/// 一层玻璃、一条外框,中间用一条线分开,那条线同时就是**进度**。
///
/// 用 [Stack] 浮在内容之上而不是放进正常流:玻璃**身后必须有内容**才有东西
/// 可模糊,放流里的话后面是空的,模糊出来只是一块灰。
///
/// 内容区要自己留出下边距,免得最后一行被压在托盘下面(见 [bottomInset])。
class BottomStack extends StatelessWidget {
  const BottomStack({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    this.showDock = true,
  });

  /// 当前选中的 tab。**可以为空** —— 专辑 / 艺人 / 服务器这几屏也浮着同一颗
  /// 胶囊(原型如此),但它们不属于任何一个 tab,那时谁都不高亮。
  final AppTab? activeTab;

  final ValueChanged<AppTab> onTabSelected;

  /// 沉浸页(播放 / 歌词)不显示坞 —— 那一屏整屏都是播放控制。
  final bool showDock;

  /// 列表需要留出的底部空间。坞 62 + 间距 8 + 标签栏 66 + 四周留白。
  static const bottomInset = 150.0;

  /// 带胶囊的页面里,列表底部该留多少(已含系统指示条)。
  static double listInset(BuildContext context) =>
      bottomInset + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    // 不看坞的时候**不去问播放层** —— 短路的写法让这一片在「没有播放层」
    // 的树里也能立起来(测试里就是这么用的)。
    final docked =
        showDock && context.watch<PlaybackController?>()?.state.song != null;

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
        child: NordicGlass(
          panel: NordicGlassPanel.nav,
          // 一行时是胶囊,两行时取大圆角 —— 一整块两行的东西做成胶囊,
          // 上下缘会鼓得像药丸。
          borderRadius: BorderRadius.circular(
            docked ? NordicRadius.xl : NordicRadius.full,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (docked) const _PlayerDock(),
              if (docked) const _TrayProgress(),
              _TabBar(active: activeTab, onSelected: onTabSelected),
            ],
          ),
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
    // 必须 watch **这一份**:它是 ChangeNotifierProvider,播放状态一变就重建。
    // (早先这里查过一份可空的注册,那份是普通 Provider,不监听通知 ——
    //  坞于是永远停在「还没开始播」的样子,放起歌来也不出现。)
    final playback = context.watch<PlaybackController>();
    final song = playback.state.song;
    // 还没放过任何东西时不占位 —— 空坞是一块没有意义的玻璃。
    if (song == null) return const SizedBox.shrink();

    final appState = context.watch<AppState>();

    final playing = playback.state.playing;

    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/player'),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 60,
        child: Padding(
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

/// 托盘中间那条细线 —— **同时就是进度**。
///
/// 原先进度线贴在坞底:既要绕开圆角,又压在内容上。现在它就是播放坞与标签栏
/// 之间的那条分隔线,从左往右长 —— 整块托盘于是自己说明「正在放」。
class _TrayProgress extends StatelessWidget {
  const _TrayProgress();

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s4),
      child: ValueListenableBuilder<Duration>(
        valueListenable: playback.position,
        builder: (context, position, _) => ProgressLine(
          progress:
              playbackProgress(position, playback.state.duration) / 100,
          height: 2,
        ),
      ),
    );
  }
}

/// 标签栏 —— `.tabbar`。选中项做成一颗凹进去的玻璃胶囊:记住的是位置,不是颜色。
class _TabBar extends StatelessWidget {
  const _TabBar({required this.active, required this.onSelected});

  final AppTab? active;
  final ValueChanged<AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent.accent;

    return SizedBox(
      height: 62,
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
    );
  }
}

/// 沉浸页上那颗胶囊要让主壳切 tab —— 用一句全局的「请切到这个 tab」。
///
/// 专辑 / 艺人 / 服务器 / 歌单这几屏是**独立路由**(见 [AppRoutes]),不属于
/// 任何一个 tab,却各自浮着一颗同样的胶囊。点它得先退回主壳、再切 tab;
/// 为此把回调从主壳一路传进这些页面的每一层并不划算,一个 notifier 说完。
final ValueNotifier<AppTab?> pendingTab = ValueNotifier(null);

/// 在哪一屏点了胶囊上的哪个 tab。
void openTab(BuildContext context, AppTab tab) {
  pendingTab.value = tab;
  // 回到主壳。它是根路由,一直活着,所以不必等它重建再切 —— 见 shell.dart
  // 里对 pendingTab 的订阅。
  Navigator.of(context).popUntil((route) => route.isFirst);
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