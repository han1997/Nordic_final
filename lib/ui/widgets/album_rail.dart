import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/subsonic_repository.dart';
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
  const AlbumRail({super.key, required this.albums, required this.repo});

  final List<Album> albums;

  /// 封面地址由它拼。可为空 —— 还没配服务器时走渐变兜底。
  final SubsonicRepository? repo;

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
                    tag: 'cover-rail-${album.id}',
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
