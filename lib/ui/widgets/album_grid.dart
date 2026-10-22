import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/music_source.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../adaptive/window.dart';
import '../routes.dart';
import 'cover.dart';

/// 专辑网格 —— `.grid-covers`(音乐库「专辑」栏与搜索页共用一份,
/// 原先两处各写一遍)。
///
/// 手机 / 平板竖屏**恒 2 列**(与历史形态一致);宽屏(>= 840)按
/// [NordicWindow.gridColumns] 放开列数。列数只在 expanded 分支算:
/// 单靠那条除式,默认测试视口(800 宽)会给出 3 列,而那一档的判据
/// 全建在两列网格的骨架上(见 docs/performance.md)。
///
/// **它是个 sliver**:别改成嵌在 ListView 里的 `GridView(shrinkWrap: true)` ——
/// 后者为了量自己的高度会把每一张专辑都建出来(库里 400 多张 = 进库那一帧
/// 建 400 多个卡片、解 400 多张封面)。
class AlbumGridSliver extends StatelessWidget {
  const AlbumGridSliver({super.key, required this.albums, required this.repo});

  final List<Album> albums;
  final MusicSource? repo;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s3),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          // 可用宽取**真实约束**(已扣掉左右 padding 与竖栏让位),
          // 与原型 app.js 的 gridColsOf 同一条公式、同一份输入。
          final columns = context.isExpanded
              ? NordicWindow.gridColumns(constraints.crossAxisExtent)
              : 2;
          final tileWidth = (constraints.crossAxisExtent -
                  NordicSpace.s4 * (columns - 1)) /
              columns;
          return SliverGrid(
            // **单格高 = 封面(方形)+ 标题实测高**,而不是定死的 childAspectRatio:
            // 旧的 0.78 在两列手机宽下封面是 167×159.5(比正方形扁 4%),
            // 网格拉大后这个偏差会变成肉眼可见的扁。标题高按字号算,字体放大跟着走。
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: NordicSpace.s4,
              mainAxisSpacing: NordicSpace.s5,
              mainAxisExtent: tileWidth + _captionHeight(context),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => AlbumTile(album: albums[index], repo: repo),
              childCount: albums.length,
            ),
          );
        },
      ),
    );
  }

  /// 封面下面那两行字占的高度(10 间距 + 名字行 + 2 + 副标题行)。
  /// 与 `shelfHeight`(rows.dart)同一个按字号算的路子,每行留 1px 余量 ——
  /// 字体度量取整后可能比 fontSize×1.45 略高,不留就会常挂着溢出警示带。
  static double _captionHeight(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final nameLine = scaler.scale(textTheme.bodyMedium?.fontSize ?? 15) * 1.45 + 1;
    final metaLine = scaler.scale(textTheme.bodySmall?.fontSize ?? 13) * 1.45 + 1;
    return 10 + nameLine + 2 + metaLine;
  }
}

/// 单张专辑 —— 封面 + 名称 + 艺人年份。音乐库与搜索页共用。
class AlbumTile extends StatelessWidget {
  const AlbumTile({super.key, required this.album, required this.repo});

  final Album album;

  /// 封面地址由它拼。可为空 —— 还没配服务器时界面照样能画(走渐变兜底)。
  final MusicSource? repo;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return GestureDetector(
      onTap: () => AppRoutes.openAlbum(context, album.id),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Hero(
              // 共享元素过渡:封面从网格飞到详情页(原型用 View Transition,
              // 这里用 Hero —— 同一件事的平台原生做法)。
              tag: 'cover-${album.id}',
              child: Cover(
                coverArtId: album.coverArtId,
                seed: album.id,
                uri: albumCoverUri(repo, album.coverArtId),
                width: double.infinity,
                radius: 22,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            album.year == null ? album.artist : '${album.artist} · ${album.year}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.fg3),
          ),
        ],
      ),
    );
  }
}
