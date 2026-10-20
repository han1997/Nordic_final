import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/server_config.dart';
import '../../data/music_source.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/ambient.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../shell/bottom_stack.dart';
import '../shell/shell.dart';
import '../widgets/album_rail.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import '../widgets/states.dart';
import 'library_screen.dart';

/// 首页 —— 进来先看「现在在听什么」和「最近在听什么」。
///
/// 它取代了原先那个**单独的搜索 tab**:搜索是「我知道要找什么」时的动作,
/// 而首页是「不知道听什么」时的落点 —— 后者才配占一个常驻位置。
/// 搜索入口没丢:顶栏那颗放大镜即开即用(见 [AppRoutes.openSearch])。
///
/// 这一屏的每条货架都是**服务器口径**(`getAlbumList2` 的 recent / frequent /
/// newest):「最近播放」「常听」本地算不出来,只有服务器有播放统计。
/// 货架为空就整条收掉 —— 空标题下面挂一行「暂无」只是噪音。
/// 首页真正订阅的那几件 `AppState` 数据。
///
/// **别换回 `watch<AppState>()`。** 下载进度最多每秒播报四次、缓存淘汰也会
/// 播报,而它们一件都不在这张表里;记录是按**值**比较的,于是那些通知到不了
/// 这一屏 —— 三条货架与顶栏不会跟着下载进度重建。表里每一件都必须是 build 体
/// (含它调用的私有方法)真正读到的,漏一件就是那一件不再更新。
typedef _HomeView = ({
  bool hasServer,
  ServerConfig? server,
  LibrarySnapshot library,
  LoadPhase phase,
  String? error,
  bool errorIsAuth,
  bool errorIsNetwork,
  String? refreshError,
  DateTime? cachedAt,
  MusicSource? repository,
  /// 断网失败时那句「本机已下载的还在」要不要给 —— 由下载列表算出来,
  /// 所以它进表(下载**完成**会让它翻面,进度跳动不会)。
  bool offlineReady,
});

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final view = context.select<AppState, _HomeView>((s) => (
          hasServer: s.hasServer,
          server: s.server,
          library: s.library,
          phase: s.phase,
          error: s.error,
          errorIsAuth: s.errorIsAuth,
          errorIsNetwork: s.errorIsNetwork,
          refreshError: s.refreshError,
          cachedAt: s.libraryCachedAt,
          repository: s.repository,
          offlineReady: s.downloads.any((j) => j.isDone),
        ));
    // 方法用这一份:取值函数不参与重建判定(下拉刷新、重试都走它)。
    final state = context.read<AppState>();

    return Scaffold(
      backgroundColor: context.nordic.bg,
      body: Stack(
        children: [
          // 首页是「正在播放」的主场,氛围背景跟着当前封面走 ——
          // 播放页与歌词页也是这一套,三处是同一个视觉语言。
          if (view.hasServer) const _HomeAmbient(),
          Column(
            children: [
              NordicAppBar(
                // 顶栏**不铺实色底**:首页背后是跟着封面走的氛围渐变,
                // 一块纯色顶栏会把顶部与中间切成两截(真机反馈的颜色断层)。
                transparent: true,
                title: '首页',
                subtitle: view.server == null
                    ? '还没有连接服务器'
                    : '${view.server!.name} · ${view.library.totalSongs} 首',
                actions: [
                  IconButtonRound(
                    icon: Icons.search,
                    quiet: true,
                    onPressed: () => AppRoutes.openSearch(context),
                  ),
                ],
              ),
              Expanded(child: _body(context, state, view)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AppState state, _HomeView view) {
    if (!view.hasServer) {
      return EmptyState(
        title: '还没有连接服务器',
        detail: '扫码带走另一台设备的配置，或者手动填上地址与账号。',
        topPadding: 80,
        // 空态说的是「这儿没有」,那就顺手给出**怎么让它有** ——
        // 只写一句「到设置里填」等于把活交给用户去找。
        //
        // 两颗入口:手动填是原有的路,扫码是这一轮新开的那条 —— 另一台设备上
        // 已经配好的服务器与线路,扫一下就带过来,不必重打一遍地址。两个都落在
        // `EmptyState.action` 那一个槽里,所以自己竖着排。
        action: SizedBox(
          width: 210,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryButton(
                label: '连接服务器',
                icon: Icons.dns_outlined,
                onPressed: () => AppRoutes.openServers(context, form: true),
              ),
              const SizedBox(height: NordicSpace.s3),
              GhostButton(
                label: '扫码同步',
                icon: Icons.qr_code_scanner,
                onPressed: () => AppRoutes.openSync(context),
              ),
            ],
          ),
        ),
      );
    }

    // 与音乐库同一套:加载 / 出错时**不显示空态**(见 `app_state.dart` 的约定)。
    switch (view.phase) {
      case LoadPhase.loading:
        return const LoadingState();
      case LoadPhase.failed:
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
    // **只在需要的那一块订阅播放状态**(`_NowPlayingCard` 自己 watch)。
    // 这里原先整屏 `watch`:每次播放 / 暂停 / 换歌,三条货架连同它们的封面
    // 都要重建一遍 —— 而货架只在「点一下开播」时用到播放层(一个回调,
    // 取值就够了)。同一个理由,上面那些 `select` 也是把重建收窄。
    final playable = context.read<PlaybackController>();

    return RefreshIndicator(
      color: context.accentSafe,
      backgroundColor: context.nordic.glass3,
      onRefresh: () => state.loadLibrary(silent: true),
      child: CustomScrollView(
        // 内容装得下时也要能下拉:那句「或下拉刷新」的空态正好出现在
        // **内容最短**的时候,而不可滚动的 scroll view 不发滚动通知,
        // RefreshIndicator 于是永远等不到那一下。
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _NowPlayingHeader()),
          SliverToBoxAdapter(child: _NowPlayingCard()),
          if (view.refreshError != null)
            SliverToBoxAdapter(
              child: StaleBanner(
                message: view.refreshError!,
                savedAt: view.cachedAt,
                onRetry: () => state.loadLibrary(silent: true),
                // 货架列表里没有音乐库那样的顶部留白,这条自己带一点。
                padding: const EdgeInsets.fromLTRB(
                  NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s2),
              ),
            ),
          // 三条货架 —— 「最近在听什么」。还没播过任何东西时,它们正是
          // 「从哪儿开始」的答案,所以这一屏不给空态(那是播放卡自己的事)。
          // 「最近添加」铺**歌曲**而不是专辑 —— 用户要的是「最近加进来的那几首」,
          // 专辑只是它们的容器。服务器没有这个端点,列表由本地按入库时间排出来
          // (见 `app_state.dart` 的 `_recentlyAddedSongs`)。
          _SongShelf(
            title: '最近添加',
            songs: library.recentlyAddedSongs,
            repo: view.repository,
            playable: playable,
          ),
          _Shelf(
            title: '最近播放',
            albums: library.recentlyPlayed,
            repo: view.repository,
            heroPrefix: 'cover-rail-recent',
          ),
          _Shelf(
            title: '最常播放',
            albums: library.mostPlayed,
            repo: view.repository,
            heroPrefix: 'cover-rail-frequent',
          ),
          if (library.recentlyAddedSongs.isEmpty &&
              library.recentlyPlayed.isEmpty &&
              library.mostPlayed.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                title: '这个库里还没有内容',
                detail: '如果服务器上确实有歌，到设置里重新扫描一次曲库，或下拉刷新。',
                topPadding: 40,
              ),
            ),
          if (library.playlists.isNotEmpty)
            SliverToBoxAdapter(
              child: _PlaylistShelf(playlists: library.playlists),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: BottomStack.listInset(context)),
          ),
        ],
      ),
    );
  }
}

/// 首页的氛围背景 —— 跟着当前播放的封面取色。
///
/// 单独一层:它要 watch 播放状态,而下面那几条货架只认音乐库,
/// 合成一处会让「换首歌」把整个首页重建一遍。
class _HomeAmbient extends StatelessWidget {
  const _HomeAmbient();

  @override
  Widget build(BuildContext context) {
    // **只订阅「当前是哪个封面」这一件**:氛围配色只跟 albumId 走,
    // 而 play/pause、时长上报、循环 / 随机翻转都不该让它重建。
    final albumId = context.select<PlaybackController, String?>(
      (p) => p.state.song?.albumId,
    );
    return NordicAmbient(
      accent: albumId == null ? context.accent : NordicAccent.derived(albumId),
    );
  }
}

/// 「正在播放」那一行的标题。
class _NowPlayingHeader extends StatelessWidget {
  const _NowPlayingHeader();

  @override
  Widget build(BuildContext context) =>
      const SectionHeader(title: '正在播放', padding: EdgeInsets.fromLTRB(
        NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s3));
}

/// 大播放卡 —— 首页的主角。
///
/// 与音乐库那张「继续收听」是同一件事,但那是首页**主角**、这里是货架上面
/// 顺手的一格,所以这边给足封面与操作(上一首 / 播放 / 下一首)。
class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard();

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    // 自己订阅播放状态 —— 这一块是首页上唯一跟着播放重建的东西
    // (页头与三条货架不该陪着一起重建)。
    final playable = context.watch<PlaybackController>();
    final song = playable.state.song;

    // 还没播过任何东西:给一张**说明性的空卡**,而不是留白 ——
    // 那一条空白会让人以为加载失败了。
    if (song == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s4),
        child: Container(
          padding: const EdgeInsets.all(NordicSpace.s5),
          decoration: BoxDecoration(
            color: t.fill1,
            borderRadius: BorderRadius.circular(NordicRadius.xl),
            border: Border.all(color: t.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.play_circle_outline, size: 34, color: t.fg3),
                  const SizedBox(width: NordicSpace.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '还没有在播的歌',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '随机放一首，或者从下面挑一张专辑。',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: t.fg3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // 空着的时候**最缺的就是一个开始的动作** —— 让用户先去下面
              // 挑专辑,等于把「怎么开始」交回给他。这里直接给一颗随机播放,
              // 逻辑与音乐库那颗随机键同源(见 [shuffleLibrary])。
              const SizedBox(height: NordicSpace.s4),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: '随机播放',
                  icon: Icons.shuffle,
                  onPressed: () => shuffleLibrary(context, playable),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final accent = context.accent;
    final playing = playable.state.playing;
    // 这张卡只用 `AppState` 里的一件事:仓库(拼封面地址用)——
    // 所以 select 那一件,而不是 watch 整个 `AppState`(下载进度与缓存淘汰
    // 都会把这张卡连同它的封面一起拖着重建)。
    final repo = context.select<AppState, MusicSource?>(
      (s) => s.repository,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s2),
      child: Pressable(
        onTap: () => AppRoutes.openPlayer(context),
        scale: 0.98,
        // **隔一层重绘边界**:这张卡有 44px 的模糊投影、两层渐变,外加里面那张
        // 38px 投影的封面 —— 而它挂在 `SliverToBoxAdapter` 上,那个位置**不带**
        // 重绘边界(sliver 的默认边界只发给 `SliverList` / `SliverGrid` 的子项),
        // 于是首页上下滑动时这几笔每帧重画一遍。隔开之后滑过去只是搬一层已经
        // 光栅化好的图层;按下缩一下那 0.98 也只作用在这一层上。
        child: RepaintBoundary(
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
              // 左上角一团强调色 —— 整张卡的气质来自这里(与音乐库那张同源)。
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
                    coverArtId: song.coverArtId,
                    seed: song.albumId,
                    uri: albumCoverUri(repo, song.coverArtId, size: 256),
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
                          playing ? '正在播放' : '已暂停',
                          style: TextStyle(
                            fontSize: NordicType.xs,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                            color: Color.lerp(accent.accent, t.fg, 0.18),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${song.artist} · ${song.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: t.fg2),
                        ),
                        const SizedBox(height: 8),
                        // 位置**既单独订阅、也单独隔一层重绘边界**:位置每秒变
                        // 好几次,而它上面那张卡带着 44px 的模糊投影 —— 不隔开的话,
                        // 每跳一次数字就把整张卡(含投影)重绘一遍。
                        ValueListenableBuilder<Duration>(
                          valueListenable: playable.position,
                          builder: (context, position, _) => RepaintBoundary(
                            child: Text(
                              '${formatDuration(position)} / '
                              '${formatDuration(playable.state.duration)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: t.fg3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: NordicSpace.s2),
                  // 三颗键**竖着排** —— 横着塞在 92 的封面右边会挤掉歌名。
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButtonRound(
                        icon: Icons.skip_previous,
                        size: 36,
                        iconSize: 21,
                        quiet: true,
                        onPressed:
                            playable.state.hasPrevious ? playable.previous : null,
                      ),
                      const SizedBox(height: 2),
                      IconButtonRound(
                        icon: playing ? Icons.pause : Icons.play_arrow,
                        size: 44,
                        iconSize: 26,
                        color: accent.accent,
                        onPressed: playable.toggle,
                      ),
                      const SizedBox(height: 2),
                      IconButtonRound(
                        icon: Icons.skip_next,
                        size: 36,
                        iconSize: 21,
                        quiet: true,
                        onPressed:
                            playable.state.hasNext ? playable.next : null,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// 一条横滑货架。**没内容就整条不出现** —— 空标题挂一行「暂无」只是噪音。
class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.title,
    required this.albums,
    required this.repo,
    required this.heroPrefix,
  });

  final String title;
  final List<Album> albums;

  /// 只取「仓库」这一件(拼封面地址用),不订阅整个 [AppState]。
  final MusicSource? repo;

  /// 货架之间**唯一**的共享元素前缀 —— 见 [AlbumRail.heroPrefix]:
  /// 首页摆了两条专辑货架,而同一张专辑常常两条都在,写死同一个 tag 会崩。
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title),
          AlbumRail(albums: albums, repo: repo, heroPrefix: heroPrefix),
        ],
      ),
    );
  }
}

/// 歌曲横滑货架 —— 「最近添加」用。
///
/// 与 [AlbumRail] 同一个骨架(横滑、固定宽度、封面 + 两行文字),
/// 差别只有数据是 [Song] 且点一下**直接播**。高度按内容算,不写死。
class _SongShelf extends StatelessWidget {
  const _SongShelf({
    required this.title,
    required this.songs,
    required this.repo,
    required this.playable,
  });

  final String title;
  final List<Song> songs;

  /// 同 [_Shelf]:只要仓库这一件。
  final MusicSource? repo;
  final PlaybackController playable;

  static const _artwork = 132.0;
  static const _tileWidth = 132.0;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final t = context.nordic;

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title),
          SizedBox(
            height: shelfHeight(context, artwork: _artwork),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s4),
              itemCount: songs.length,
              separatorBuilder: (_, _) => const SizedBox(width: NordicSpace.s4),
              itemBuilder: (context, index) {
                final song = songs[index];
                return Pressable(
                  // 点哪首就从哪首开始,队列就是这一条货架 —— 与货架的
                  // 直觉一致(横滑看到的就是接下来会播的)。
                  onTap: () => playable.playAll(songs, index: index),
                  scale: 0.97,
                  child: SizedBox(
                    width: _tileWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Cover(
                          coverArtId: song.coverArtId,
                          seed: song.albumId,
                          uri: albumCoverUri(repo, song.coverArtId, size: 256),
                          size: _artwork,
                          radius: 20,
                        ),
                        const SizedBox(height: 9),
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist,
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
          ),
        ],
      ),
    );
  }
}

/// 歌单横滑 —— 首页也给一条:歌单是「按场景听」的入口,不该只藏在音乐库里。
class _PlaylistShelf extends StatelessWidget {
  const _PlaylistShelf({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final repo = context.select<AppState, MusicSource?>(
      (s) => s.repository,
    );
    final shown = playlists.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '歌单',
          count: '${playlists.length} 个',
          // 不给「全部」那颗按钮:主壳记不住音乐库里选中哪一栏,点了只会落在
          // 「专辑」那一格上 —— 一个说「全部歌单」却跳去专辑的按钮,不如不给。
        ),
        SizedBox(
          height: 58,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: NordicSpace.s2),
            itemBuilder: (context, index) {
              final playlist = shown[index];
              return Pressable(
                onTap: () => AppRoutes.openPlaylist(context, playlist.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: t.fill1,
                    borderRadius: BorderRadius.circular(NordicRadius.full),
                    border: Border.all(color: t.line),
                  ),
                  child: Row(
                    children: [
                      Cover(
                        coverArtId: playlist.coverArtId,
                        seed: playlist.id,
                        uri: albumCoverUri(repo, playlist.coverArtId, size: 128),
                        size: 30,
                        radius: 9,
                        showShadow: false,
                      ),
                      const SizedBox(width: NordicSpace.s3),
                      Text(
                        playlist.name,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: NordicSpace.s2),
                      Text(
                        '${playlist.songCount} 首',
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
        ),
        const SizedBox(height: NordicSpace.s4),
      ],
    );
  }
}
