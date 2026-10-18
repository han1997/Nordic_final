import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/subsonic_payload.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../shell/bottom_stack.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import '../widgets/states.dart';

/// 专辑详情 —— 氛围背景 + 大封面 + 曲目表。
///
/// 头部的曲目数用的是**服务器报的整张数量**([Album.songCount]),
/// 而我们一次可能只拉到其中一部分 —— 两者不一致时页脚必须说清楚,
/// 否则用户会以为是漏数据。
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.albumId});

  final String albumId;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  Album? _album;
  List<Song> _songs = const [];
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
      final detail = await repo.album(widget.albumId);
      if (!mounted) return;
      setState(() {
        _album = detail.album;
        _songs = detail.songs;
        _loading = false;
        _starred = state.isAlbumStarred(widget.albumId);
      });
    } on SubsonicException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = _album;
    final accent = album == null
        ? NordicAccent.derived(widget.albumId)
        : NordicAccent.derived(album.id);

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
            // 顶栏只剩返回与「⋯」—— 与歌词页同一副骨架。下载原先在这里,
            // 而「⋯」里本来就有「整张下载到本机」,两处重复只让顶栏更挤。
            actions: [
              IconButtonRound(
                icon: Icons.more_horiz,
                quiet: true,
                onPressed: album == null ? null : _showMenu,
              ),
            ],
          ),
          Expanded(child: _body(album)),
        ],
      ),
    );
  }

  Widget _body(Album? album) {
    if (_loading) return const LoadingState(message: '正在读取专辑');
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (album == null) {
      return const EmptyState(title: '这张专辑已经不在库里了');
    }

    final playable = context.watch<PlaybackController>();
    final currentId = playable.state.song?.id;

    // 服务器报的整张首数 vs 我们实际拿到的条数。
    final missing = album.songCount - _songs.length;

    // sliver 铺法:曲目多的时候(库里有五百首一张的专辑)一次铺完要好几帧。
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _AlbumHead(
            album: album,
            repoCoverUri: _coverUri(album.coverArtId, 512),
          ),
        ),
        SliverToBoxAdapter(
          child: _PlayButton(
            onPlay: _songs.isEmpty
                ? null
                : () => playable.playAll(_songs, index: 0),
          ),
        ),
        if (_songs.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              title: '这张专辑里还没有曲目',
              detail: '服务器上有这张专辑的记录，但没有可播放的文件。',
              topPadding: 40,
            ),
          )
        else
          SliverList.builder(
            itemCount: _songs.length,
            itemBuilder: (context, i) => TrackRow(
              song: _songs[i],
              trackNumber: _songs[i].track ?? i + 1,
              playing: _songs[i].id == currentId && playable.state.playing,
              onTap: () => playable.playAll(_songs, index: i),
            ),
          ),
        if (missing > 0)
          SliverToBoxAdapter(
            child: ListNote(
              '服务器把这张专辑记为 ${album.songCount} 首，当前只取到 ${_songs.length} 首，'
              '还有 $missing 首没有返回。',
            ),
          )
        else if (_songs.isNotEmpty)
          SliverToBoxAdapter(
            child: ListNote(
              '${album.name} · ${album.artist}'
              '${album.year == null ? '' : ' · ${album.year}'}',
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: BottomStack.listInset(context)),
        ),
      ],
    );
  }

  Uri? _coverUri(String? artId, int size) {
    final repo = context.read<AppState>().repository;
    if (repo == null || artId == null) return null;
    try {
      return repo.coverUri(artId, size: size);
    } on SubsonicException {
      return null;
    }
  }

  Future<void> _toggleStar() async {
    final state = context.read<AppState>();
    final ok = await state.toggleAlbumStar(widget.albumId);
    if (!mounted) return;
    setState(() => _starred = state.isAlbumStarred(widget.albumId));
    // 没存上的时候**不能说「已收藏」** —— 状态已经滚回去了,那句提示就成了
    // 假的;用户也才分得出「没点上」与「没存上」。
    _toast(ok
        ? (_starred ? '已收藏这张专辑' : '已取消收藏')
        : '没能存到服务器，收藏状态已退回 —— 检查网络后再试');
  }

  void _showQueue() {
    // 队列面板在播放页;专辑页的「队列」按钮直接跳过去,比在这里
    // 另建一份队列 UI 更省事,也不会两处不同步。
    AppRoutes.openPlayer(context);
  }

  Future<void> _downloadToQueue(Album album) async {
    // 下的是**当前已加载的曲目表**:没加载出来的曲目我们不知道 id,
    // 只报个数量给下载器,它也无从下手。
    final state = context.read<AppState>();
    try {
      final job = await state.downloadAlbum(album, _songs);
      if (!mounted) return;
      _toast(job.queuedNotice);
    } catch (e) {
      if (!mounted) return;
      _toast('$e');
    }
  }

  void _showMenu() {
    showNordicSheet<void>(
      context: context,
      builder: (context) => NordicScrim(
        onTap: () => Navigator.of(context).pop(),
        child: NordicSheet(
          title: _album?.name ?? '',
          subtitle: _album?.artist,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NordicMenuRow(
                icon: _starred ? Icons.favorite : Icons.favorite_border,
                label: _starred ? '取消收藏' : '收藏这张专辑',
                onTap: () {
                  Navigator.of(context).pop();
                  _toggleStar();
                },
              ),
              NordicMenuRow(
                icon: Icons.shuffle,
                label: '随机播放这张专辑',
                onTap: () {
                  Navigator.of(context).pop();
                  _shufflePlay();
                },
              ),
              NordicMenuRow(
                icon: Icons.download_outlined,
                label: '整张下载到本机',
                onTap: () {
                  Navigator.of(context).pop();
                  if (_album != null) _downloadToQueue(_album!);
                },
              ),
              NordicMenuRow(
                icon: Icons.queue_music,
                label: '加入播放队列',
                onTap: () {
                  Navigator.of(context).pop();
                  _addAllToQueue();
                },
              ),
              NordicMenuRow(
                icon: Icons.queue_music,
                label: '查看播放队列',
                onTap: () {
                  Navigator.of(context).pop();
                  _showQueue();
                },
              ),
              const SizedBox(height: NordicSpace.s2),
            ],
          ),
        ),
      ),
    );
  }

  /// 「随机播放」= 打乱后整队装载并开播,而不是只跳一首。
  void _shufflePlay() {
    if (_songs.isEmpty) return;
    final playable = context.read<PlaybackController>();
    playable.playAll([..._songs]..shuffle(), index: 0);
  }

  Future<void> _addAllToQueue() async {
    final playable = context.read<PlaybackController>();
    for (final song in _songs) {
      await playable.append(song);
    }
    _toast('${_songs.length} 首已加入队列');
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

/// 专辑头部 —— 居中:封面、标题、艺人、一行 meta。
///
/// 向歌词页看齐:那一屏之所以清爽,一半在「舍得空、只有一件主事」。
/// **音质不往这里写** —— 它是每首曲子的事(曲目行里已经有了),头部再说一遍是重复。
class _AlbumHead extends StatelessWidget {
  const _AlbumHead({required this.album, required this.repoCoverUri});

  final Album album;
  final Uri? repoCoverUri;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final artistId = album.artistId;
    final meta = [
      if (album.year != null) '${album.year}',
      '${album.songCount} 首',
      if (album.genre != null) album.genre!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s6, NordicSpace.s6, NordicSpace.s6, NordicSpace.s5),
      child: Column(
        children: [
          Hero(
            tag: 'cover-${album.id}',
            child: Cover(
              coverArtId: album.coverArtId,
              seed: album.id,
              uri: repoCoverUri,
              size: 168,
              radius: 26,
            ),
          ),
          const SizedBox(height: NordicSpace.s4),
          Text(
            album.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.12,
                ),
          ),
          const SizedBox(height: 6),
          // 艺人名可点才挂手势;库里没这位艺人时保持纯文字 ——
          // 点了跳到别人页比不能点更糟。
          if (artistId != null && artistId.isNotEmpty)
            GestureDetector(
              onTap: () => AppRoutes.openArtist(context, artistId),
              child: Text(
                album.artist,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    Theme.of(context).textTheme.bodyLarge?.copyWith(color: t.fg2),
              ),
            )
          else
            Text(
              album.artist,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: t.fg2),
            ),
          const SizedBox(height: 5),
          Text(
            meta,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.fg3),
          ),
        ],
      ),
    );
  }
}

/// 播放独占一行:整屏只有这一颗实心按钮。
///
/// 原先这一行挤着四颗(播放 / 随机 / 收藏 / 队列),它们把封面挤到左上角、
/// 整屏读起来全是控件。随机与收藏进了「⋯」——「播这张专辑」才是这一屏的主事。
/// 宽度收成一枚**居中的胶囊**而不是通栏,与居中构图一致。
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onPlay});

  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s5),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 190),
          child: PrimaryButton(
            label: '播放',
            icon: Icons.play_arrow,
            height: 50,
            fillMaxWidth: false,
            onPressed: onPlay,
          ),
        ),
      ),
    );
  }
}

/// 上下文菜单的一行 —— `.menu-item`。

