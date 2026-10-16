import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/subsonic_payload.dart';
import '../../data/subsonic_repository.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../shell/bottom_stack.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import '../widgets/states.dart';
import 'sort_sheet.dart';

/// 音乐库 —— 四个分栏:专辑 / 艺人 / 歌曲 / 歌单。
enum LibraryTab {
  albums('专辑'),
  artists('艺人'),
  songs('歌曲'),
  playlists('歌单');

  const LibraryTab(this.label);

  final String label;
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryTab _tab = LibraryTab.albums;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final playable = context.watch<PlaybackController>();
    final currentSongId = playable.state.song?.id;

    return Scaffold(
      backgroundColor: context.nordic.bg,
      body: Stack(
        children: [
          Column(
            children: [
              NordicAppBar(
                title: '音乐库',
                subtitle: state.server == null
                    ? '还没有连接服务器'
                    : '${state.server!.name} · ${state.library.totalSongs} 首',
                actions: [
                  IconButtonRound(
                    icon: Icons.search,
                    quiet: true,
                    onPressed: () => AppRoutes.openSearchTab(context),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s4),
                child: SegmentedControl<LibraryTab>(
                  options: LibraryTab.values,
                  value: _tab,
                  labelOf: (t) => t.label,
                  onChanged: (t) => setState(() => _tab = t),
                ),
              ),
              Expanded(child: _body(state, currentSongId, playable)),
            ],
          ),
          // 底部留白:内容要能滚到坞的上方,而不是被压在玻璃下面。
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(height: BottomStack.bottomInset),
          ),
        ],
      ),
    );
  }

  Widget _body(AppState state, String? currentSongId, PlaybackController playable) {
    if (!state.hasServer) {
      return EmptyState(
        title: '还没有连接服务器',
        detail: '到设置里填上你的音乐服务器地址,曲库会显示在这里。',
        topPadding: 80,
      );
    }

    // 加载 / 出错时**不显示空态** —— 那是两件不同的事。
    switch (state.phase) {
      case LoadPhase.loading:
        return const LoadingState();
      case LoadPhase.failed:
        // 断网时**已经下到本机的那批还在**:指一句去哪找,不然用户会以为
        // 离线就什么都用不了。(库里没有下过东西时不提这一句 —— 空跑一趟更烦。)
        final offlineReady =
            state.errorIsNetwork && state.downloads.any((j) => j.isDone);
        return ErrorState(
          message: state.error ?? '读取失败',
          isAuthFailure: state.errorIsAuth,
          onRetry: () => state.loadLibrary(),
          onOpenSettings: () => AppRoutes.openServers(context),
          hint: offlineReady ? '本机已下载的音乐还在,去「下载管理」就能离线听。' : null,
          onHintTap:
              offlineReady ? () => AppRoutes.openDownloads(context) : null,
        );
      case LoadPhase.idle:
      case LoadPhase.ready:
        break;
    }

    final library = state.library;
    if (library.isEmpty) {
      return EmptyState(
        title: '这个库里还没有内容',
        detail: '如果服务器上确实有歌,到设置里重新扫描一次曲库,或下拉刷新。',
        topPadding: 80,
      );
    }

    // 刷新失败但手上有缓存时:留一条话在顶上,内容照旧。
    final stale = state.refreshError != null;

    return Column(
      children: [
        if (stale)
          _StaleBanner(
            message: state.refreshError!,
            savedAt: state.libraryCachedAt,
            onRetry: () => state.loadLibrary(silent: true),
          ),
        Expanded(
          child: RefreshIndicator(
            color: context.accentSafe,
            backgroundColor: context.nordic.glass3,
            onRefresh: () => state.loadLibrary(silent: true),
            child: switch (_tab) {
        LibraryTab.albums => _AlbumsTab(
            library: library,
            currentSongId: currentSongId,
            state: state,
            playable: playable,
          ),
        LibraryTab.artists => _ArtistsTab(library: library),
        LibraryTab.songs => _SongsTab(
            library: library,
            currentSongId: currentSongId,
            state: state,
            playable: playable,
          ),
              LibraryTab.playlists => _PlaylistsTab(library: library),
            },
          ),
        ),
      ],
    );
  }
}

/// 「显示的是本机缓存」那条 —— 刷新失败但手上有内容时出现。
///
/// 有东西看总比一片空白强,所以这时**不切成错误态**;但也不能装作是最新的,
/// 于是留这一条,并带一个「重试」。
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({
    required this.message,
    required this.savedAt,
    required this.onRetry,
  });

  final String message;
  final DateTime? savedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final when = savedAt == null ? null : '上次同步 ${_clock(savedAt!)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: t.fill1,
          borderRadius: BorderRadius.circular(NordicRadius.md),
          border: Border.all(color: t.line),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 16, color: t.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [?when, message].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: t.fg3, height: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            NordicChip(
              label: '重试',
              icon: Icons.refresh,
              height: 30,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }

  /// `10 月 16 日 17:20` —— 只到分钟:再细没有意义,这里只想说「是哪时候的」。
  static String _clock(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.month} 月 ${local.day} 日 ${two(local.hour)}:${two(local.minute)}';
  }
}

/// 专辑分栏:「继续收听」英雄卡 + 全部专辑网格 + 最近添加货架。
class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab({
    required this.library,
    required this.currentSongId,
    required this.state,
    required this.playable,
  });

  final LibrarySnapshot library;
  final String? currentSongId;
  final AppState state;
  final PlaybackController playable;

  @override
  Widget build(BuildContext context) {
    final song = playable.state.song;
    final albumOfSong = song == null
        ? null
        : library.albums.where((a) => a.id == song.albumId).firstOrNull;

    // 整栏走 sliver:网格必须**真的懒**(见 [_AlbumGridSliver])。
    return CustomScrollView(
      slivers: [
        if (song != null)
          SliverToBoxAdapter(
            child: _ContinueCard(
              song: song,
              album: albumOfSong,
              playable: playable,
            ),
          ),
        SliverToBoxAdapter(
          child: SectionHeader(
            title: '全部专辑',
            count: '${library.albums.length} 张',
            trailing: SortButton(
              label: '按${state.albumSort.label}',
              busy: state.sortingAlbums,
              onTap: () => showSortSheet(context, albums: true),
            ),
          ),
        ),
        _AlbumGridSliver(albums: library.albums, state: state),
        if (library.recentlyAdded.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SectionHeader(title: '最近添加', count: null),
          ),
          SliverToBoxAdapter(
            child: _AlbumRail(albums: library.recentlyAdded, state: state),
          ),
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: BottomStack.listInset(context)),
        ),
      ],
    );
  }
}

/// 「继续收听」英雄卡 —— `.hero-card`。整宽的当前播放卡。
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.song, required this.album, required this.playable});

  final Song song;
  final Album? album;
  final PlaybackController playable;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final playing = playable.state.playing;
    final accent = context.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s2),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => AppRoutes.openPlayer(context),
            child: Container(
              padding: const EdgeInsets.all(NordicSpace.s4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NordicRadius.xl),
                border: Border.all(color: t.line),
                boxShadow: [
                  BoxShadow(
                    color: t.depth,
                    blurRadius: 44,
                    offset: const Offset(0, 22),
                    spreadRadius: -24,
                  ),
                ],
                gradient: LinearGradient(
                  begin: const Alignment(-1, -1.2),
                  end: const Alignment(0.6, 1),
                  colors: [t.bg3, t.bg1],
                ),
              ),
              child: Stack(
                children: [
                  // 左上角一团强调色 —— 整张卡的气质来自这里。
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(NordicRadius.xl),
                          gradient: RadialGradient(
                            center: const Alignment(-1, -1),
                            radius: 1.3,
                            colors: [
                              accent.accent.withValues(alpha: 0.34 * t.glow),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Cover(
                        coverArtId: album?.coverArtId ?? song.coverArtId,
                        seed: song.albumId,
                        uri: _cover(context, album?.coverArtId ?? song.coverArtId),
                        size: 92,
                        radius: 20,
                      ),
                      const SizedBox(width: NordicSpace.s4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              playing ? '继续收听' : '已暂停',
                              style: TextStyle(
                                fontSize: NordicType.xs,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                                color: Color.lerp(
                                  accent.accent,
                                  t.fg,
                                  0.18,
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              album?.name ?? song.album,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            // 位置单独订阅:英雄卡是音乐库首页的一部分,
                            // 不该因为播放位置而把整页货架拉进重建。
                            ValueListenableBuilder<Duration>(
                              valueListenable: playable.position,
                              builder: (context, position, _) => Text(
                                '${song.artist} · 播到 '
                                '${formatDuration(position)} / '
                                '${formatDuration(playable.state.duration)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: t.fg2),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: playable.toggle,
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: accent.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accent.accent.withValues(alpha: 0.8),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                                spreadRadius: -8,
                              ),
                            ],
                          ),
                          child: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
                            size: 24,
                            color: t.bg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: NordicSpace.s3),
          ValueListenableBuilder<Duration>(
            valueListenable: playable.position,
            builder: (context, position, _) => ProgressLine(
              progress:
                  playbackProgress(position, playable.state.duration) / 100,
            ),
          ),
          const SizedBox(height: NordicSpace.s2),
        ],
      ),
    );
  }

  Uri? _cover(BuildContext context, String? artId) {
    final repo = context.read<AppState>().repository;
    if (repo == null || artId == null) return null;
    try {
      return repo.coverUri(artId, size: 256);
    } on SubsonicException {
      return null;
    }
  }
}

/// 专辑网格 —— `.grid-covers`,两列大封面。
///
/// **它是个 sliver**,不是嵌在 ListView 里的 `GridView(shrinkWrap: true)`:
/// 后者为了量自己的高度会把**每一张专辑**都建出来 —— 库里 400 多张就是 400 多个
/// 卡片、400 多次封面解码,全压在进音乐库的那一帧上。sliver 只建视口附近那几格。
class _AlbumGridSliver extends StatelessWidget {
  const _AlbumGridSliver({required this.albums, required this.state});

  final List<Album> albums;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s3),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: NordicSpace.s4,
          mainAxisSpacing: NordicSpace.s5,
          childAspectRatio: 0.78,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => AlbumTile(
            album: albums[index],
            repo: state.repository,
          ),
          childCount: albums.length,
        ),
      ),
    );
  }
}

/// 单张专辑 —— 封面 + 名称 + 艺人年份。音乐库与搜索页共用。
class AlbumTile extends StatelessWidget {
  const AlbumTile({super.key, required this.album, required this.repo});

  final Album album;

  /// 封面地址由它拼。可为空 —— 还没配服务器时界面照样能画(走渐变兜底)。
  final SubsonicRepository? repo;

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
                uri: _uri(repo, album.coverArtId),
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

  static Uri? _uri(SubsonicRepository? repo, String? coverArtId) {
    if (repo == null || coverArtId == null) return null;
    try {
      return repo.coverUri(coverArtId, size: 512);
    } on SubsonicException {
      return null;
    }
  }
}

/// 横滑货架 —— `.rail`。
class _AlbumRail extends StatelessWidget {
  const _AlbumRail({required this.albums, required this.state});

  final List<Album> albums;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return SizedBox(
      // 142 的封面 + 两行文字,按内容算高 —— 写死会在字体放大时溢出。
      height: shelfHeight(context, artwork: 142),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s4),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: NordicSpace.s4),
        itemBuilder: (context, index) {
          final album = albums[index];
          return GestureDetector(
            onTap: () => AppRoutes.openAlbum(context, album.id),
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
                      uri: AlbumTile._uri(state.repository, album.coverArtId),
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

/// 艺人分栏:常听横滑 + 全部艺人列表。
class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab({required this.library});

  final LibrarySnapshot library;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final top = library.topArtists;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SectionHeader(
            title: '常听艺人',
            count: '${library.artists.length} 位',
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            // 152 的方块 + 两行文字,按内容算高。
            height: shelfHeight(context, artwork: 152),
            child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s4),
            itemCount: top.length,
            separatorBuilder: (_, _) => const SizedBox(width: NordicSpace.s4),
            itemBuilder: (context, index) {
              final artist = top[index];
              return GestureDetector(
                onTap: () => AppRoutes.openArtist(context, artist.id),
                child: SizedBox(
                  width: 152,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ArtistPlate(artist: artist, size: 152, radius: 26),
                      const SizedBox(height: 11),
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${artist.albumCount} 张专辑',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: t.fg3),
                      ),
                    ],
                  ),
                ),
              );
            },
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionHeader(title: '全部艺人')),
        // 一屏一屏地建:300 多位艺人一次铺完,进这一栏就要多等好几帧。
        SliverList.builder(
          itemCount: library.artists.length,
          itemBuilder: (context, index) {
            final artist = library.artists[index];
            return NordicRow(
              leading: ArtistPlate(artist: artist, size: 52, circular: true),
              title: artist.name,
              subtitle: '${artist.albumCount} 张专辑',
              trailing: Icon(Icons.chevron_right, size: 18, color: t.fg3),
              onTap: () => AppRoutes.openArtist(context, artist.id),
            );
          },
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: BottomStack.listInset(context)),
        ),
      ],
    );
  }
}

/// 歌曲分栏:全部歌曲。
class _SongsTab extends StatelessWidget {
  const _SongsTab({
    required this.library,
    required this.currentSongId,
    required this.state,
    required this.playable,
  });

  final LibrarySnapshot library;
  final String? currentSongId;
  final AppState state;
  final PlaybackController playable;

  @override
  Widget build(BuildContext context) {
    final repo = state.repository;
    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: BottomStack.listInset(context),
      ),
      itemCount: library.songs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return SectionHeader(
            title: '全部歌曲',
            count: '${library.songs.length} 首',
            trailing: SortButton(
              label: '按${state.songSort.label}',
              onTap: () => showSortSheet(context, albums: false),
            ),
            padding: const EdgeInsets.fromLTRB(
              NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s3),
          );
        }
        final song = library.songs[index - 1];
        return SongRow(
          song: song,
          coverUri: (id) => repo!.coverUri(id, size: 128),
          playing: song.id == currentSongId && playable.state.playing,
          onTap: () => playable.playAll(library.songs, index: index - 1),
        );
      },
    );
  }
}

/// 歌单分栏:我的歌单 + 新建入口。
class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab({required this.library});

  final LibrarySnapshot library;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = context.watch<AppState>();

    // 歌单一般不多,但口径与其它两栏统一:一屏一屏地建。
    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: BottomStack.listInset(context),
      ),
      itemCount: library.playlists.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return SectionHeader(
            title: '我的歌单',
            count: '${library.playlists.length} 个',
          );
        }
        if (index == library.playlists.length + 1) {
          // 空库时也要能建歌单 —— 一个空列表配一个入口,比只显示「暂无」
          // 有用得多。
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              NordicSpace.s5, NordicSpace.s5, NordicSpace.s5, NordicSpace.s4),
            child: GhostButton(
              label: '新建歌单',
              icon: Icons.add,
              onPressed: () => AppRoutes.openNewPlaylist(context),
            ),
          );
        }

        final playlist = library.playlists[index - 1];
        return NordicRow(
            height: 72,
            leading: Cover(
              coverArtId: playlist.coverArtId,
              seed: playlist.id,
              uri: _uri(state, playlist.coverArtId),
              size: 56,
              radius: 16,
              showShadow: false,
            ),
            title: playlist.name,
            subtitle: [
              '${playlist.songCount} 首',
              if (playlist.description != null) playlist.description!,
            ].join(' · '),
            trailing: Icon(Icons.chevron_right, size: 18, color: t.fg3),
            onTap: () => AppRoutes.openPlaylist(context, playlist.id),
          );
      },
    );
  }

  Uri? _uri(AppState state, String? coverArtId) {
    final repo = state.repository;
    if (repo == null || coverArtId == null) return null;
    try {
      return repo.coverUri(coverArtId, size: 256);
    } on SubsonicException {
      return null;
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}