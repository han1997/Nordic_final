import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/music_source.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../play_tapped.dart';
import '../routes.dart';
import '../shell/bottom_stack.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import '../widgets/states.dart';
import 'library_screen.dart';

/// 搜索的分类筛选。
enum SearchScope {
  all('全部'),
  songs('歌曲'),
  albums('专辑'),
  artists('艺人');

  const SearchScope(this.label);

  final String label;

  String get unit => switch (this) {
        SearchScope.all => '条',
        SearchScope.songs => '首',
        SearchScope.albums => '张',
        SearchScope.artists => '位',
      };
}

/// 搜索 —— 输入即筛选。
///
/// 服务器侧走 `search3`,所以「敲一个字就发一次请求」需要节流:
/// 打字很快时既不希望每个字符都打一次网络,也不希望结果落后于输入。
/// 300ms 是这两者之间的常见折中。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  SearchScope _scope = SearchScope.all;
  SearchHits _hits = SearchHits.empty;
  bool _searching = false;
  String? _error;

  /// 已发起的查询。回来的结果若对不上当前输入就丢掉 ——
  /// 否则慢的那次会覆盖掉快的那次,结果与输入框不一致。
  String _pendingQuery = '';

  /// 问过的词 → 结果。**只留最近几条**(`Map` 保序,满了丢最旧的那条)。
  ///
  /// 「删一个字再打回来」是最常见的改字方式:`ab → a → ab`,而那样会为**同一个
  /// 词**再打一次 `search3` —— 服务器白跑一趟、用户白等一次往返。只记「上一次」
  /// 是不够的(中间那次 `a` 会把它顶掉),所以记一张小表。
  static const _cacheLimit = 8;
  final Map<String, SearchHits> _cache = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      setState(() {
        _hits = SearchHits.empty;
        _searching = false;
        _error = null;
        _pendingQuery = '';
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(query));
  }

  Future<void> _run(String query) async {
    final state = context.read<AppState>();
    final repo = state.repository;
    if (repo == null) {
      setState(() {
        _searching = false;
        _error = '还没有连接服务器';
      });
      return;
    }

    // 这个词刚问过:直接铺那份结果,不再打一次服务器。
    final cached = _cache[query];
    if (cached != null) {
      setState(() {
        _hits = cached;
        _searching = false;
        _error = null;
        _pendingQuery = query;
      });
      return;
    }

    _pendingQuery = query;
    try {
      final hits = await repo.search(query);
      // 输入已经变了,这次结果作废。
      if (!mounted || _pendingQuery != query) return;
      // 满了丢最旧的那条 —— 搜索页是推入的短命页面,记太多只是占内存。
      while (_cache.length >= _cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      _cache[query] = hits;
      setState(() {
        _hits = hits;
        _searching = false;
        _error = null;
      });
    } on MusicSourceException catch (e) {
      if (!mounted || _pendingQuery != query) return;
      setState(() {
        _searching = false;
        _error = e.message;
      });
    }
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();

    // 搜索是**推入的页面**(2026-10-17 起不再是常驻 tab),所以自带头返回;
    // 底部那颗胶囊照旧浮着 —— 从搜索结果里想直接切去音乐库 / 设置,不必先退出去。
    return ImmersiveScaffold(
      accent: context.accent,
      showAmbient: false,
      showNav: true,
      child: Column(
        children: [
          NordicAppBar(
            title: '搜索',
            subtitle: _subtitle(query),
            big: false,
            leading: IconButtonRound(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s4),
            child: _SearchField(
              controller: _controller,
              onChanged: _onChanged,
              onClear: _clear,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s4),
            child: Row(
              children: [
                for (final scope in SearchScope.values)
                  Padding(
                    padding: const EdgeInsets.only(right: NordicSpace.s2),
                    child: NordicChip(
                      label: scope.label,
                      selected: _scope == scope,
                      onTap: () => setState(() => _scope = scope),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body(query)),
        ],
      ),
    );
  }

  String _subtitle(String query) {
    if (query.isEmpty) return '全库检索';
    if (_searching) return '正在搜索';
    final total = _hits.total;
    if (_scope == SearchScope.all) return '$total 条结果';
    final count = switch (_scope) {
      SearchScope.songs => _hits.songs.length,
      SearchScope.albums => _hits.albums.length,
      SearchScope.artists => _hits.artists.length,
      SearchScope.all => total,
    };
    return '${_scope.label} · $count ${_scope.unit}';
  }

  Widget _body(String query) {
    final t = context.nordic;

    if (query.isEmpty) {
      return const EmptyState(
        title: '输入歌名、专辑或艺人',
        detail: '结果会按分类铺开。',
      );
    }
    if (_searching) return const LoadingState(message: '正在搜索');
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: () => _run(query));
    }
    if (_hits.isEmpty) {
      // 与「空库」分开:这里是「搜了但没匹配」,配一句换词建议。
      return EmptyState(
        title: '没有匹配「$query」的内容',
        detail: '换个关键词，或者到设置里重新扫描曲库。',
      );
    }

    bool show(SearchScope scope) =>
        _scope == SearchScope.all || _scope == scope;

    // 只订阅真正读到的两件(命中行高亮);动作(播放全部)走 read ——
    // 整份 watch 会让 play/pause、切歌、时长上报都重建整片结果。
    final (currentId, playing) = context
        .select<PlaybackController, (String?, bool)>(
      (p) => (p.state.song?.id, p.state.playing),
    );
    final repo = context.select<AppState, MusicSource?>(
      (s) => s.repository,
    );

    // 结果整栏走 sliver:搜索可能命中几百条,列表与网格都要**真的懒**
    // (嵌在 ListView 里的 `GridView(shrinkWrap: true)` 会把每一格都建出来)。
    return CustomScrollView(
      slivers: [
        if (show(SearchScope.songs) && _hits.songs.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: '歌曲',
              count: '${_hits.songs.length} 首',
              padding: const EdgeInsets.fromLTRB(
                NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s3),
            ),
          ),
          SliverList.builder(
            itemCount: _hits.songs.length,
            itemBuilder: (context, i) => SongRow(
              song: _hits.songs[i],
              coverUri: (id) => albumCoverUri(repo, id, size: 128),
              playing: _hits.songs[i].id == currentId && playing,
              onTap: () => playTapped(
                context,
                _hits.songs,
                index: i,
                label: _hits.songs[i].title,
              ),
            ),
          ),
        ],
        if (show(SearchScope.albums) && _hits.albums.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: '专辑',
              count: '${_hits.albums.length} 张',
            ),
          ),
          SliverPadding(
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
                (context, index) =>
                    AlbumTile(album: _hits.albums[index], repo: repo),
                childCount: _hits.albums.length,
              ),
            ),
          ),
        ],
        if (show(SearchScope.artists) && _hits.artists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: '艺人',
              count: '${_hits.artists.length} 位',
            ),
          ),
          SliverList.builder(
            itemCount: _hits.artists.length,
            itemBuilder: (context, index) {
              final artist = _hits.artists[index];
              return NordicRow(
                leading: ArtistPlate(artist: artist, size: 52, circular: true),
                title: artist.name,
                subtitle: '${artist.albumCount} 张专辑',
                trailing: Icon(Icons.chevron_right, size: 18, color: t.fg3),
                onTap: () => AppRoutes.openArtist(context, artist.id),
              );
            },
          ),
        ],
        // 选中的分类里没有结果,但别的分类有 —— 说清楚,别让用户
        // 看着空列表以为搜索坏了。
        if (_scope != SearchScope.all && _countInScope == 0)
          SliverToBoxAdapter(
            child: EmptyState(
              title: '「$query」在${_scope.label}里没有结果',
              detail: '换成「全部」看看。',
              topPadding: 40,
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: BottomStack.listInset(context)),
        ),
      ],
    );
  }

  int get _countInScope => switch (_scope) {
        SearchScope.songs => _hits.songs.length,
        SearchScope.albums => _hits.albums.length,
        SearchScope.artists => _hits.artists.length,
        SearchScope.all => _hits.total,
      };
}

/// 搜索输入框 —— `.searchfield`。玻璃底 + 圆形,带清空按钮。
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Container(
      height: 54,
      padding: const EdgeInsets.only(left: 18, right: 8),
      decoration: BoxDecoration(
        color: t.glass4,
        borderRadius: BorderRadius.circular(NordicRadius.full),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 19, color: t.fg3),
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              autofocus: false,
              style: Theme.of(context).textTheme.bodyLarge,
              cursorColor: context.accent.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '歌曲、专辑、艺人',
                hintStyle: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: t.fg4),
              ),
            ),
          ),
          // 空查询时这枚按钮没有意义,收掉它而不是留一个点了没反应的圆。
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: value.text.isEmpty ? 0 : 1,
              child: IgnorePointer(
                ignoring: value.text.isEmpty,
                child: IconButtonRound(
                  icon: Icons.close,
                  size: 38,
                  iconSize: 16,
                  color: t.fg3,
                  onPressed: onClear,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}