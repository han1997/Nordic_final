import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import 'cover.dart';
import 'components.dart';

/// 通用列表行 —— `.row`。歌曲 / 艺人 / 歌单 / 设置项共用一份骨架。
///
/// 高度可调:歌曲行 64,歌单行 72,设置行 64。
class NordicRow extends StatelessWidget {
  const NordicRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.height = 64,
    this.titleColor,
    this.padding = const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double height;

  /// 覆盖标题色 —— 「正在播放」那一行用强调色。
  final Color? titleColor;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Pressable(
      onTap: onTap,
      // 整行按下去的反馈取原型的 `.row:hover{background:var(--fill-1)}` ——
      // 手机上按 = 悬停,缩放在 64px 高的整行上会晃眼。
      pressedDecoration: BoxDecoration(color: t.fill1),
      child: Container(
        // `minHeight` 而不是写死高度:系统字号拉大时行要能跟着长高,
        // 写死 64 的话文字会被裁掉半截(无障碍里这是最常见的设置)。
        constraints: BoxConstraints(minHeight: height),
        padding: padding,
        color: Colors.transparent,
        child: Row(
          children: [
            leading,
            const SizedBox(width: NordicSpace.s3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: titleColor ?? t.fg,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.fg3),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: NordicSpace.s2),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 歌曲行 —— 音乐库里的一首歌。字形轨道上带播放中的跳动条。
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.song,
    required this.coverUri,
    this.playing = false,
    this.onTap,
    this.trailing,
  });

  final Song song;
  final Uri? Function(String coverArtId) coverUri;
  final bool playing;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return NordicRow(
      onTap: onTap,
      leading: Cover(
        coverArtId: song.coverArtId,
        seed: song.albumId,
        uri: song.hasCover ? coverUri(song.coverArtId!) : null,
        size: 52,
        radius: 14,
        showShadow: false,
      ),
      title: song.title,
      titleColor: playing ? context.accentSafe : null,
      subtitle: '${song.artist} · ${song.album}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playing) ...[
            PlayingBars(size: 15),
            const SizedBox(width: NordicSpace.s3),
          ],
          trailing ??
              Text(
                formatDuration(song.duration),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: t.fg3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
        ],
      ),
    );
  }
}

/// 曲目行 —— 专辑页与艺人页共用。
///
/// [trackNumber] 为 null 时不排曲序(艺人页的「热门」按播放量排,序数无意义);
/// 播放中的那一行用跳动竖条**顶掉**曲序,而不是两个都留着 ——
/// 两处宽度保持一致,行不会随播放状态左右挪。
class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.song,
    this.trackNumber,
    this.playing = false,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final Song song;
  final int? trackNumber;
  final bool playing;

  /// 覆盖第二行文案(艺人页显示「专辑 · 格式」)。
  final String? subtitle;

  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return NordicRow(
      onTap: onTap,
      leading: SizedBox(
        width: 24,
        child: playing
            ? Align(
                alignment: Alignment.centerLeft,
                child: PlayingBars(size: 15, color: context.accentSafe),
              )
            : Text(
                '${trackNumber ?? ''}',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: t.fg4,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
      ),
      title: song.title,
      titleColor: playing ? context.accentSafe : null,
      subtitle: subtitle ?? song.formatLine,
      trailing: trailing ??
          Text(
            formatDuration(song.duration),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: t.fg3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
    );
  }
}

/// 秒 → `m:ss`。专辑与队列到处在用,收一处免得各写一遍格式不一致。
String formatDuration(Duration duration) {
  final total = duration.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// 字节 → `138 MB` / `1.4 GB`。下载管理与歌曲缓存两处都用它。
///
/// 不到 1 GB 就别硬撑「0.1 GB」—— 该显示 MB 的时候显示 MB,
/// 而小数位在 MB 这一档没有意义,直接取整。
String formatBytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
  return '${mb.round()} MB';
}

/// 横滑货架的高度 —— 按内容算,不写死。
///
/// 写死过 214 / 220 两处,结果中文名换行或系统字体调大时就会溢出
/// (那块黄黑相间的警示带)。货架里放的是固定尺寸的封面 + 两行文字,
/// 高度本来就能算准:
///   [artwork] 封面边长
///   + 10 封面与名称的间距 + 17 名称行 + 3 + 17 副标题行
///   + s2/s4 上下内边距
///
/// 文案行高用当前主题字号推,因此字体缩放变化时这里也跟着变。
double shelfHeight(BuildContext context, {required double artwork}) {
  final textTheme = Theme.of(context).textTheme;
  // +1:字体度量取整后每行可能比 fontSize×1.45 略高一点,
  // 不留这点余量就会常年挂着 0.4px 的溢出警示带。
  final nameLine = (textTheme.bodyMedium?.fontSize ?? 15) * 1.45 + 1;
  final metaLine = (textTheme.bodySmall?.fontSize ?? 13) * 1.45 + 1;
  return artwork +
      10 +
      nameLine +
      3 +
      metaLine +
      NordicSpace.s2 +
      NordicSpace.s4;
}

/// 相对时长 —— 「还有约 12:34」。
String formatRemaining(Duration duration) {
  if (duration <= Duration.zero) return '0:00';
  return formatDuration(duration);
}