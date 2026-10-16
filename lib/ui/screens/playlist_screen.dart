import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/subsonic_payload.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import '../widgets/states.dart';

/// 歌单详情 —— 曲目表 + 整单播放。
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  Playlist? _playlist;
  List<Song> _songs = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = context.read<AppState>().repository;
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
      final detail = await repo.playlist(widget.playlistId);
      if (!mounted) return;
      setState(() {
        _playlist = detail.playlist;
        _songs = detail.songs;
        _loading = false;
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
    final accent = NordicAccent.derived(widget.playlistId);

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
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingState(message: '正在读取歌单');
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final playlist = _playlist;
    if (playlist == null) {
      return const EmptyState(title: '这个歌单已经不在库里了');
    }

    final state = context.watch<AppState>();
    final playable = context.watch<PlaybackController>();
    final currentId = playable.state.song?.id;
    final total = _songs.fold(Duration.zero, (sum, s) => sum + s.duration);

    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + NordicSpace.s6,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Cover(
                coverArtId: playlist.coverArtId,
                seed: playlist.id,
                uri: _coverUri(state, playlist.coverArtId),
                size: 140,
                radius: 24,
              ),
              const SizedBox(width: NordicSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.08,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${playlist.songCount} 首 · ${formatRemaining(total)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.nordic.fg3),
                    ),
                    if (playlist.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        playlist.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: context.nordic.fg3),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s4),
          child: Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: '播放',
                  icon: Icons.play_arrow,
                  height: 48,
                  onPressed: _songs.isEmpty
                      ? null
                      : () => playable.playAll(_songs, index: 0),
                ),
              ),
              const SizedBox(width: NordicSpace.s3),
              IconButtonRound(
                icon: Icons.shuffle,
                size: 48,
                iconSize: 20,
                halo: true,
                onPressed: _songs.isEmpty
                    ? null
                    : () {
                        final shuffled = [..._songs]..shuffle();
                        playable.playAll(shuffled, index: 0);
                      },
              ),
              const SizedBox(width: NordicSpace.s3),
              IconButtonRound(
                icon: Icons.queue_music,
                size: 48,
                iconSize: 20,
                halo: true,
                onPressed: _songs.isEmpty ? null : () => _addAll(playable),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
          child: Divider(height: 1, color: context.nordic.line),
        ),
        if (_songs.isEmpty)
          const EmptyState(
            title: '这个歌单里还没有歌',
            detail: '在歌曲菜单里可以把它加进来。',
            topPadding: 40,
          )
        else
          for (var i = 0; i < _songs.length; i++)
            TrackRow(
              song: _songs[i],
              trackNumber: i + 1,
              playing: _songs[i].id == currentId && playable.state.playing,
              onTap: () => playable.playAll(_songs, index: i),
            ),
        // 服务器报的首数与实际取到的条数不一致时说明一句,免得像漏数据。
        if (_songs.isNotEmpty && playlist.songCount > _songs.length)
          ListNote(
            '服务器把这张歌单记为 ${playlist.songCount} 首,'
            '这次取到 ${_songs.length} 首。',
          ),
      ],
    );
  }

  Uri? _coverUri(AppState state, String? artId) {
    final repo = state.repository;
    if (repo == null || artId == null) return null;
    try {
      return repo.coverUri(artId, size: 512);
    } on SubsonicException {
      return null;
    }
  }

  Future<void> _addAll(PlaybackController playable) async {
    for (final song in _songs) {
      await playable.append(song);
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('${_songs.length} 首已加入队列'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}