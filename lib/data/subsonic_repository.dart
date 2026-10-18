import 'json_list.dart';
import 'models.dart';
import 'subsonic_client.dart';
import 'subsonic_mapper.dart';
import 'subsonic_payload.dart';

/// 音乐库的门面:界面只跟它对话。
///
/// 职责边界:持有 [SubsonicClient](网络 + 线路择优)、调端点、用
/// [SubsonicMapper] 映射成域模型、把失败包成能直接展示成文案的异常。
/// **不做缓存** —— 缓存是状态层的事,混进来会让「刷新」语义变得含糊。
class SubsonicRepository {
  SubsonicRepository(this.client, {this._localCover});

  final SubsonicClient client;

  /// 「这张封面在本机有没有」—— 有就返回磁盘路径。
  ///
  /// 由状态层从下载索引里接过来(见 `state/app_state.dart`)。放在这个类里
  /// 而不是各页面的 `_coverUri` 里,是因为封面地址**只有这一处**在拼:
  /// 十几处调用点各自判断一次,迟早会有一处漏掉,表现成「断网时只有那一个
  /// 角落的封面没了」。
  final String? Function(String coverArtId)? _localCover;

  // ---------------- 详情缓存 ----------------

  /// 详情页的短期缓存(专辑 / 艺人 / 歌单)。
  ///
  /// **为什么放在仓库这一层**:三张详情页各自在 `initState` 里拉一次,
  /// 而「进专辑 → 返回 → 再进同一张」是很常见的路径。每次都打一轮网络
  /// 是白等的,而详情在一两分钟内不会变。缓存只活在进程里(不落盘):
  /// 详情数据比库快照小得多,内存里放几十份不心疼;重启后重新取,
  /// 也顺带保证「服务器上改了东西,重开就能看到」。
  static const _detailTtl = Duration(minutes: 2);

  final Map<String, ({Object value, DateTime at})> _detailCache = {};

  /// 详情缓存最多留这么多份。
  ///
  /// 过期的仅仅在「被再次问到」时才清 —— 一路逛下去(每张专辑都点开看一眼、
  /// 再也不回头)就会一直堆着,而每一份都是几十上百行曲目。
  static const _detailCacheLimit = 48;

  T? _cachedDetail<T>(String key) {
    final entry = _detailCache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > _detailTtl) {
      _detailCache.remove(key);
      return null;
    }
    return entry.value as T;
  }

  void _rememberDetail(String key, Object value) {
    if (_detailCache.length >= _detailCacheLimit) {
      // 先把过期的清掉;还满就把最早放进来的那一份挤出去
      // (详情这一层不需要更精细的 LRU —— 它只是「刚看过的还留着」)。
      final now = DateTime.now();
      _detailCache.removeWhere((_, e) => now.difference(e.at) > _detailTtl);
      if (_detailCache.length >= _detailCacheLimit) {
        _detailCache.remove(_detailCache.keys.first);
      }
    }
    _detailCache[key] = (value: value, at: DateTime.now());
  }

  /// 让某张详情的缓存失效 —— 歌单增删改之后要调,否则再进去还是旧列表。
  void invalidateDetail(String endpoint, String id) {
    _detailCache.remove('$endpoint:$id');
  }

  // ---------------- 音乐库 ----------------

  /// 全部艺人。按首字母分组由服务器给出,这里拉平 ——
  /// 原型里艺人页是「常听 + 全部」两条,分组头用不到。
  Future<List<Artist>> artists() async {
    final body = await client.call('getArtists');
    return SubsonicMapper.artists(SubsonicPayload.artists(body));
  }

  /// 专辑列表。[sort] 决定排序口径,默认按艺人字母序 ——
  /// 与原型「全部专辑」网格的读法一致。
  ///
  /// 就是 [albumList] 里「整库浏览」那一档:**同一套端点、同一套映射**,
  /// 差别只在要多少(网格要 500 条,货架只要一屏)。早先这里是一份照着写的
  /// 副本,两边得手工保持同步。
  Future<List<Album>> albums({AlbumSort sort = AlbumSort.alphabeticalByArtist}) =>
      albumList(sort, size: 500);

  /// 按口径拉一小版专辑 —— 首页那几条货架(最近添加 / 最近播放 / 常听)。
  ///
  /// 与 [albums] 的区别只在**要多少**:整库浏览要 500 条,货架只要一屏 ——
  /// 为了几行横滑去拉五百张专辑的元数据是白花的。
  Future<List<Album>> albumList(AlbumSort sort, {int size = 20}) async {
    final body = await client.call('getAlbumList2', {
      'type': sort.wireName,
      'size': '$size',
    });
    return SubsonicMapper.albums(SubsonicPayload.albums(body));
  }

  /// 专辑详情(含曲目)。
  Future<({Album album, List<Song> songs})> album(String albumId) async {
    final cached = _cachedDetail<({Album album, List<Song> songs})>('album:$albumId');
    if (cached != null) return cached;

    final body = await client.call('getAlbum', {'id': albumId});
    final json = SubsonicPayload.album(body);
    final detail = (
      album: SubsonicMapper.album(json),
      songs: SubsonicMapper.songs(mapList(json['song'])),
    );
    _rememberDetail('album:$albumId', detail);
    return detail;
  }

  /// 艺人详情。`getArtist` 一次给回艺人信息 + 专辑列表 + 曲目列表。
  Future<({Artist artist, List<Album> albums, List<Song> topSongs})> artist(
    String artistId,
  ) async {
    final cached = _cachedDetail<
        ({Artist artist, List<Album> albums, List<Song> topSongs})>(
      'artist:$artistId',
    );
    if (cached != null) return cached;

    final body = await client.call('getArtist', {'id': artistId});
    final json = SubsonicPayload.artist(body);
    final albums = SubsonicMapper.albums(mapList(json['album']));

    // 排序在映射**之前**做 —— playCount 不在域模型里(界面上不显示它),
    // 为了排序把它抬进 [Song] 的公共接口不值得。
    // 缺 playCount 的服务器上所有值都是 0,排序稳定,保持服务器原序。
    // 注意复制一份再排:mapList 返回的是不可变列表,原地 sort 会抛。
    final songJson = mapList(json['song']).toList()
      ..sort((a, b) => _playCount(b).compareTo(_playCount(a)));

    final detail = (
      artist: SubsonicMapper.artist(json),
      albums: albums,
      // **排序之后只映射前五首**:一位大艺人可能有几百首曲子,全映射一遍
      // 就为了留五首,是每次打开艺人页都要付的一笔白账。
      topSongs: SubsonicMapper.songs(songJson.take(5).toList()),
    );
    _rememberDetail('artist:$artistId', detail);
    return detail;
  }

  /// 全部歌曲的**一页**。Subsonic 没有「列全部歌」的端点,用随机歌单凑是错的
  /// (会漏歌)。这里走搜索接口的空查询,拿服务器的字母序全集。
  ///
  /// [offset] 用于翻页 —— 空查询也能带 `songOffset`,这是协议里
  /// 唯一的翻页手段(见 [songsByArtist])。
  ///
  /// **一页 500 是服务器的常见上限**(实测这台 Navidrome 就卡在 500):
  /// 要全集就得一页页取,所以界面上的「全部歌曲」是按需翻页的
  /// (见 `LibraryScreen` 的翻页小节),不是一次取完。
  Future<List<Song>> allSongs({int size = 500, int offset = 0}) async {
    final body = await client.call('search3', {
      'query': '',
      'songCount': '$size',
      if (offset > 0) 'songOffset': '$offset',
      'albumCount': '0',
      'artistCount': '0',
    });
    return SubsonicMapper.search(SubsonicPayload.searchResult(body)).songs;
  }

  /// 一位艺人的全部歌曲。
  ///
  /// Subsonic 没有「按艺人列全部曲目」的端点:`getArtist` 只给几首热门。
  /// 只能翻全集再按艺人筛,并且**要翻到底** —— 取前 500 首当全集,
  /// 会让大库里的用户在「下载这位艺人的歌」时默默少下后半截。
  Future<List<Song>> songsByArtist(Artist artist) async {
    const pageSize = 500;
    // 两万首封顶。真实艺人远远到不了;这是给「筛不出东西时别把库翻穿」
    // 留的止损点。
    const maxPages = 40;

    final songs = <Song>[];
    for (var page = 0; page < maxPages; page++) {
      final batch = await allSongs(size: pageSize, offset: page * pageSize);
      songs.addAll(batch.where((s) => _isBy(s, artist)));
      if (batch.length < pageSize) break;
    }
    return songs;
  }

  /// 一首歌属不属于这位艺人。
  ///
  /// 两个条件都要试:`artistId` 在某些服务器上是专辑艺人(合辑里会指到
  /// 别人),按名字兜一层;反过来名字也可能被服务器改过写法。
  static bool _isBy(Song song, Artist artist) =>
      song.artistId == artist.id || song.artist == artist.name;


  /// 歌单列表。
  Future<List<Playlist>> playlists() async {
    final body = await client.call('getPlaylists');
    return SubsonicMapper.playlists(SubsonicPayload.playlists(body));
  }

  /// 歌单详情(含曲目)。
  Future<({Playlist playlist, List<Song> songs})> playlist(String playlistId) async {
    final cached = _cachedDetail<({Playlist playlist, List<Song> songs})>(
      'playlist:$playlistId',
    );
    if (cached != null) return cached;

    final body = await client.call('getPlaylist', {'id': playlistId});
    final json = SubsonicPayload.playlist(body);
    final detail = (
      playlist: SubsonicMapper.playlist(json),
      songs: SubsonicMapper.songs(mapList(json['entry'])),
    );
    _rememberDetail('playlist:$playlistId', detail);
    return detail;
  }

  // ---------------- 搜索 ----------------

  /// 输入即筛选。服务器侧的 `search3` 支持空查询返回全量,
  /// 所以本地不必再单独维护一份索引。
  Future<SearchHits> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return SearchHits.empty;
    final body = await client.call('search3', {
      'query': trimmed,
      'songCount': '50',
      'albumCount': '50',
      'artistCount': '50',
    });
    return SubsonicMapper.search(SubsonicPayload.searchResult(body));
  }

  // ---------------- 歌词 ----------------

  /// 取歌词。先试 OpenSubsonic 的 `getLyricsBySongId`(带时间轴),
  /// 服务器不认这个端点时退回老的 `getLyrics`(纯文本)。
  ///
  /// 退避是必要的:Navidrome 0.64 支持前者,但别的 Subsonic 实现未必,
  /// 而歌词页在两者下都该能出内容 —— 只是一个能逐句跟随,一个不能。
  Future<Lyrics> lyrics(String songId) async {
    try {
      final body = await client.call('getLyricsBySongId', {'id': songId});
      final lyrics = SubsonicMapper.lyrics(SubsonicPayload.structuredLyrics(body));
      if (!lyrics.isEmpty) return lyrics;
    } on SubsonicException {
      // 端点不存在(错误码 0 / 70)或服务器不支持 —— 落到下面的老接口。
    }

    try {
      final body = await client.call('getLyrics', {
        'artist': '',
        'title': '',
        // 老接口按「艺人 + 标题」查,但很多实现接受空串返回任意匹配;
        // 真正的取法是下面这次带 id 的调用(部分实现扩展了 id 参数)。
        'id': songId,
      });
      return SubsonicMapper.plainLyrics(SubsonicPayload.lyrics(body));
    } on SubsonicException {
      // 歌词确实没有,不是错误 —— 歌词页显示「这首歌还没有歌词」。
      return Lyrics.empty;
    }
  }

  // ---------------- 收藏 ----------------

  Future<void> setStarred({
    String? songId,
    String? albumId,
    String? artistId,
    required bool starred,
  }) async {
    assert(
      songId != null || albumId != null || artistId != null,
      'star / unstar 至少要给一个 id',
    );
    await client.call(starred ? 'star' : 'unstar', {
      'id': ?songId,
      'albumId': ?albumId,
      'artistId': ?artistId,
    });
  }

  /// 收藏内容。界面用它在设置页显示「我的收藏」入口计数。
  Future<SearchHits> starred() async {
    final body = await client.call('getStarred2');
    final json = SubsonicPayload.starred(body);
    return SearchHits(
      songs: SubsonicMapper.songs(mapList(json['song'])),
      albums: SubsonicMapper.albums(mapList(json['album'])),
      artists: SubsonicMapper.artists(mapList(json['artist'])),
    );
  }

  // ---------------- 播放地址 ----------------

  /// 封面图 URL。**本机下过就直接给本机文件** —— 断网时封面不该消失,
  /// 那是「下载了也不能离线用」的观感。
  ///
  /// 否则必须带鉴权参数 —— 图片缓存与音频解码器是绕过 `SubsonicClient`
  /// 直接发请求的,不签名会被服务器拒掉。
  ///
  /// [size] 由服务器负责缩放;传原始尺寸会把 4000px 的原图拉进内存。
  /// 本机那份不再按 [size] 缩放:它是下载时按 1024 存的,为显示尺寸现解码
  /// 一张已经在磁盘上的图不值当。
  Uri coverUri(String coverArtId, {int size = 512}) {
    final local = _localCover?.call(coverArtId);
    if (local != null) return Uri.file(local);

    // 本机那份**不进备忘录**:它跟着下载状态变,记下来就不认新下的了。
    final route = _activeRouteOrThrow;
    return _rememberUri('cover|${route.url}|$coverArtId|$size', () =>
        SubsonicClient.buildUri(
          route,
          'getCoverArt',
          {'id': coverArtId, 'size': '$size'},
          client.auth,
        ));
  }

  /// 音频流 URL。转码档位在这里落成 `maxBitRate` / `format` 参数;
  /// 原音档不传参数,直接取原文件。
  Uri streamUri(String songId, {int? maxBitRate, String? format}) {
    final route = _activeRouteOrThrow;
    return _rememberUri('stream|${route.url}|$songId|$maxBitRate|$format', () =>
        SubsonicClient.buildUri(
          route,
          'stream',
          {
            'id': songId,
            'maxBitRate': ?maxBitRate?.toString(),
            'format': ?format,
          },
          client.auth,
        ));
  }

  // ---------------- 地址的短期备忘录 ----------------

  /// 拼好的地址按「线路 + 参数」记一份。
  ///
  /// **为什么值得记**:一次 `setQueue` 会把整条队列的播放源都拼出来
  /// (见 `audio_handler.dart` 的 `_sourceFor`),上千首的队列就是上千次
  /// 「新生成盐 + MD5」,而其中绝大多数地址到播完也不会被请求一次;同一张专辑
  /// 底下的几十首歌更是共用同一个封面地址。命中即复用,省下的是那几千次哈希。
  ///
  /// **盐的口径说清楚**:命中时复用同一条 URL,连同它那一份盐。盐在这里的作用是
  /// 「不把密码送上网」,而不是一次性票据(服务器不回收盐);同一张封面、同一首歌
  /// 在同一次会话里重复取址本来也不带额外信息 —— 要的只是「别为它算一千遍」。
  /// 未命中时照旧**当场新生成**一个盐。
  ///
  /// 键里带线路的 **url** 而不只是 id:某条线路的地址可以被改掉而 id 不变,
  /// 只按 id 作键会把改动前的那条 URL 一直喂回去(表现是「改了地址还走旧的」)。
  /// 换服务器 / 换账号会重建整个仓库(见 `app_state.attachRepository`),
  /// 备忘录跟着一起换新。
  static const _uriMemoLimit = 2048;
  final Map<String, Uri> _uriMemo = {};

  Uri _rememberUri(String key, Uri Function() build) {
    final hit = _uriMemo[key];
    if (hit != null) return hit;
    final uri = build();
    // 满了就整体清掉:这是备忘录,不是缓存 —— 清空只是多算一遍,
    // 而它省下的是队列装载那一下的几千次哈希。
    if (_uriMemo.length >= _uriMemoLimit) _uriMemo.clear();
    _uriMemo[key] = uri;
    return uri;
  }

  /// 下载用的地址:**一律取原文件,不吃转码档**。
  ///
  /// 下载的卖点是「离线也能听」,那就该存服务器上真正的那个文件。
  /// 跟着当前档位存一份转码过的,既对不起界面上「下载到本机(FLAC)」
  /// 那句话,也会让用户在换档位时才发现本地这首比在线的还差。
  Uri downloadUri(String songId) => streamUri(songId);

  ServerRoute get _activeRouteOrThrow {
    final route = client.activeRoute;
    if (route == null) {
      throw const SubsonicException('还没有配置任何服务器线路');
    }
    return route;
  }

  // ---------------- 歌单写操作 ----------------

  /// 建一个空歌单。返回新建的歌单。
  ///
  /// `createPlaylist` 在部分实现里会**返回空响应体**(而不是新建的对象),
  /// 那种情况下退回去 `getPlaylists` 里按名字找最新的一条 —— 建完却拿不到
  /// 对象会让调用方以为失败,而服务器上其实已经有了。
  Future<Playlist> createPlaylist(String name, {List<String> songIds = const []}) async {
    final body = await client.call('createPlaylist', {
      'name': name,
      if (songIds.isNotEmpty) 'songId': songIds.join(','),
    });

    if (SubsonicPayload.hasPlaylist(body)) {
      return SubsonicMapper.playlist(SubsonicPayload.playlist(body));
    }

    final all = await playlists();
    final match = all.where((p) => p.name == name).toList();
    if (match.isEmpty) {
      throw SubsonicException('歌单「$name」创建后没有返回,请下拉刷新看看');
    }
    return match.first;
  }

  /// 把一首歌加进歌单。
  Future<void> addToPlaylist(String playlistId, String songId) async {
    await client.call('updatePlaylist', {
      'playlistId': playlistId,
      'songIdToAdd': songId,
    });
    invalidateDetail('playlist', playlistId);
  }

  /// 从歌单里移除某一首。
  ///
  /// **按位置移除**:协议给的是 `songIndexToRemove`,索引指服务器那份列表里的
  /// 位置。同一首歌在歌单里出现两次时,「移除哪一次」只有位置说得清,
  /// 所以这里收位置而不是歌曲 id。
  Future<void> removeFromPlaylist(String playlistId, int index) async {
    await client.call('updatePlaylist', {
      'playlistId': playlistId,
      'songIndexToRemove': '$index',
    });
    invalidateDetail('playlist', playlistId);
  }

  /// 重命名歌单。
  Future<void> renamePlaylist(String playlistId, String name) async {
    await client.call('updatePlaylist', {
      'playlistId': playlistId,
      'name': name,
    });
    invalidateDetail('playlist', playlistId);
  }

  /// 删除歌单。
  Future<void> deletePlaylist(String playlistId) async {
    await client.call('deletePlaylist', {'id': playlistId});
    invalidateDetail('playlist', playlistId);
  }
}

/// 专辑列表的排序口径,对应 `getAlbumList2` 的 `type`。
enum AlbumSort {
  alphabeticalByName('alphabeticalByName', '名称'),
  alphabeticalByArtist('alphabeticalByArtist', '艺人'),
  newest('newest', '最近添加'),
  recent('recent', '最近播放'),
  frequent('frequent', '常听'),
  random('random', '随机');

  const AlbumSort(this.wireName, this.label);

  final String wireName;
  final String label;

  /// 存的是**名字**而不是序号(见 ConfigStore.saveAlbumSort)。
  static AlbumSort byName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => AlbumSort.alphabeticalByArtist,
      );
}

int _playCount(Map<String, dynamic> songJson) {
  final count = songJson['playCount'];
  return count is num ? count.toInt() : 0;
}

