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
  SubsonicRepository(this.client);

  final SubsonicClient client;

  // ---------------- 音乐库 ----------------

  /// 全部艺人。按首字母分组由服务器给出,这里拉平 ——
  /// 原型里艺人页是「常听 + 全部」两条,分组头用不到。
  Future<List<Artist>> artists() async {
    final body = await client.call('getArtists');
    return SubsonicMapper.artists(SubsonicPayload.artists(body));
  }

  /// 专辑列表。[sort] 决定排序口径,默认按艺人字母序 ——
  /// 与原型「全部专辑」网格的读法一致。
  Future<List<Album>> albums({AlbumSort sort = AlbumSort.alphabeticalByArtist}) async {
    final body = await client.call('getAlbumList2', {
      'type': sort.wireName,
      'size': '500',
    });
    return SubsonicMapper.albums(SubsonicPayload.albums(body));
  }

  /// 最近添加。用于音乐库首页的「最近添加」货架。
  Future<List<Album>> recentlyAdded({int size = 20}) async {
    final body = await client.call('getAlbumList2', {
      'type': 'newest',
      'size': '$size',
    });
    return SubsonicMapper.albums(SubsonicPayload.albums(body));
  }

  /// 专辑详情(含曲目)。
  Future<({Album album, List<Song> songs})> album(String albumId) async {
    final body = await client.call('getAlbum', {'id': albumId});
    final json = SubsonicPayload.album(body);
    return (
      album: SubsonicMapper.album(json),
      songs: SubsonicMapper.songs(_mapList(json['song'])),
    );
  }

  /// 艺人详情。`getArtist` 一次给回艺人信息 + 专辑列表 + 曲目列表。
  Future<({Artist artist, List<Album> albums, List<Song> topSongs})> artist(
    String artistId,
  ) async {
    final body = await client.call('getArtist', {'id': artistId});
    final json = SubsonicPayload.artist(body);
    final albums = SubsonicMapper.albums(_mapList(json['album']));

    // 排序在映射**之前**做 —— playCount 不在域模型里(界面上不显示它),
    // 为了排序把它抬进 [Song] 的公共接口不值得。
    // 缺 playCount 的服务器上所有值都是 0,排序稳定,保持服务器原序。
    // 注意复制一份再排:_mapList 返回的是不可变列表,原地 sort 会抛。
    final songJson = _mapList(json['song']).toList()
      ..sort((a, b) => _playCount(b).compareTo(_playCount(a)));

    return (
      artist: SubsonicMapper.artist(json),
      albums: albums,
      topSongs: SubsonicMapper.songs(songJson).take(5).toList(),
    );
  }

  /// 全部歌曲。Subsonic 没有「列全部歌」的端点,用随机歌单凑是错的
  /// (会漏歌)。这里走搜索接口的空查询,拿服务器的字母序全集。
  Future<List<Song>> allSongs({int size = 500}) async {
    final body = await client.call('search3', {
      'query': '',
      'songCount': '$size',
      'albumCount': '0',
      'artistCount': '0',
    });
    return SubsonicMapper.search(SubsonicPayload.searchResult(body)).songs;
  }

  /// 歌单列表。
  Future<List<Playlist>> playlists() async {
    final body = await client.call('getPlaylists');
    return SubsonicMapper.playlists(SubsonicPayload.playlists(body));
  }

  /// 歌单详情(含曲目)。
  Future<({Playlist playlist, List<Song> songs})> playlist(String playlistId) async {
    final body = await client.call('getPlaylist', {'id': playlistId});
    final json = SubsonicPayload.playlist(body);
    return (
      playlist: SubsonicMapper.playlist(json),
      songs: SubsonicMapper.songs(_mapList(json['entry'])),
    );
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
      songs: SubsonicMapper.songs(_mapList(json['song'])),
      albums: SubsonicMapper.albums(_mapList(json['album'])),
      artists: SubsonicMapper.artists(_mapList(json['artist'])),
    );
  }

  // ---------------- 播放地址 ----------------

  /// 封面图 URL。**必须带鉴权参数** —— 图片缓存与音频解码器是绕过
  /// `SubsonicClient` 直接发请求的,不签名会被服务器拒掉。
  ///
  /// [size] 由服务器负责缩放;传原始尺寸会把 4000px 的原图拉进内存。
  Uri coverUri(String coverArtId, {int size = 512}) => SubsonicClient.buildUri(
        _activeRouteOrThrow,
        'getCoverArt',
        {'id': coverArtId, 'size': '$size'},
        client.auth,
      );

  /// 音频流 URL。转码档位在这里落成 `maxBitRate` / `format` 参数;
  /// 原音档不传参数,直接取原文件。
  Uri streamUri(String songId, {int? maxBitRate, String? format}) =>
      SubsonicClient.buildUri(
        _activeRouteOrThrow,
        'stream',
        {
          'id': songId,
          'maxBitRate': ?maxBitRate?.toString(),
          'format': ?format,
        },
        client.auth,
      );

  ServerRoute get _activeRouteOrThrow {
    final route = client.activeRoute;
    if (route == null) {
      throw const SubsonicException('还没有配置任何服务器线路');
    }
    return route;
  }

  /// 收藏状态查询要按 id 找 —— Subsonic 没有「这首歌收藏了吗」的单点查询,
  /// 只能拉全量收藏名单在本地比对。
  Future<Set<String>> starredSongIds() async =>
      (await starred()).songs.map((s) => s.id).toSet();

  Future<Set<String>> starredAlbumIds() async =>
      (await starred()).albums.map((a) => a.id).toSet();

  Future<Set<String>> starredArtistIds() async =>
      (await starred()).artists.map((a) => a.id).toSet();

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
  Future<void> addToPlaylist(String playlistId, String songId) =>
      client.call('updatePlaylist', {
        'playlistId': playlistId,
        'songIdToAdd': songId,
      });

  /// 重命名歌单。
  Future<void> renamePlaylist(String playlistId, String name) =>
      client.call('updatePlaylist', {
        'playlistId': playlistId,
        'name': name,
      });

  /// 删除歌单。
  Future<void> deletePlaylist(String playlistId) =>
      client.call('deletePlaylist', {'id': playlistId});
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
}

int _playCount(Map<String, dynamic> songJson) {
  final count = songJson['playCount'];
  return count is num ? count.toInt() : 0;
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}