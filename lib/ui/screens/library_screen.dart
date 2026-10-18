import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/server_config.dart';
import '../../data/sorting.dart';
import '../../data/music_source.dart';
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

/// 音乐库这一屏真正订阅的那几件 `AppState` 数据。
///
/// **别换回 `watch<AppState>()`。** 下载进度最多每秒播报四次、缓存淘汰也会播报,
/// 而它们一件都不在这张表里;记录是按**值**比较的,于是那些通知到不了这一屏 ——
/// 四百多张专辑的网格不会跟着下载进度重建(它原先就因为这一条被注释点名过)。
/// 分栏各自要的那几件(排序口径、仓库、翻页状态)由分栏自己 select,不进这张表:
/// 换歌曲排序不该把专辑网格也重建一遍。
typedef _LibraryView = ({
  bool hasServer,
  ServerConfig? server,
  LibrarySnapshot library,
  LoadPhase phase,
  String? error,
  bool errorIsAuth,
  bool errorIsNetwork,
  String? refreshError,
  DateTime? cachedAt,
  /// 同首页:断网失败时那句「本机已下载的还在」要不要给。
  bool offlineReady,
});

class _LibraryScreenState extends State<LibraryScreen> {
  /// 默认落在**歌曲**:打开音乐库多半是想找一首具体的歌,
  /// 而专辑网格要先认封面、再点进去才看到曲目(真机反馈过这一步多余)。
  LibraryTab _tab = LibraryTab.songs;

  /// 派生值按**快照**缓存。
  ///
  /// 「总首数」未取全时要 fold 四百多张专辑,「常听艺人」每次要排三百多位艺人 ——
  /// 而这一屏会因为切歌、下载进度(最多每秒四次)这些事反复重建。
  /// 它们只跟库本身有关,快照没换就不必重算。快照是 `const` 的
  /// (见 models.dart 的 LibrarySnapshot),所以在它身上挂不了缓存,只能挂这儿。
  LibrarySnapshot? _derivedFor;
  int _totalSongs = 0;
  List<Artist> _topArtists = const [];

  void _deriveIfNeeded(LibrarySnapshot library) {
    if (identical(library, _derivedFor)) return;
    _derivedFor = library;
    _totalSongs = library.totalSongs;
    _topArtists = library.topArtists;
  }

  @override
  Widget build(BuildContext context) {
    final view = context.select<AppState, _LibraryView>((s) => (
          hasServer: s.hasServer,
          server: s.server,
          library: s.library,
          phase: s.phase,
          error: s.error,
          errorIsAuth: s.errorIsAuth,
          errorIsNetwork: s.errorIsNetwork,
          refreshError: s.refreshError,
          cachedAt: s.libraryCachedAt,
          offlineReady: s.downloads.any((j) => j.isDone),
        ));
    // 方法用这一份:取值函数不参与重建判定。
    final state = context.read<AppState>();
    final playable = context.watch<PlaybackController>();
    final currentSongId = playable.state.song?.id;
    _deriveIfNeeded(view.library);

    return Scaffold(
      backgroundColor: context.nordic.bg,
      body: Stack(
        children: [
          Column(
            children: [
              NordicAppBar(
                title: '音乐库',
                subtitle: view.server == null
                    ? '还没有连接服务器'
                    : '${view.server!.name} · $_totalSongs 首',
                actions: [
                  IconButtonRound(
                    icon: Icons.shuffle,
                    quiet: true,
                    // 随机播放整个库 —— 与专辑页「随机播放这张专辑」、艺人页 /
                    // 歌单页那颗随机键同一套做法:打乱后整队装载,于是队列本身
                    // 就是随机顺序,队列面板不必特殊处理。
                    onPressed: () => _shuffleAll(playable),
                  ),
                  IconButtonRound(
                    icon: Icons.search,
                    quiet: true,
                    onPressed: () => AppRoutes.openSearch(context),
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
              Expanded(child: _body(state, view, currentSongId, playable)),
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

  Widget _body(
    AppState state,
    _LibraryView view,
    String? currentSongId,
    PlaybackController playable,
  ) {
    if (!view.hasServer) {
      return EmptyState(
        title: '还没有连接服务器',
        detail: '填上服务器地址与账号，曲库会显示在这里。',
        topPadding: 80,
        // 与首页同一颗入口(见那儿为什么加)。
        action: SizedBox(
          width: 200,
          child: PrimaryButton(
            label: '连接服务器',
            icon: Icons.dns_outlined,
            onPressed: () => AppRoutes.openServers(context, form: true),
          ),
        ),
      );
    }

    // 加载 / 出错时**不显示空态** —— 那是两件不同的事。
    switch (view.phase) {
      case LoadPhase.loading:
        return const LoadingState();
      case LoadPhase.failed:
        // 断网时**已经下到本机的那批还在**:指一句去哪找,不然用户会以为
        // 离线就什么都用不了。(库里没有下过东西时不提这一句 —— 空跑一趟更烦。)
        final offlineReady = view.errorIsNetwork && view.offlineReady;
        return ErrorState(
          message: view.error ?? '读取失败',
          isAuthFailure: view.errorIsAuth,
          onRetry: () => state.loadLibrary(),
          onOpenSettings: () => AppRoutes.openServers(context),
          hint: offlineReady ? '本机已下载的音乐还在，去「下载管理」就能离线听。' : null,
          onHintTap:
              offlineReady ? () => AppRoutes.openDownloads(context) : null,
        );
      case LoadPhase.idle:
      case LoadPhase.ready:
        break;
    }

    final library = view.library;
    if (library.isEmpty) {
      return EmptyState(
        title: '这个库里还没有内容',
        detail: '如果服务器上确实有歌，到设置里重新扫描一次曲库，或下拉刷新。',
        topPadding: 80,
      );
    }

    // 刷新失败但手上有缓存时:留一条话在顶上,内容照旧。
    final stale = view.refreshError != null;

    return Column(
      children: [
        if (stale)
          StaleBanner(
            message: view.refreshError!,
            savedAt: view.cachedAt,
            onRetry: () => state.loadLibrary(silent: true),
          ),
        Expanded(
          child: RefreshIndicator(
            color: context.accentSafe,
            backgroundColor: context.nordic.glass3,
            onRefresh: () => state.loadLibrary(silent: true),
            child: switch (_tab) {
        LibraryTab.albums => _AlbumsTab(library: library),
        LibraryTab.artists => _ArtistsTab(library: library, top: _topArtists),
        LibraryTab.songs => _SongsTab(
            library: library,
            currentSongId: currentSongId,
            playable: playable,
          ),
              LibraryTab.playlists => _PlaylistsTab(library: library),
            },
          ),
        ),
      ],
    );
  }

  /// 随机播放整个库。逻辑收在 [shuffleLibrary] —— 首页空态那颗也走它。
  void _shuffleAll(PlaybackController playable) =>
      shuffleLibrary(context, playable);
}

/// 随机播放整个库。
///
/// 与专辑页 / 艺人页 / 歌单页那颗随机键同一套做法:打乱后**整队装载**,
/// 于是队列本身就是随机的,面板照原样列也不会说谎。
/// (播放页那颗随机键走的是另一条路 —— just_audio 的随机模式,那是「播着播着
/// 随机接下去」,两者不冲突。)
///
/// 抽成顶层函数是因为**音乐库与首页空态**都要用它:两处各写一遍
/// 「取歌、空则提示、打乱、装载」,迟早会有一处漏掉空判断。
void shuffleLibrary(BuildContext context, PlaybackController playable) {
  final songs = context.read<AppState>().library.songs;
  if (songs.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('曲库还没有加载出歌曲'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }
  playable.playAll([...songs]..shuffle(), index: 0);
}

/// 专辑分栏:「全部专辑」封面网格 + 排序。
///
/// 「继续收听」那张卡与「最近添加」货架**2026-10-17 起归首页**(原型同步改了,
/// 见 `prototype/app.js` 的 screenHome):音乐库回答「库里有什么」,首页回答
/// 「最近动过什么」—— 两屏各铺一份等于同一件事说两遍。
class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab({required this.library});

  final LibrarySnapshot library;

  @override
  Widget build(BuildContext context) {
    // 这一栏只用这三件 —— 排序口径、转圈状态、仓库(拼封面地址)。
    final (sort, busy, repo) = context.select<
        AppState, (AlbumSort, bool, MusicSource?)>(
      (s) => (s.albumSort, s.sortingAlbums, s.repository),
    );

    // 整栏走 sliver:网格必须**真的懒**(见 [_AlbumGridSliver])。
    // 下拉刷新挂在整屏外面(见本文件上方的 `RefreshIndicator`),
    // 而不够长的一栏**本来不可滚**,不发滚动通知 —— 那句「或下拉刷新」的空态
    // 正好出现在这种时候,所以四栏都要 [AlwaysScrollableScrollPhysics]。
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SectionHeader(
            title: '全部专辑',
            count: '${library.albums.length} 张',
            trailing: SortButton(
              label: '按${sort.label}',
              busy: busy,
              onTap: () => showSortSheet(context, albums: true),
            ),
          ),
        ),
        _AlbumGridSliver(albums: library.albums, repo: repo),
        SliverToBoxAdapter(
          child: SizedBox(height: BottomStack.listInset(context)),
        ),
      ],
    );
  }
}

/// 专辑网格 —— `.grid-covers`,两列大封面。
///
/// **它是个 sliver**,不是嵌在 ListView 里的 `GridView(shrinkWrap: true)`:
/// 后者为了量自己的高度会把**每一张专辑**都建出来 —— 库里 400 多张就是 400 多个
/// 卡片、400 多次封面解码,全压在进音乐库的那一帧上。sliver 只建视口附近那几格。
class _AlbumGridSliver extends StatelessWidget {
  const _AlbumGridSliver({required this.albums, required this.repo});

  final List<Album> albums;
  final MusicSource? repo;

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
            repo: repo,
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

  static Uri? _uri(MusicSource? repo, String? coverArtId) {
    if (repo == null || coverArtId == null) return null;
    try {
      return repo.coverUri(coverArtId, size: 512);
    } on MusicSourceException {
      return null;
    }
  }
}

/// 艺人分栏:常听横滑 + 全部艺人列表。
class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab({required this.library, required this.top});

  final LibrarySnapshot library;

  /// 「常听艺人」—— 由 `_LibraryScreenState` 按快照算好传进来,
  /// 不在这儿现排(见那边的 [_LibraryScreenState._deriveIfNeeded])。
  final List<Artist> top;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;

    return CustomScrollView(
      // 同 [_AlbumsTab]:不够长也要能下拉刷新。
      physics: const AlwaysScrollableScrollPhysics(),
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
/// 歌曲分栏:全部歌曲 + 排序。
///
/// **一次翻一页,滚到底自动接着取**(伺服器一次最多给 500 首,见
/// `AppState.loadMoreSongs`)。原先这里只铺启动时取回的那 500 首 ——
/// 对 531 首的库就是**默默少 31 首**,页脚那句「N 首」也只敢报本地条数。
/// 现在页脚照实说「已取到 N 首 / 库里 M 首」,并给一颗「继续加载」
/// 兜住「滚到底没触发」的情况(比如列表不够长、或者用户是一路拖到顶的)。
class _SongsTab extends StatelessWidget {
  const _SongsTab({
    required this.library,
    required this.currentSongId,
    required this.playable,
  });

  final LibrarySnapshot library;
  final String? currentSongId;
  final PlaybackController playable;

  @override
  Widget build(BuildContext context) {
    // 这一栏要的三件:仓库(拼封面地址)、歌曲排序口径、还在翻页吗。
    // 单独 select 而不是从上面那张表里拿 —— 换歌曲排序不该连专辑网格一起重建。
    final (repo, sort, loadingMore) = context.select<
        AppState, (MusicSource?, SongSort, bool)>(
      (s) => (s.repository, s.songSort, s.loadingMoreSongs),
    );
    // 「接着取下一页」是动作,用取值函数即可。
    final state = context.read<AppState>();
    // 头一行 + 每首歌一行 + 页脚一行(页脚照实说取到多少 / 库里多少)。
    return NotificationListener<ScrollNotification>(
      // 快到底了就取下一页。留 600 的余量,滚到底时正好接上 ——
      // 等真的滑到头再发请求会看见一段空白。
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
          unawaited(state.loadMoreSongs());
        }
        return false;
      },
      child: ListView.builder(
        // 同 [_AlbumsTab]:不够长也要能下拉刷新。
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: BottomStack.listInset(context),
        ),
        itemCount: library.songs.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return SectionHeader(
              title: '全部歌曲',
              // 标题上写**本地已有的条数**:这一栏铺的就是这些,
              // 库里还有多少写在页脚(那儿才说得清「还差着没取」)。
              count: '${library.songs.length} 首',
              trailing: SortButton(
                label: '按${sort.label}',
                onTap: () => showSortSheet(context, albums: false),
              ),
              padding: const EdgeInsets.fromLTRB(
                NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s3),
            );
          }
          if (index == library.songs.length + 1) {
            return _SongsFooter(
              library: library,
              loadingMore: loadingMore,
              onLoadMore: state.loadMoreSongs,
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
      ),
    );
  }
}

/// 歌曲栏的页脚 —— 「取到多少 / 库里多少」,没取完就给一颗「继续加载」。
///
/// 只报本地条数会让人以为库里就这么多(531 首的库上显示 500 就是这么露的);
/// 只报库里总数又对不上眼前这份列表。两句话一起说才没有歧义。
class _SongsFooter extends StatelessWidget {
  const _SongsFooter({
    required this.library,
    required this.loadingMore,
    required this.onLoadMore,
  });

  final LibrarySnapshot library;

  /// 还在取下一页吗(界面据此把页脚换成一句「正在取剩下的曲目」)。
  final bool loadingMore;

  /// 那颗兜底按钮走它 —— 滚到底会自动接口,这颗是给「列表不够长 / 一路拖到顶」用的。
  final Future<bool> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final total = library.totalSongs;
    final loaded = library.songs.length;
    final missing = library.songsComplete ? 0 : (total - loaded).clamp(0, 1 << 30);

    // 取全了、条数也对得上 —— 那就不必多说什么(库里没问题时报一句总数是噪音)。
    // 取全之后 `total` 就是实际条数,所以「已取到全部 N 首」这句在这里到不了,
    // 页脚收掉本身就是那句「已经到底了」。
    if (!loadingMore && missing <= 0 && loaded == total) {
      return const SizedBox(height: NordicSpace.s5);
    }

    // 「还有 N 首没取」里的 N 来自专辑那一栏报的规模估计,它可能比手头这份
    // 列表还小(有的曲子不在任何专辑里)。那时印出来是「库里 0 首,还有 0 首
    // 没取」—— 两个数自相矛盾,不如只说还没取完。
    final progress = missing > 0
        ? '已取到 $loaded 首 · 库里 $total 首，还有 $missing 首没取'
        : '已取到 $loaded 首 · 库里还有没取到的曲目';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, NordicSpace.s4, NordicSpace.s5, NordicSpace.s5),
      child: Column(
        children: [
          Text(
            progress,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: t.fg3, height: 1.5),
          ),
          if (loadingMore) ...[
            const SizedBox(height: NordicSpace.s4),
            const LoadingState(message: '正在取剩下的曲目', topPadding: 0),
          ] else if (!library.songsComplete) ...[
            // 滚到底会自动接着取;这颗是兜底(列表不够长、或者一路拖到顶)。
            const SizedBox(height: NordicSpace.s4),
            SizedBox(
              width: 200,
              child: GhostButton(
                label: '继续加载',
                icon: Icons.expand_more,
                onPressed: onLoadMore,
              ),
            ),
          ],
        ],
      ),
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
    // 这一栏只用「仓库」这一件(拼封面地址)—— 别 watch 整个 `AppState`。
    final repo = context.select<AppState, MusicSource?>(
      (s) => s.repository,
    );

    // 歌单一般不多,但口径与其它两栏统一:一屏一屏地建。
    return ListView.builder(
      // 同 [_AlbumsTab]:不够长也要能下拉刷新。
      physics: const AlwaysScrollableScrollPhysics(),
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
              uri: _uri(repo, playlist.coverArtId),
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

  Uri? _uri(MusicSource? repo, String? coverArtId) {
    if (repo == null || coverArtId == null) return null;
    try {
      return repo.coverUri(coverArtId, size: 256);
    } on MusicSourceException {
      return null;
    }
  }
}
