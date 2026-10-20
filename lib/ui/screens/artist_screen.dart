import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/music_source.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import 'song_menu_sheet.dart';
import '../shell/bottom_stack.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import '../widgets/states.dart';

/// 艺人详情 —— 大头像 + 热门 + 专辑货架。
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key, required this.artistId});

  final String artistId;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  Artist? _artist;
  List<Album> _albums = const [];
  List<Song> _topSongs = const [];
  String? _error;
  bool _loading = true;
  bool _starred = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final repo = state.repository;
    if (repo == null) {
      setState(() {
        _loading = false;
        _error = '还没有连接服务器';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await repo.artist(widget.artistId);
      if (!mounted) return;
      setState(() {
        _artist = detail.artist;
        _albums = detail.albums;
        _topSongs = detail.topSongs;
        _loading = false;
        _starred = state.isArtistStarred(widget.artistId);
      });
    } on MusicSourceException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = NordicAccent.derived(widget.artistId);

    return ImmersiveScaffold(
      accent: accent,
      // 原型在这几屏上也浮着播放坞 + 标签栏(音乐一直在放,不该因为
      // 进了专辑页就断了入口)。
      showNav: true,
      child: Column(
        children: [
          NordicAppBar(
            title: '',
            big: false,
            transparent: true,
            leading: IconButtonRound(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButtonRound(
                icon: Icons.more_horiz,
                quiet: true,
                onPressed: _artist == null ? null : _showMenu,
              ),
            ],
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingState(message: '正在读取艺人');
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final artist = _artist;
    if (artist == null) {
      return const EmptyState(title: '这位艺人已经不在库里了');
    }

    // 同 [LibraryScreen]:只订阅高亮要的两件,动作走 read。
    final playable = context.read<PlaybackController>();
    final (currentId, playing) = context
        .select<PlaybackController, (String?, bool)>(
      (p) => (p.state.song?.id, p.state.playing),
    );
    // 订阅的只有「仓库」这一件(拼封面地址用);动作(收藏、下载)走取值函数,
    // 下载进度与缓存淘汰于是不会把这一屏拖着重建。
    final repo = context.select<AppState, MusicSource?>(
      (s) => s.repository,
    );

    // 有作品才给播放入口。库里没歌的艺人点「播放」会去播上一首别人的歌 ——
    // 那一下等于对用户说了假话,所以整行收掉,旁边说明一句。
    final playableSongs = _topSongs.isNotEmpty || _albums.isNotEmpty;

    // sliver 铺法 —— 与专辑页、歌单页同一条家法:热门曲目一次全建出来,
    // 每次播放状态一变就重来一遍,没必要。
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _ArtistHead(artist: artist)),
        SliverToBoxAdapter(
          child: _ArtistActions(
            starred: _starred,
            playable: playableSongs && _topSongs.isNotEmpty,
            onPlay: _topSongs.isEmpty
                ? null
                : () => playable.playAll(_topSongs, index: 0),
            onShuffle: _topSongs.isEmpty
                ? null
                : () {
                    final shuffled = [..._topSongs]..shuffle();
                    playable.playAll(shuffled, index: 0);
                  },
            onToggleStar: _toggleStar,
          ),
        ),
        if (!playableSongs)
          const SliverToBoxAdapter(
            child: ListNote('这个库里没有这位艺人的可播放曲目，换一位试试。'),
          ),
        if (_topSongs.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: '热门歌曲',
              count: '${_topSongs.length} 首',
            ),
          ),
          SliverList.builder(
            itemCount: _topSongs.length,
            itemBuilder: (context, i) => TrackRow(
              song: _topSongs[i],
              // 「热门」按播放量排,序数没有意义,所以不排曲序。
              playing: _topSongs[i].id == currentId && playing,
              onTap: () => playable.playAll(_topSongs, index: i),
              trailing: IconButtonRound(
                icon: Icons.more_horiz,
                size: 32,
                iconSize: 18,
                quiet: true,
                onPressed: () => _songMenu(_topSongs[i]),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: SectionHeader(
            title: '专辑',
            count: _albums.length < artist.albumCount
                ? '${_albums.length} / ${artist.albumCount} 张'
                : '${_albums.length} 张',
          ),
        ),
        if (_albums.isEmpty)
          const SliverToBoxAdapter(
            child: ListNote('服务器上这位艺人名下有专辑记录，但这次没有返回具体条目。'),
          )
        else
          SliverToBoxAdapter(
            child: SizedBox(
              height: shelfHeight(context, artwork: 142),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                  NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s4),
                itemCount: _albums.length,
                separatorBuilder: (_, _) => const SizedBox(width: NordicSpace.s4),
                itemBuilder: (context, index) {
                  final album = _albums[index];
                  return Pressable(
                    onTap: () => AppRoutes.openAlbum(context, album.id),
                    scale: 0.97,
                    child: SizedBox(
                      width: 142,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Cover(
                            coverArtId: album.coverArtId,
                            seed: album.id,
                            uri: albumCoverUri(repo, album.coverArtId),
                            size: 142,
                            radius: 22,
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
                            album.year == null
                                ? '${album.songCount} 首'
                                : '${album.year}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: context.nordic.fg3),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        if (_albums.isNotEmpty && _albums.length < artist.albumCount)
          SliverToBoxAdapter(
            child: ListNote(
              '服务器上 ${artist.name} 共有 ${artist.albumCount} 张唱片，'
              '这里列出了 ${_albums.length} 张。',
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: BottomStack.listInset(context)),
        ),
      ],
    );
  }

  Future<void> _toggleStar() async {
    final state = context.read<AppState>();
    final ok = await state.toggleArtistStar(widget.artistId);
    if (!mounted) return;
    setState(() => _starred = state.isArtistStarred(widget.artistId));
    // 同专辑页:失败时那句「已收藏」会是假的(状态已经滚回去了)。
    _toast(ok
        ? (_starred ? '已收藏这位艺人' : '已取消收藏')
        : '没能存到服务器，收藏状态已退回 —— 检查网络后再试');
  }

  void _showMenu() {
    showNordicSheet<void>(
      context: context,
      builder: (context) => NordicScrim(
        onTap: () => Navigator.of(context).pop(),
        child: NordicSheet(
          title: _artist?.name ?? '',
          subtitle: _artist == null ? null : '${_artist!.albumCount} 张专辑',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NordicMenuRow(
                icon: _starred ? Icons.favorite : Icons.favorite_border,
                label: _starred ? '取消收藏' : '收藏这位艺人',
                onTap: () {
                  Navigator.of(context).pop();
                  _toggleStar();
                },
              ),
              NordicMenuRow(
                icon: Icons.queue_music,
                label: '热门歌曲加入队列',
                onTap: () {
                  Navigator.of(context).pop();
                  _queueAll();
                },
              ),
              NordicMenuRow(
                icon: Icons.download_outlined,
                label: '下载全部歌曲',
                onTap: () {
                  Navigator.of(context).pop();
                  _downloadAll();
                },
              ),
              const SizedBox(height: NordicSpace.s2),
            ],
          ),
        ),
      ),
    );
  }

  /// 下载这位艺人的全部歌曲。
  ///
  /// 曲目得在全库里翻页找齐(`getArtist` 只给几首热门),大库上这一步要等
  /// 几秒 —— 先给一句提示再动手,否则这段时间界面看着像卡住了。
  Future<void> _downloadAll() async {
    final artist = _artist;
    if (artist == null) return;
    final state = context.read<AppState>();

    _toast('正在整理 ${artist.name} 的曲目…');
    try {
      final job = await state.downloadArtist(artist);
      if (!mounted) return;
      _toast(job.queuedNotice);
    } catch (e) {
      if (!mounted) return;
      _toast('$e');
    }
  }

  Future<void> _queueAll() async {
    final playable = context.read<PlaybackController>();
    for (final song in _topSongs) {
      await playable.append(song);
    }
    _toast('${_topSongs.length} 首已加入队列');
  }

  void _songMenu(Song song) => showSongMenu(context, song);

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _ArtistHead extends StatelessWidget {
  const _ArtistHead({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s5),
      child: Row(
        children: [
          ArtistPlate(artist: artist, size: 104, radius: 30),
          const SizedBox(width: NordicSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  artist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontSize: 29,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                ),
                const SizedBox(height: 8),
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
        ],
      ),
    );
  }
}

class _ArtistActions extends StatelessWidget {
  const _ArtistActions({
    required this.starred,
    required this.playable,
    required this.onPlay,
    required this.onShuffle,
    required this.onToggleStar,
  });

  final bool starred;
  final bool playable;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback onToggleStar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s4),
      child: Row(
        children: [
          if (playable)
            Expanded(
              child: PrimaryButton(
                label: '播放热门',
                icon: Icons.play_arrow,
                height: 48,
                onPressed: onPlay,
              ),
            ),
          if (playable) const SizedBox(width: NordicSpace.s3),
          IconButtonRound(
            icon: Icons.shuffle,
            size: 48,
            iconSize: 20,
            halo: true,
            onPressed: onShuffle,
          ),
          const SizedBox(width: NordicSpace.s3),
          IconButtonRound(
            icon: starred ? Icons.favorite : Icons.favorite_border,
            size: 48,
            iconSize: 20,
            halo: true,
            color: starred ? context.accentSafe : null,
            onPressed: onToggleStar,
          ),
          if (!playable)
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: NordicSpace.s3),
                child: Text(
                  '库里没有这位艺人的曲目',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

