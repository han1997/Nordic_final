import 'models.dart';
import 'server_route.dart';
import 'sorting.dart';

// 音源抽象层:界面与状态层只跟 [MusicSource] 对话,不认任何具体协议。
//
// 现在只有一个实现([SubsonicRepository],讲 Subsonic 协议),所以这一层
// 眼下不省谁的事 —— 它的价值在于**接缝已经在了**:飞牛音乐那份协议拿到之后,
// 写一个 implements MusicSource 的类、在 `server_config.dart` 的 sourceFor
// 里加一支,别处不用再动。

/// 服务器上那次曲库扫描的状态(Subsonic 的 `getScanStatus`)。
///
/// [count] 是**服务器说它库里有几首**(扫描中时是这一趟已经数到的数),
/// [lastScan] 是上一次扫完的时刻。三个字段各自可能缺 —— 有的实现只报其中一两件,
/// 缺的那件给 null,**界面照实不印**,不编一个 0 出来。
typedef ScanStatus = ({bool scanning, int? count, DateTime? lastScan});

/// 一条线路的可用性、择优与测速 —— 「**怎么连**」。
///
/// 与 [MusicSource] 分开是有意的:线路(多地址、择优、故障切换、锁定)是
/// 传输层的事,与「这台服务器上有什么音乐」无关。合成一个接口的话,
/// 每个音源都得实现一遍线路表,哪怕它根本没有多线路这回事。
///
/// [SubsonicClient] 的名字与签名本来就是这一组,所以它 `implements` 这个
/// 接口是零改名的。
abstract interface class ServerConnection {
  /// 手上的线路表(只读快照)。
  List<ServerRoute> get routes;

  /// 换一份线路表 —— 增删 / 改名 / 锁定都走这里。
  void setRoutes(List<ServerRoute> routes);

  /// 当前生效的那条:用户锁定 > 实测最快 > 列表首条。
  ServerRoute? get activeRoute;

  /// 是否按延迟自动择优。关掉之后只走手动锁定的那条。
  bool get autoRoute;

  set autoRoute(bool value);

  /// 最近一次测速结果,按线路 id。
  Map<String, RoutePing> get pings;

  /// 批量测速。单条失败不影响其它条。
  Future<Map<String, RoutePing>> pingAll();

  /// 单条线路测速。
  Future<RoutePing> pingRoute(ServerRoute route);
}

/// 一个音乐库 —— 「**有什么**」,以及怎么拿。
///
/// 界面与状态层只依赖它。方法的返回类型是 `models.dart` 里那些域模型,
/// 它们本来就与协议无关(映射发生在各实现内部)。
///
/// **失败一律抛 [MusicSourceException]**(或其子类)—— 界面按这个基类判,
/// 不认任何具体协议的错误类型;否则换一个音源,那些 catch 会一条都接不住。
abstract interface class MusicSource {
  /// 这一台服务器的线路(见 [ServerConnection])。
  ServerConnection get connection;

  // ---------------- 音乐库 ----------------

  Future<List<Artist>> artists();

  Future<List<Album>> albums({AlbumSort sort = AlbumSort.alphabeticalByArtist});

  Future<List<Album>> albumList(AlbumSort sort, {int size = 20});

  Future<({Album album, List<Song> songs})> album(String albumId);

  Future<({Artist artist, List<Album> albums, List<Song> topSongs})> artist(
    String artistId,
  );

  Future<List<Song>> allSongs({int size = 500, int offset = 0});

  /// 一位艺人的全部歌曲。**要翻页找齐** —— 详情接口只给几首热门。
  Future<List<Song>> songsByArtist(Artist artist);

  Future<List<Playlist>> playlists();

  Future<({Playlist playlist, List<Song> songs})> playlist(String playlistId);

  // ---------------- 搜索与歌词 ----------------

  Future<SearchHits> search(String query);

  Future<Lyrics> lyrics(String songId);

  // ---------------- 收藏 ----------------

  Future<void> setStarred({
    String? songId,
    String? albumId,
    String? artistId,
    required bool starred,
  });

  /// 收藏内容。界面用它在设置页显示「我的收藏」入口计数。
  Future<SearchHits> starred();

  // ---------------- 播放状态 ----------------

  /// 播放状态回报 —— Subsonic 的 `scrobble`。
  ///
  /// [submission] 为 false 是「正在播放」(**不计数**),为 true 是「听过一次」。
  /// 谁来报、什么时候报由 `playback/scrobble.dart` 的 `ScrobbleTracker` 判,
  /// 这一层只管把它落成一个请求。
  ///
  /// **本机不另存一份播放记录**:这条记录的去处只有服务器(播放次数 /
  /// 最近播放 /「正在播放」那一栏)。所以实现**必须容忍失败** —— 离线时这条
  /// 请求发不出去,那一次就不计入服务器统计,而播放本身不该受影响。
  ///
  /// [at] 是「听过一次」那一刻;不给就是服务器收到的时间。
  Future<void> reportPlayback(
    String songId, {
    required bool submission,
    DateTime? at,
  });

  // ---------------- 播放队列 ----------------

  /// 把队列与进度写回服务器 —— Subsonic 的 `savePlayQueue`。
  ///
  /// 用途只有一个:**换设备接着听**。另一台设备(或另一个客户端)读它,
  /// 就能把队列摆在同一个位置。
  ///
  /// [songs] 只该给**当前曲目前后的一段**(调用方负责截断,见
  /// `playback/play_queue_sync.dart`)—— 这是一条 GET 查询串,几千个 id
  /// 拼出来的 URL 会被反向代理挡下。[currentId] 必须是 [songs] 里的一首。
  Future<void> savePlayQueue({
    required List<Song> songs,
    String? currentId,
    Duration position = Duration.zero,
  });

  /// 读回服务器上的队列。**没有 / 不支持就返回 null** ——
  /// 这是可选能力,不能因为对面不实现就把启动路径拖红。
  ///
  /// [changed] 是**服务器记的**「上一次改动时刻」:我们自己写的那一份也会让它变,
  /// 所以界面要拿它跟本机记着的那个比,才分得清「这是别的设备留下的」。
  /// 服务器从没存过时给的是零时间 —— 那种情况一律当 null(见实现)。
  Future<
      ({
        List<Song> songs,
        String? currentId,
        Duration position,
        DateTime? changed,
      })?> playQueue();

  // ---------------- 曲库扫描 ----------------

  /// 服务器上那次扫描的状态 —— Subsonic 的 `getScanStatus`。
  Future<ScanStatus> scanStatus();

  /// 让服务器**现在扫一遍自己的曲库** —— `startScan`,返回它报的新状态。
  ///
  /// 这是服务器端的活(扫的是它自己的盘),而它**要管理员权限**:非管理员账号
  /// 会拿到服务器的拒绝 —— 实现如实抛出,界面把服务器那句话转述出来。
  Future<ScanStatus> startScan();

  // ---------------- 地址 ----------------

  /// 封面地址。实现**应当本机优先** —— 下过的封面断网也要看得见。
  Uri coverUri(String coverArtId, {int size = 512});

  /// 播放地址。[maxBitRate] / [format] 为转码档;原音档两者都空。
  Uri streamUri(String songId, {int? maxBitRate, String? format});

  /// 下载地址(要的是**原文件**,不转码)。
  Uri downloadUri(String songId);

  // ---------------- 歌单写 ----------------

  Future<Playlist> createPlaylist(String name, {List<String> songIds = const []});

  Future<void> addToPlaylist(String playlistId, String songId);

  Future<void> removeFromPlaylist(String playlistId, int index);

  Future<void> renamePlaylist(String playlistId, String name);

  Future<void> deletePlaylist(String playlistId);
}

/// 音源给出的失败。**界面只认这一层**。
///
/// 各实现抛自己的子类(如 [SubsonicException]);状态层与界面里那些
/// `on MusicSourceException catch` 于是对任何音源都成立,不会因为换了一个
/// 实现就静默漏掉错误。
///
/// 这是一个**具体类**而不是抽象接口:应用层自己也要造失败(「还没有连接
/// 服务器」「音乐库里没有这位艺人的歌」),那些与协议无关,直接抛它即可。
class MusicSourceException implements Exception {
  const MusicSourceException(this.message);

  /// 能直接展示给用户的一句话。
  final String message;

  /// 凭据不对 —— 界面据此引导去设置页,而不是「重试一下可能就好了」。
  ///
  /// 基类默认「不是」;**是不是由各实现自己判**(如 [SubsonicException] 按
  /// 服务器的错误码)。应用层自己造的那两处(「还没有连接服务器」等)也落在
  /// 这个默认上。
  bool get isAuthFailure => false;

  /// 网络层失败(超时、DNS、连接被拒)—— 据此判断「这条线路不行,换一条」。
  /// 默认同上,由实现判。
  bool get isNetworkFailure => false;

  @override
  String toString() => 'MusicSourceException: $message';
}