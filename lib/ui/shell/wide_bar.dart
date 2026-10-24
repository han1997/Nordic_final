import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/music_source.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../adaptive/window.dart';
import '../routes.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';

/// 宽屏(>= 840)的底部播放横条 —— 手机形态那颗托盘在这里只剩一行玻璃:
/// 封面 + 标题/艺人 + 行内进度 + 三键(上一首 / 播放暂停 / 下一首)。
/// 点整条进播放页(`AppRoutes.openPlayer`,与窄屏坞同一件事)。
///
/// **订阅面与窄屏坞(_PlayerDock / _TrayProgress)逐条相同**:只订
/// 「当前这一首 + 是否在播」的二元组与仓库单件;进度分开走 position 通道。
/// 别的播放通知(时长上报、循环 / 随机翻转)都不该把这块玻璃重建一遍 ——
/// 坞是每个带常驻区的屏都在的常驻件,这条口径在 docs/performance.md 里。
/// 「还没放过任何东西」时不出现(不留一块没有意义的空玻璃)。
class WidePlaybackBar extends StatelessWidget {
  const WidePlaybackBar({super.key});

  @override
  Widget build(BuildContext context) {
    final playback = context.read<PlaybackController>();
    final (song, playing) = context
        .select<PlaybackController, (Song?, bool)>(
      (p) => (p.state.song, p.state.playing),
    );
    if (song == null) return const SizedBox.shrink();

    final t = context.nordic;
    // 坞只用到 AppState 里的一件事:**仓库**(拼封面地址用)。select 那一件,
    // 而不是 watch 整个 AppState —— 下载进度与缓存淘汰与这一条无关。
    final repo = context.select<AppState, MusicSource?>((s) => s.repository);
    // 时长只有换歌才变;位置每秒跳好几次 —— 分开订(与托盘里同一条口径)。
    final duration = context.select<PlaybackController, Duration>(
      (p) => p.state.duration,
    );
    final position = playback.position;

    return Positioned(
      left: NordicWindow.gutter,
      right: NordicWindow.railMargin,
      bottom: MediaQuery.paddingOf(context).bottom + NordicWindow.railMargin,
      child: RepaintBoundary(
        // 那行字与进度是会变的,而这块玻璃本身不变 —— 隔一层重绘边界,
        // 播放状态一变就只重画内容(与窄屏托盘同一处置)。
        child: NordicGlass(
          panel: NordicGlassPanel.nav,
          borderRadius: BorderRadius.circular(NordicRadius.xl),
          child: Pressable(
            // 整条按下去亮一层底色,与所有列表行同一套(`pressedDecoration`);
            // 跳转走 AppRoutes.openPlayer,路由名只留一处。
            onTap: () => AppRoutes.openPlayer(context),
            pressedDecoration: BoxDecoration(color: t.fill1),
            child: SizedBox(
              height: NordicWindow.barHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s3),
                child: Row(
                  // 宽屏这一档与手机同一条缝:12(原型 `.dock { gap: var(--s3) }`)。
                  spacing: NordicSpace.s3,
                  children: [
                    Cover(
                      coverArtId: song.coverArtId,
                      seed: song.albumId,
                      uri: albumCoverUri(repo, song.coverArtId, size: 128),
                      size: 48,
                      radius: 14,
                      showShadow: false,
                    ),
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
                    // 行内进度 —— 与托盘里那条分隔线同一份数据、同一套算法,
                    // 单独隔一层重绘边界(它每秒重画好几次)。
                    //
                    // 两侧各 24 = 坞的 gap 12 **加上** `.prog-inline` 自己的
                    // `margin: 0 var(--s3)` —— 原型那两件是叠着的,不是一层。
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NordicSpace.s3,
                        ),
                        child: RepaintBoundary(
                          child: ValueListenableBuilder<Duration>(
                            valueListenable: position,
                            builder: (context, position, _) => ProgressLine(
                              progress:
                                  playbackProgress(position, duration) / 100,
                              height: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButtonRound(
                      icon: Icons.skip_previous,
                      // 原型坞里三颗键:上一首 25、播放 / 暂停 25、下一首 23。
                      iconSize: 25,
                      onPressed: playback.previous,
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
          ),
        ),
      ),
    );
  }
}
