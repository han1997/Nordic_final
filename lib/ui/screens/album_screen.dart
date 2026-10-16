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
                icon: Icons.download_outlined,
                quiet: true,
                onPressed: album == null ? null : () => _downloadToQueue(album),
              ),
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

    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + NordicSpace.s6,
      ),
      children: [
        _AlbumHead(
          album: album,
          repoCoverUri: _coverUri(album.coverArtId, 512),
        ),
        _ActionRow(
          starred: _starred,
          onPlay: _songs.isEmpty
              ? null
              : () => playable.playAll(_songs, index: 0),
          onShuffle: _songs.isEmpty
              ? null
              : () {
                  // 「随机播放」= 打乱后整队装载并开播,而不是只跳一首。
                  final shuffled = [..._songs]..shuffle();
                  playable.playAll(shuffled, index: 0);
                },
          onToggleStar: _toggleStar,
          onQueue: _songs.isEmpty ? null : _showQueue,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
          child: Divider(height: 1, color: context.nordic.line),
        ),
        if (_songs.isEmpty)
          const EmptyState(
            title: '这张专辑里还没有曲目',
            detail: '服务器上有这张专辑的记录,但没有可播放的文件。',
            topPadding: 40,
          )
        else
          for (var i = 0; i < _songs.length; i++)
            TrackRow(
              song: _songs[i],
              trackNumber: _songs[i].track ?? i + 1,
              playing: _songs[i].id == currentId && playable.state.playing,
              onTap: () => playable.playAll(_songs, index: i),
            ),
        if (missing > 0)
          ListNote(
            '服务器把这张专辑记为 ${album.songCount} 首,当前只取到 ${_songs.length} 首,'
            '还有 $missing 首没有返回。',
          )
        else if (_songs.isNotEmpty)
          ListNote(
            '${album.name} · ${album.artist}'
            '${album.year == null ? '' : ' · ${album.year}'}',
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
    await state.toggleAlbumStar(widget.albumId);
    if (!mounted) return;
    setState(() => _starred = state.isAlbumStarred(widget.albumId));
    _toast(_starred ? '已收藏这张专辑' : '已取消收藏');
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
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
              const SizedBox(height: NordicSpace.s2),
            ],
          ),
        ),
      ),
    );
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

/// 专辑头部 —— 大封面 + 标题 + 艺人 + 元信息。
class _AlbumHead extends StatelessWidget {
  const _AlbumHead({required this.album, required this.repoCoverUri});

  final Album album;
  final Uri? repoCoverUri;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final artistId = album.artistId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Hero(
            tag: 'cover-${album.id}',
            child: Cover(
              coverArtId: album.coverArtId,
              seed: album.id,
              uri: repoCoverUri,
              size: 140,
              radius: 24,
            ),
          ),
          const SizedBox(width: NordicSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  album.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.08,
                      ),
                ),
                const SizedBox(height: 8),
                // 艺人名可点才挂手势;库里没这位艺人时保持纯文字 ——
                // 点了跳到别人页比不能点更糟。
                if (artistId != null && artistId.isNotEmpty)
                  GestureDetector(
                    onTap: () => AppRoutes.openArtist(context, artistId),
                    child: Text(
                      album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: t.fg2),
                    ),
                  )
                else
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: t.fg2),
                  ),
                const SizedBox(height: 7),
                Text(
                  [
                    if (album.year != null) '${album.year}',
                    '${album.songCount} 首',
                    if (album.genre != null) album.genre!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

/// 动作排 —— 播放 / 随机 / 收藏 / 队列。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.starred,
    required this.onPlay,
    required this.onShuffle,
    required this.onToggleStar,
    required this.onQueue,
  });

  final bool starred;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback onToggleStar;
  final VoidCallback? onQueue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s4),
      child: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: '播放',
              icon: Icons.play_arrow,
              height: 48,
              onPressed: onPlay,
            ),
          ),
          const SizedBox(width: NordicSpace.s3),
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
          const SizedBox(width: NordicSpace.s3),
          IconButtonRound(
            icon: Icons.queue_music,
            size: 48,
            iconSize: 20,
            halo: true,
            onPressed: onQueue,
          ),
        ],
      ),
    );
  }
}

/// 上下文菜单的一行 —— `.menu-item`。

