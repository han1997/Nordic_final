import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/music_source.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/accent.dart';
import '../../theme/context_ext.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../play_tapped.dart';
import '../shell/bottom_stack.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import '../widgets/states.dart';
import 'song_menu_sheet.dart';

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
  /// 整单时长。**在取到 / 改动曲目时算一次**,不在 build 里现算 ——
  /// 每帧 fold 一遍几百首歌,换来的只是标题里那几个字。
  Duration _totalDuration = Duration.zero;
  String? _error;
  bool _loading = true;

  static Duration _sumOf(Iterable<Song> songs) =>
      songs.fold(Duration.zero, (sum, s) => sum + s.duration);

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
        _totalDuration = _sumOf(detail.songs);
        _loading = false;
      });
    } on MusicSourceException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      // 同 [AlbumScreen._load]:兜住 `MusicSourceException` 之外的一切,
      // 否则 `_loading` 停在 true 就是一屏转不完的圈。
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = NordicAccent.derived(widget.playlistId);
    final playlist = _playlist;
    // 服务器标了只读的歌单(别人分享给你的那种)不给改写的入口 ——
    // 摆在这里也只会换来一句服务器拒绝。
    final editable = playlist != null && !playlist.readonly;

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
              if (editable)
                IconButtonRound(
                  icon: Icons.more_horiz,
                  quiet: true,
                  onPressed: _showMenu,
                ),
            ],
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

    // 订阅的只有「仓库」这一件(拼封面地址用);写操作(加歌、改名、移除)
// 走取值函数 —— 下载进度与缓存淘汰于是不会把这一屏拖着重建。
    final repo = context.select<AppState, MusicSource?>(
      (s) => s.repository,
    );
    // 同 [LibraryScreen]:只订阅高亮要的两件,动作走 read。
    final playable = context.read<PlaybackController>();
    final (currentId, playing) = context
        .select<PlaybackController, (String?, bool)>(
      (p) => (p.state.song?.id, p.state.playing),
    );

    // sliver 铺法 —— 与专辑页同一条家法:曲目多的时候(几百首的歌单)
    // 一次全建出来要好几帧,而且每次播放状态 / 应用状态一变就重来一遍。
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Cover(
                  coverArtId: playlist.coverArtId,
                  seed: playlist.id,
                  uri: albumCoverUri(repo, playlist.coverArtId),
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
                        '${playlist.songCount} 首 · ${formatRemaining(_totalDuration)}',
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
        ),
        SliverToBoxAdapter(
          child: Padding(
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
                        : () => playTapped(context, _songs, index: 0),
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
                          unawaited(
                            playTapped(context, [..._songs]..shuffle(), index: 0),
                          );
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
        ),
        const SliverToBoxAdapter(child: NordicDivider()),
        if (_songs.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              title: '这个歌单里还没有歌',
              detail: '在歌曲菜单里可以把它加进来。',
              topPadding: 40,
            ),
          )
        else
          // 歌单里的歌**要带封面** —— 曲序数字在这里没有意义(歌单不是专辑,
          // 顺序也不按 track),而封面是「一眼认出是哪首」最快的线索。
          // 与音乐库「全部歌曲」那一栏同一颗 [SongRow],观感一致。
          SliverList.builder(
            itemCount: _songs.length,
            itemBuilder: (context, i) => SongRow(
              song: _songs[i],
              coverUri: (id) => albumCoverUri(repo, id, size: 128),
              playing: _songs[i].id == currentId && playing,
              onTap: () => playTapped(
                context,
                _songs,
                index: i,
                label: _songs[i].title,
              ),
              trailing: playlist.readonly
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatDuration(_songs[i].duration),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: context.nordic.fg3),
                        ),
                        const SizedBox(width: NordicSpace.s2),
                        IconButtonRound(
                          icon: Icons.more_horiz,
                          size: 32,
                          iconSize: 16,
                          quiet: true,
                          onPressed: () => _songMenu(i),
                        ),
                      ],
                    ),
            ),
          ),
        // 服务器报的首数与实际取到的条数不一致时说明一句,免得像漏数据。
        if (_songs.isNotEmpty && playlist.songCount > _songs.length)
          SliverToBoxAdapter(
            child: ListNote(
              '服务器把这张歌单记为 ${playlist.songCount} 首，'
              '这次取到 ${_songs.length} 首。',
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: BottomStack.listInset(context)),
        ),
      ],
    );
  }

  Future<void> _addAll(PlaybackController playable) async {
    for (final song in _songs) {
      await playable.append(song);
    }
    if (!mounted) return;
    _toast('${_songs.length} 首已加入队列');
  }

  // ---------------- 歌单管理 ----------------

  /// 歌单自己的菜单。只读歌单没有这个入口(见 [build])。
  void _showMenu() {
    final playlist = _playlist;
    if (playlist == null) return;

    showNordicSheet<void>(
      context: context,
      builder: (sheetContext) => NordicScrim(
        onTap: () => Navigator.of(sheetContext).pop(),
        child: NordicSheet(
          title: playlist.name,
          subtitle: '${playlist.songCount} 首',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NordicMenuRow(
                icon: Icons.edit_outlined,
                label: '重命名歌单',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _rename();
                },
              ),
              NordicMenuRow(
                icon: Icons.delete_outline,
                label: '删除这个歌单',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDelete();
                },
              ),
              const SizedBox(height: NordicSpace.s2),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename() async {
    final playlist = _playlist;
    if (playlist == null) return;

    final controller = TextEditingController(text: playlist.name)
      // 改名时多半是整个换掉,所以默认全选 —— 省一次手动清空。
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: playlist.name.length,
      );

    final name = await showNordicSheet<String>(
      context: context,
      // 软键盘弹出时整张纸要跟着抬起来,不然输入框会被盖住。
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: NordicScrim(
          onTap: () => Navigator.of(sheetContext).pop(),
          child: NordicSheet(
            title: '重命名歌单',
            subtitle: '原标题：${playlist.name}',
            child: _RenameForm(
              controller: controller,
              original: playlist.name,
              onSubmit: (value) => Navigator.of(sheetContext).pop(value),
            ),
          ),
        ),
      ),
    );
    controller.dispose();

    if (name == null || !mounted) return;
    try {
      await context.read<AppState>().renamePlaylist(playlist.id, name);
      if (!mounted) return;
      // 本屏自己那份也要跟着改 —— 它不会因为 AppState 更新而重拉。
      setState(() => _playlist = playlist.copyWith(name: name));
      _toast('已改名为「$name」');
    } catch (e) {
      if (!mounted) return;
      _toast('$e', duration: const Duration(seconds: 3));
    }
  }

  Future<void> _confirmDelete() async {
    final playlist = _playlist;
    if (playlist == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.nordic.glass3,
        title: const Text('删除这个歌单？'),
        content: Text(
          '「${playlist.name}」会从服务器上删掉，里面的 ${playlist.songCount} 首曲子'
          '本身不受影响。这一步不能撤销。',
          style: Theme.of(dialogContext).textTheme.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('删除', style: TextStyle(color: dialogContext.nordic.bad)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 提示要在**退出本屏之前**找好 —— 退出后 context 就跟着作废了。
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await context.read<AppState>().deletePlaylist(playlist.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(
        content: Text('「${playlist.name}」已删除'),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      _toast('$e', duration: const Duration(seconds: 3));
    }
  }

  void _songMenu(int index) => showSongMenu(
        context,
        _songs[index],
        onRemoveFromPlaylist: () => _removeAt(index),
      );

  /// 从歌单里移除一首。**按位置移除** —— 同一首歌在歌单里出现两次时,
  /// 只有位置说得清要移掉哪一次(见 [MusicSource.removeFromPlaylist])。
  Future<void> _removeAt(int index) async {
    final playlist = _playlist;
    if (playlist == null || index < 0 || index >= _songs.length) return;

    final song = _songs[index];
    try {
      await context.read<AppState>().removeSongFromPlaylist(playlist.id, index);
      if (!mounted) return;
      setState(() {
        _songs = [..._songs]..removeAt(index);
        _totalDuration -= song.duration;
        _playlist = playlist.copyWith(
          songCount: (playlist.songCount - 1).clamp(0, 1 << 30),
        );
      });
      _toast('已从歌单移除「${song.title}」');
    } catch (e) {
      if (!mounted) return;
      _toast('没能移除：$e', duration: const Duration(seconds: 3));
    }
  }

  void _toast(String message, {Duration? duration}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 2),
      ),
    );
  }
}

/// 重命名表单。名字没变(或被清空)时保存按钮是灰的 ——
/// 空名字会把歌单变成列表里一行看不见的东西。
class _RenameForm extends StatelessWidget {
  const _RenameForm({
    required this.controller,
    required this.original,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String original;
  final void Function(String) onSubmit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final name = value.text.trim();
        final usable = name.isNotEmpty && name != original;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
              child: NordicField(
                label: '歌单名称',
                child: NordicTextField(
                  controller: controller,
                  hintText: '例如：深夜驾驶',
                  autofocus: true,
                ),
              ),
            ),
            const SizedBox(height: NordicSpace.s5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
              child: PrimaryButton(
                label: '保存',
                height: 48,
                onPressed: usable ? () => onSubmit(name) : null,
              ),
            ),
            const SizedBox(height: NordicSpace.s5),
          ],
        );
      },
    );
  }
}