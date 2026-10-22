import 'json_list.dart';
import 'models.dart';
import 'music_source.dart';
import 'sorting.dart';
import 'subsonic_client.dart';
import 'subsonic_mapper.dart';
import 'subsonic_payload.dart';

// 专辑排序口径 [AlbumSort] 搬去了 `sorting.dart`(它是排序口径,不是协议)。
// 这里再导出一次,让原先从本文件拿它的地方零改动。
// **用 `show` 收窄** —— 不然整个 `sorting.dart`(SongSort / sortSongs /
// mergeSongPage…)都会透传出去,原先直连那些名字的文件会突然多出一条
// `unnecessary_import`。只透出真正从这里被拿走的那个。
// (`export` 不把名字带进本文件的 scope,所以上面那句 import 不能省。)
export 'sorting.dart' show AlbumSort;

/// 音乐库的门面:界面只跟它对话。
///
/// 职责边界:持有 [SubsonicClient](网络 + 线路择优)、调端点、用
/// [SubsonicMapper] 映射成域模型、把失败包成能直接展示成文案的异常。
/// **不做缓存** —— 缓存是状态层的事,混进来会让「刷新」语义变得含糊。
class SubsonicRepository implements MusicSource {
  SubsonicRepository(this.client, {this._localCover});

  final SubsonicClient client;

  /// 线路这一层(见 [ServerConnection])—— 客户端本来就是干这个的,
  /// 直接把它交出去,不另包一层。
  @override
  ServerConnection get connection => client;

  /// 「这张封面在本机有没有」—— 有就返回磁盘路径。
  ///
  /// 由状态层从下载索引里接过来(见 `state/app_state.dart`)。放在这个类里
  /// 而不是界面那一层,是因为封面地址**只有这一处**在拼:界面那边只经
  /// `ui/widgets/cover.dart` 的 `albumCoverUri` 一份包装过来 —— 判断散在
  /// 各写一遍的十几处的话,迟早会有一处漏掉,表现成「断网时只有那一个
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
  @override
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
  @override
  Future<List<Album>> albums({AlbumSort sort = AlbumSort.alphabeticalByArtist}) =>
      albumList(sort, size: 500);

  /// 按口径拉一小版专辑 —— 首页那几条货架(最近添加 / 最近播放 / 常听)。
  ///
  /// 与 [albums] 的区别只在**要多少**:整库浏览要 500 条,货架只要一屏 ——
  /// 为了几行横滑去拉五百张专辑的元数据是白花的。
  @override
  Future<List<Album>> albumList(AlbumSort sort, {int size = 20}) async {
    final body = await client.call('getAlbumList2', {
      'type': sort.wireName,
      'size': '$size',
    });
    return SubsonicMapper.albums(SubsonicPayload.albums(body));
  }

  /// 专辑详情(含曲目)。
  @override
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
  @override
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
    // 先筛掉没有 id 的条目 —— 排序那一步只是挑前五首,但映射那一头要的是
    // 「这一条读得出来」(见 `SubsonicMapper.hasIdentity`)。
    final songJson = mapList(json['song'])
        .where(SubsonicMapper.hasIdentity)
        .toList()
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
  /// **一页 500 不是服务器的上限** —— 那是早先的误判(旧注释写「实测这台
  /// Navidrome 就卡在 500」,换成 `songCount=1000/2000/20000` 都返回全量,
  /// 见 `docs/performance.md` 的翻页小节)。500 只是一个够用的**页宽**:要全集
  /// 仍得一页页取,所以界面上的「全部歌曲」是按需翻页的(见 `LibraryScreen`
  /// 的翻页小节),不是一次取完。
  @override
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
  @override
  Future<List<Song>> songsByArtist(Artist artist) async {
    const pageSize = 500;
    // 两万首封顶。真实艺人远远到不了;这是给「筛不出东西时别把库翻穿」
    // 留的止损点。
    const maxPages = 40;

    final songs = <Song>[];
    for (var page = 0; page < maxPages; page++) {
      final batch = await allSongs(size: pageSize, offset: page * pageSize);
      songs.addAll(batch.where((s) => _isBy(s, artist)));
      // **空页才算到底**:服务器可能把 `search3` 卡在比这个更低的条数上
      // (常见的是 500),按「不满一页」判会当场收摊 —— 大库里的用户点
      // 「下载这位艺人的全部歌曲」就会默默少下后半截。代价是每个艺人
      // 多一趟空请求(翻页本来就是按需的活)。
      if (batch.isEmpty) break;
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
  @override
  Future<List<Playlist>> playlists() async {
    final body = await client.call('getPlaylists');
    return SubsonicMapper.playlists(SubsonicPayload.playlists(body));
  }

  /// 歌单详情(含曲目)。
  @override
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
  @override
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
  @override
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

  @override
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
  @override
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
  @override
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
  @override
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
  @override
  Uri downloadUri(String songId) => streamUri(songId);

  ServerRoute get _activeRouteOrThrow {
    final route = client.activeRoute;
    if (route == null) {
      throw const SubsonicException('还没有配置任何服务器线路');
    }
    return route;
  }

  // ---------------- 播放状态 ----------------

  /// 播放状态回报 —— `scrobble`。
  ///
  /// 参数只有三件:`id` 必有;`submission` 用**字符串** `true` / `false`
  /// (Subsonic 那边就是这么收的,`'0'` 一律当成「正在播放」);
  /// `time` 只在「听过一次」时给 —— 那是**那一刻**的墙上时间(毫秒),
  /// 而不是「服务器收到的时间」:请求可能排了一会儿队才发出去。
  @override
  Future<void> reportPlayback(
    String songId, {
    required bool submission,
    DateTime? at,
  }) async {
    await client.call('scrobble', {
      'id': songId,
      'submission': submission ? 'true' : 'false',
      if (submission && at != null)
        'time': '${at.millisecondsSinceEpoch}',
    });
  }

  // ---------------- 播放队列 ----------------

  /// 把队列与进度写回服务器。`id` 这个参数**重复出现**若干次(协议就是这么定的),
  /// 所以不能塞进 `Map<String, String>` —— 见 [SubsonicClient.callMulti]。
  ///
  /// 队列长的时候调用方会截断(见 `play_queue_sync.dart`):这是一条 GET 查询串。
  @override
  Future<void> savePlayQueue({
    required List<Song> songs,
    String? currentId,
    Duration position = Duration.zero,
  }) async {
    if (songs.isEmpty) return;
    await client.callMulti('savePlayQueue', {
      'id': [for (final s in songs) s.id],
      // 当前曲目**必须在这份名单里**(服务器按 id 找它);调用方负责截断时保住它。
      if (currentId != null) 'current': [currentId],
      'position': ['${position.inMilliseconds}'],
    });
  }

  /// 读回服务器上的队列。
  ///
  /// **不实现这个端点的服务器一律当「没有队列」**:它是个可选能力,
  /// 抛出去只会让启动路径上多一条没人处理的失败(界面上什么也做不了)。
  /// 网络错误同样吞掉 —— 冷启动时服务器不通是常态,而缓存里那份库照旧能看。
  @override
  Future<
      ({
        List<Song> songs,
        String? currentId,
        Duration position,
        DateTime? changed,
      })?> playQueue() async {
    final Map<String, dynamic> body;
    try {
      body = await client.call('getPlayQueue');
    } on MusicSourceException {
      return null;
    }
    return SubsonicPayload.playQueue(body);
  }

  // ---------------- 曲库扫描 ----------------

  @override
  Future<ScanStatus> scanStatus() async =>
      SubsonicPayload.scanStatus(await client.call('getScanStatus'));

  /// 让服务器现在扫一遍。**要管理员权限** —— 非管理员会拿到服务器的拒绝
  /// (Navidrome 回「not authorized」),这里如实抛出,界面把那一句转述出来。
  ///
  /// 返回的是服务器报的**新状态**(它已经在扫了,`scanning` 为真)。
  @override
  Future<ScanStatus> startScan() async =>
      SubsonicPayload.scanStatus(await client.call('startScan'));

  // ---------------- 歌单写操作 ----------------

  /// 建一个空歌单。返回新建的歌单。
  ///
  /// `createPlaylist` 在部分实现里会**返回空响应体**(而不是新建的对象),
  /// 那种情况下退回去 `getPlaylists` 里按名字找最新的一条 —— 建完却拿不到
  /// 对象会让调用方以为失败,而服务器上其实已经有了。
  @override
  Future<Playlist> createPlaylist(String name, {List<String> songIds = const []}) async {
    // 先记下手上这份名单:服务器**不返回新建对象**时(有的实现就是空响应体),
    // 建完之后要靠「哪一条是新的」认出来。同名歌单早就存在是常事 ——
    // 按名字取第一条可能取回一条旧歌单,调用方于是以为新建成功、还跳进了旧的那条。
    // 代价是建歌单这个动作多一趟 `getPlaylists`(用户点一次的事,不是热路径)。
    final before = {for (final p in await playlists()) p.id};

    final body = await client.call('createPlaylist', {
      'name': name,
      if (songIds.isNotEmpty) 'songId': songIds.join(','),
    });

    if (SubsonicPayload.hasPlaylist(body)) {
      return SubsonicMapper.playlist(SubsonicPayload.playlist(body));
    }

    final fresh = [
      for (final p in await playlists())
        if (!before.contains(p.id) && p.name == name) p,
    ];
    if (fresh.isEmpty) {
      throw SubsonicException('歌单「$name」创建后没有返回，请下拉刷新看看');
    }
    return fresh.first;
  }

  /// 把一首歌加进歌单。
  @override
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
  @override
  Future<void> removeFromPlaylist(String playlistId, int index) async {
    await client.call('updatePlaylist', {
      'playlistId': playlistId,
      'songIndexToRemove': '$index',
    });
    invalidateDetail('playlist', playlistId);
  }

  /// 重命名歌单。
  @override
  Future<void> renamePlaylist(String playlistId, String name) async {
    await client.call('updatePlaylist', {
      'playlistId': playlistId,
      'name': name,
    });
    invalidateDetail('playlist', playlistId);
  }

  /// 删除歌单。
  @override
  Future<void> deletePlaylist(String playlistId) async {
    await client.call('deletePlaylist', {'id': playlistId});
    invalidateDetail('playlist', playlistId);
  }
}

int _playCount(Map<String, dynamic> songJson) {
  final count = songJson['playCount'];
  return count is num ? count.toInt() : 0;
}

