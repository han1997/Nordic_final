import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/music_source.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import 'components.dart';
import 'cover.dart';
import 'rows.dart';

/// 横滑货架 —— `.rail`。首页与音乐库共用一份。
///
/// 高度按内容算([shelfHeight]),不写死:写死过 214 / 220 两处,
/// 中文名换行或系统字号调大时就会溢出。封面固定 142,拖动只有横向。
class AlbumRail extends StatelessWidget {
  const AlbumRail({
    super.key,
    required this.albums,
    required this.repo,
    this.heroPrefix = 'cover-rail',
  });

  final List<Album> albums;

  /// 封面地址由它拼。可为空 —— 还没配服务器时走渐变兜底。
  final MusicSource? repo;

  /// 共享元素 tag 的前缀 —— **同一条路由上摆两条货架时,两条必须是不同的**。
  ///
  /// 框架按 tag 在整条来源路由里找起点(`heroes.dart` 的 `_allHeroesFor`),
  /// 同一个 tag 出现两次会直接断言失败。而首页上「最近播放」与「最常播放」
  /// 常有一张专辑同时在,写死同一个前缀就是「从首页点进任何一页都可能崩」。
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return SizedBox(
      height: shelfHeight(context, artwork: 142),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s4),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: NordicSpace.s4),
        itemBuilder: (context, index) {
          final album = albums[index];
          return Pressable(
            onTap: () => AppRoutes.openAlbum(context, album.id),
            scale: 0.97,
            child: SizedBox(
              width: 142,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: '$heroPrefix-${album.id}',
                    child: Cover(
                      coverArtId: album.coverArtId,
                      seed: album.id,
                      uri: albumCoverUri(repo, album.coverArtId),
                      size: 142,
                      radius: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.artist,
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
          );
        },
      ),
    );
  }
}
