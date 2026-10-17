import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/download_manager.dart';
import '../data/library_cache.dart';
import '../data/media_cache.dart';
import '../data/models.dart';
import '../data/server_config.dart';
import '../data/subsonic_client.dart';
import '../data/subsonic_payload.dart';
import '../data/sorting.dart';
import '../data/subsonic_repository.dart';
import '../playback/quality.dart';

/// 加载态。三态而非「数据 + isLoading 标志」—— 后者容易写出
/// 「加载中同时显示空态」的界面(见项目里「不造假空态」的约定)。
enum LoadPhase { idle, loading, ready, failed }

/// 应用级状态:服务器连接、音乐库数据、界面偏好。
///
/// 界面读它,不直接碰 [SubsonicRepository] —— 这样「连不上」「还没配服务器」
/// 这类全局状态有唯一定义处,不必每个屏各自判断。
class AppState extends ChangeNotifier {
  AppState({
    required this.configStore,
    required this.credentialStore,
    required this.quality,
    required this.downloadManager,
    required this.libraryCache,
    required this.mediaCache,
    this._dio,
  }) {
    // 下载器的状态变化要能被界面看到,而界面只订阅 [AppState] 一个对象 ——
    // 这里把它接进来,省掉「下载页要多订阅一个 provider」这件事。
    downloadManager.addListener(notifyListeners);
    // 缓存同理:占用与上限都在设置页显示,淘汰又是播放层在后台触发的
    // (听一首歌就可能腾出几百 MB),所以界面得跟着动。
    mediaCache.addListener(notifyListeners);
  }

  final ConfigStore configStore;
  final CredentialStore credentialStore;
  final QualityController quality;
  final DownloadManager downloadManager;

  /// 音乐库快照的本机缓存(见 `data/library_cache.dart`)。
  final LibraryCache libraryCache;

  /// 「听过的歌留一份」的音频缓存(见 `data/media_cache.dart`)。
  ///
  /// 与 [downloadManager] 是两件事:**下载**是用户点名要的,不会被自动删;
  /// **缓存**是播放时顺手留的,上限一到就按最久没听淘汰。
  final MediaCache mediaCache;

  /// 建客户端时用的 HTTP 客户端。生产走默认(见 [clientFor]),
  /// 测试塞一个假 Dio 进来 —— 写歌单这类操作要验的是「发了什么、本地跟着变了吗」。
  final Dio? _dio;

  SubsonicRepository? _repository;
  SubsonicRepository? get repository => _repository;

  ServerConfig? _server;
  ServerConfig? get server => _server;

  bool get hasServer => _server != null && _repository != null;

  // ---------------- 连接 ----------------

  /// 用已存的配置接管仓库(启动时调用)。
  ///
  /// 与 [connect] 分开:启动时配置已经落盘,不需要再写一遍,
  /// 也不该因为写盘失败而连不上。
  void adoptServer(ServerConfig config) {
    _server = config;
    notifyListeners();
  }

  /// 用配置与密码建出仓库(启动时调用,与 [adoptServer] 配对)。
  ///
  /// 接在 [adoptServer] 之后而不是合成一个方法:配置与密码来自两个不同的
  /// 存储(前者 SharedPreferences,后者系统密钥库),各有各的失败可能,
  /// 分开之后「配置在但密码读不出来」这种情况有地方表达。
  void attachRepository(ServerConfig config, String password) {
    _repository = SubsonicRepository(
      clientFor(
        config: config,
        password: password,
        autoRoute: configStore.loadAutoRoute(),
        dio: _dio,
      ),
      // 封面的本机优先:下过的封面断网也看得见(见 SubsonicRepository.coverUri)。
      localCover: downloadManager.coverPathForArt,
    );
    notifyListeners();
  }

  /// 首次配置 / 修改配置:建仓库、测速、持久化。
  ///
  /// 密码写进系统密钥库;配置写进 SharedPreferences(不含密码)。
  Future<void> connect({
    required String name,
    required ServerKind kind,
    required String username,
    required String password,
    required List<ServerRoute> routes,
  }) async {
    final config = ServerConfig(
      id: _server?.id ?? 'server-1',
      name: name.trim().isEmpty ? kind.label : name.trim(),
      kind: kind,
      username: username.trim(),
      routes: routes,
    );

    await credentialStore.savePassword(password);
    await configStore.saveServer(config);

    _server = config;
    _repository = SubsonicRepository(
      clientFor(
        config: config,
        password: password,
        autoRoute: configStore.loadAutoRoute(),
        dio: _dio,
      ),
      // 封面的本机优先:下过的封面断网也看得见(见 SubsonicRepository.coverUri)。
      localCover: downloadManager.coverPathForArt,
    );
    notifyListeners();

    // 顺手测一次速并把择优结果定下来,这样第一次进音乐库就走最快那条。
    unawaited(refreshRouteLatency());
  }

  /// 断开并清除配置(设置页的「移除该服务器」)。
  Future<void> disconnect() async {
    await credentialStore.clear();
    await configStore.clearServer();
    // 缓存也清掉 —— 那台机器的库不再属于这里。
    await libraryCache.clear();
    // 音频缓存同理:留着的是那台服务器上的曲子,换一台之后既听不到也用不上。
    await mediaCache.clear();
    _server = null;
    _repository = null;
    _library = LibrarySnapshot.empty;
    _phase = LoadPhase.idle;
    _error = null;
    notifyListeners();
  }

  /// 更新线路(增删 / 改名 / 锁定)。
  ///
  /// 两处都要改:配置落盘,以及**正在用的那个客户端** —— 它手上那份线路是
  /// 建库时拷贝的,不推过去的话界面上的勾会动、请求却照旧走旧线路
  /// (真机报的「线路切换无效」)。测速结果同步清掉被删线路的条目,
  /// 免得「N / M 条可用」算错。
  Future<void> updateRoutes(List<ServerRoute> routes) async {
    final current = _server;
    if (current == null) return;

    final before = activeRoute;
    final updated = current.copyWith(routes: routes);
    await configStore.saveServer(updated);
    _server = updated;
    _repository?.client.setRoutes(routes);

    final ids = routes.map((r) => r.id).toSet();
    _pings = {
      for (final entry in _pings.entries)
        if (ids.contains(entry.key)) entry.key: entry.value,
    };
    _routeMaybeChanged(before);
    notifyListeners();
  }

  /// 重新测速并按结果择优。
  /// 正在测速。
  ///
  /// 界面据此把按钮改成「测速中」并禁用 —— 局域网一次 `ping.view` 是个位数毫秒,
  /// 不给这个状态,用户只会觉得「按了没反应」(真机反馈过这一条)。
  bool _pinging = false;
  bool get pinging => _pinging;

  Future<Map<String, RoutePing>> refreshRouteLatency() async {
    final repo = _repository;
    if (repo == null) return const {};

    final before = activeRoute;
    _pinging = true;
    notifyListeners();
    try {
      _pings = await repo.client.pingAll();
    } finally {
      // 「按下去要等一下才有结果」这个节奏得对上 —— 原型里同样如此
      // (`ping-all` 故意等 800ms 再回),否则个位数毫秒的往返谁也看不见。
      await Future<void>.delayed(const Duration(milliseconds: 600));
      _pinging = false;
      // 线路可用性变了,当前生效线路也可能变 —— 界面上的延迟数字要跟着更新。
      _routeMaybeChanged(before);
      notifyListeners();
    }
    return _pings;
  }

  // ---------------- 歌曲翻页 ----------------

  /// 一页多少首。
  ///
  /// 取 1000:实测这台 Navidrome 对 `songCount=1000/2000/20000` 都返回全量,
  /// 500 并不是它的硬上限(旧注释的「卡在 500」是误判)。常见个人库(几百到
  /// 一千首)**一个请求就完整**,于是「最近添加」当场就是对的。
  /// 真有服务器卡在 500 时,首屏拿 500、`songsComplete=false`,
  /// 由后台补齐继续取 —— 逻辑不变。
  static const _songPageSize = 1000;

  /// 后台补齐时最多再翻多少页(一页 1000,即一万首封顶)。
  /// 防的是「极端大库把启动后的网络一路占着」。
  static const _maxAutoPages = 10;

  /// 已经在翻了吗 —— 界面据此禁用「继续加载」那颗按钮,别叠出两次请求。
  bool _loadingMoreSongs = false;
  bool get loadingMoreSongs => _loadingMoreSongs;

  /// 已经从服务器**取回过的原始条数**(不是去重后的条数)。
  ///
  /// 翻页的 offset 必须按这个走:去重会丢掉重叠的条目,拿 `songs.length`
  /// 当 offset 会让下一页与上一页重叠,一直取不到底。
  int _songsFetched = 0;

  /// 「全部歌曲」那一栏滚到底时调一次:再取一页并上去。
  ///
  /// 返回是否**真的**又取到了一页(界面据此决定要不要再滚一次继续触发)。
  Future<bool> loadMoreSongs() async {
    final repo = _repository;
    if (repo == null || _loadingMoreSongs || _library.songsComplete) {
      return false;
    }

    _loadingMoreSongs = true;
    notifyListeners();
    try {
      final offset = _songsFetched;
      final page = await repo.allSongs(size: _songPageSize, offset: offset);
      _songsFetched += page.length;
      _library = mergeSongPage(
        _library,
        page,
        complete: page.length < _songPageSize,
        sort: songSort,
      );
      // 缓存跟着更新:不然重启之后「全部歌曲」又只剩第一页,
      // 而用户上一次明明已经翻到底了。
      //
      // **不 await**:每一次都 await 一遍全量编码 + fsync,在这一条后台补齐的
      // 路上会连着压十来次(而且载荷越写越大),那是平方级的活。写这一头由
      // `LibraryCache` 自己排队合并(见那儿的 `write`):写与写之间、写与清之间
      // 都不会打架,腾出去的只是「翻页这一下要不要等它」。
      unawaited(libraryCache.write(_serverKey(_server!), _library));
      return page.isNotEmpty;
    } on SubsonicException catch (e) {
      // 翻页失败不该把已经拿到的那些弄没 —— 记一句,列表照旧。
      _refreshError = e.message;
      _fromCache = true;
      return false;
    } finally {
      _loadingMoreSongs = false;
      notifyListeners();
    }
  }

  /// 生效线路换成别的了就把正在放的那一首挪过去。
  ///
  /// 择优选出来的那条与**这一首的流地址**是绑死的:地址在播放源装载时就拼好了
  /// (见 `SubsonicRepository.streamUri`),不重新装载的话界面会说「正在走新线路」,
  /// 而声音还是从旧那条流里出来的 —— 真机报的「线路切换无效」。
  ///
  /// 走的是**取值函数**而不是 import 播放层:播放层反过来要读这个对象的仓库,
  /// 硬连起来就成环了(与下载器同一套做法,见 [downloadManager])。
  /// 换线路之后要做的第二件事 —— 由 `main.dart` 填成播放层的 `retargetRoute`。
  ///
  /// 用可写字段而不是构造参数:应用状态先建(播放服务要读它的仓库),
  /// 播放层要等平台把前台服务拉起来才存在,构造那一刻还没有它。
  /// 没人填(测试 / 没有播放层)就是空操作。
  Future<void> Function()? onRouteChanged;

  void _routeMaybeChanged(ServerRoute? before) {
    final after = activeRoute;
    if (before?.id == after?.id) return;
    final retarget = onRouteChanged;
    if (retarget != null) unawaited(retarget());
  }

  Map<String, RoutePing> _pings = const {};
  Map<String, RoutePing> get pings => _pings;

  ServerRoute? get activeRoute => _repository?.client.activeRoute;

  // ---------------- 音乐库 ----------------

  LoadPhase _phase = LoadPhase.idle;
  LoadPhase get phase => _phase;

  String? _error;
  String? get error => _error;

  /// 错误是不是认证失败 —— 界面据此决定「去改密码」还是「重试」。
  bool _errorIsAuth = false;
  bool get errorIsAuth => _errorIsAuth;

  /// 错误是不是**网络**问题。这种时候本机已下好的内容是唯一能进去的地方,
  /// 界面据此提示一句(见 `ui/screens/library_screen.dart`)。
  bool _errorIsNetwork = false;
  bool get errorIsNetwork => _errorIsNetwork;

  LibrarySnapshot _library = LibrarySnapshot.empty;
  LibrarySnapshot get library => _library;

  /// 眼下这份库是不是**本机缓存**(还没跟服务器对上过一次)。
  bool _fromCache = false;
  bool get libraryFromCache => _fromCache;

  /// 上次同步成功的时间。界面用它说「上次同步 …」。
  DateTime? _cachedAt;
  DateTime? get libraryCachedAt => _cachedAt;

  /// 最近一次刷新失败了(但手上有缓存,于是没把界面切成错误态)。
  String? _refreshError;
  String? get refreshError => _refreshError;

  /// 把上次的快照先铺出来。
  ///
  /// 冷启动时先走这一步:库立刻可见,随后 [loadLibrary] 再静默刷新。
  /// 读不到(第一次装 / 换了服务器 / 缓存坏了)就什么也不做,一切照旧。
  Future<void> loadCachedLibrary() async {
    final server = _server;
    if (server == null || _library.albums.isNotEmpty) return;

    final cached = await libraryCache.read(_serverKey(server));
    if (cached == null) return;

    _library = cached.snapshot;
    _cachedAt = cached.savedAt;
    _fromCache = true;
    _phase = LoadPhase.ready;
    notifyListeners();
  }

  /// 这台服务器在缓存里的标识。
  ///
  /// 用「类型 + 账号 + 第一条线路」而不是服务器的显示名:名字可以随便改,
  /// 而这三样变了就是真的换了另一台库 —— 那时绝不能拿旧的顶上来。
  static String _serverKey(ServerConfig config) =>
      '${config.kind.name}|${config.username}|'
      '${config.routes.isEmpty ? '' : config.routes.first.url}';

  /// 静默刷新时,距上次同步还不到这个时长就直接跳过网络,减少无谓请求。
  /// 手动刷新不受影响,依然会如实去问服务器。
  static const _cacheFresh = Duration(minutes: 1);

  /// 拉取音乐库首页需要的全部数据。
  ///
  /// 并发拉而不是串行 —— 四个端点互不依赖,串起来会让进音乐库白等三倍时间。
  /// 任何一个失败就整体失败:半截数据画出来的界面更让人困惑。
  Future<void> loadLibrary({bool silent = false}) async {
    final repo = _repository;
    if (repo == null) return;

    if (silent && _fromCache && _cachedAt != null && DateTime.now().difference(_cachedAt!) < _cacheFresh) return;

    if (!silent) {
      _phase = LoadPhase.loading;
      _error = null;
      _errorIsAuth = false;
      _errorIsNetwork = false;
      notifyListeners();
    }

    try {
      // 收藏名单与库**并行**取:串在库后面等于白等一个往返,
      // 而它自己有错误处理(取不到就当没收藏),拖不垮这一轮。
      final starred = refreshStarred();

      final results = await Future.wait([
        // 专辑这一栏按用户选的口径向服务器要 —— 「最近播放 / 常听」这种
        // 本地算不出来,只有服务器知道。
        repo.albums(sort: albumSort),
        repo.artists(),
        // **只拉第一页**(一页 [_songPageSize] 首):常见个人库一次就完整,
        // 更大的库余下的由后台补齐 + 滚动懒加载(见 [loadMoreSongs] 与
        // `_completeSongs`)—— 全拉完在超大库上就是几十个往返压在启动路径上。
        repo.allSongs(size: _songPageSize),
        repo.playlists(),
        // 首页那两条货架。与上面走**同一个端点**(不同 type),并行发出去,
        // 失败也一起失败 —— 不会因为多这两条把这一轮变得更脆。
        repo.albumList(AlbumSort.recent),
        repo.albumList(AlbumSort.frequent),
      ]);

      final songs = results[2] as List<Song>;
      _songsFetched = songs.length;
      _library = LibrarySnapshot(
        albums: results[0] as List<Album>,
        artists: results[1] as List<Artist>,
        songs: sortSongs(songs, songSort),
        playlists: results[3] as List<Playlist>,
        // 旧的专辑口径货架不再单独拉一次(`repo.recentlyAdded()` 是一次白花的
        // 往返):「最近添加」现在铺歌曲,由下面这一行从已拉的 `songs` 本地排出来。
        recentlyAdded: const [],
        recentlyAddedSongs: recentlyAddedSongsOf(songs),
        recentlyPlayed: results[4] as List<Album>,
        mostPlayed: results[5] as List<Album>,
        // 一页就装下了(不足一页)才叫全集 —— 「全部歌曲」那一栏据此决定
        // 还要不要继续翻、以及页脚有没有一句「已到全部」。
        songsComplete: songs.length < _songPageSize,
      );
      _phase = LoadPhase.ready;
      _error = null;
      _errorIsAuth = false;
      _errorIsNetwork = false;
      _fromCache = false;
      _refreshError = null;
      _cachedAt = DateTime.now();
      // 缓存**在通知界面之前**写完:它是「顺手」的事,但不能飘在后台 ——
      // 飘着的话,用户切到别的屏、甚至下一次冷启动可能正好撞上没写完的那一份。
      // 「写与写之间、写与清之间撞车」那一半现在由 `LibraryCache` 的合并写者
      // 兜住(见那儿的 `write` / `settle`),这里 **await** 是为了这条硬约定:
      // `await loadLibrary()` 之后,读同一份缓存一定读得到刚取回的库。
      // write 自己吞掉写失败,所以这里不必防。
      await libraryCache.write(_serverKey(_server!), _library);
      // 上面已经把收藏那一轮发出去了,这里只等它落地 —— 不等也行,
      // 但等一等「心形状态」与「库」就是同时到位的,不会先画一排空心的心。
      unawaited(starred);
      // 首屏那一页之外还有曲子就在**后台**接着取:一是「全部歌曲」不该停在
      // 500/1000,二是「最近添加」必须排全量才对得上服务器。取完落进缓存,
      // 下次冷启动直接从缓存拿全,不必再翻。
      if (!_library.songsComplete) {
        _completing = _completeSongs().whenComplete(() => _completing = null);
        unawaited(_completing);
      }
    } on SubsonicException catch (e) {
      _failLoad(e.message, isAuth: e.isAuthFailure, isNetwork: e.isNetworkFailure);
    } catch (e) {
      _failLoad('$e');
    }
    notifyListeners();
  }

  /// 后台把剩下的曲目取全。
  ///
  /// 首屏只拉一页(`_songPageSize`);曲子更多的库在后台一页页补齐 ——
  /// 不这么做的话,「全部歌曲」永远停在首屏那一页,而**「最近添加」会排错**:
  /// `search3` 是 `created` 升序,最新的歌排在最后一页,没取到就排不出来。
  ///
  /// 失败就停(下一轮刷新会再来),不弹错 —— 这是后台动作,不该打断浏览。
  Future<void> _completeSongs() async {
    var pages = 0;
    while (!_library.songsComplete && pages < _maxAutoPages) {
      if (!await loadMoreSongs()) return;
      pages++;
    }
  }

  /// 后台补齐那一轮的 future。测试要等它落地才能断言「总共发了几个请求」,
  /// 界面不关心(它是 fire-and-forget)。没有在补时给一个已完成的 future。
  Future<void> get songsSettled => _completing ?? Future<void>.value();

  Future<void>? _completing;

  /// 刷新失败时的处置。
  ///
  /// **手上有缓存就不切成错误态**:把上次的内容留在屏幕上,只记一句
  /// 「这次没刷上」—— 断网时「看到的是上周的库」比「一片空白加重试」有用得多。
  /// 一点都没有才如实报错(第一次进来就失败,那确实没东西可看)。
  void _failLoad(String message, {bool isAuth = false, bool isNetwork = false}) {
    final hasSomething = _library.albums.isNotEmpty || _library.songs.isNotEmpty;

    _error = message;
    _errorIsAuth = isAuth;
    _errorIsNetwork = isNetwork;

    if (hasSomething) {
      _phase = LoadPhase.ready;
      _fromCache = true;
      _refreshError = message;
    } else {
      _phase = LoadPhase.failed;
      _refreshError = null;
    }
  }

  // ---------------- 排序 ----------------

  /// 专辑这一栏的排序口径。
  AlbumSort get albumSort =>
      AlbumSort.values.where((s) => s.name == configStore.loadAlbumSort()).firstOrNull ??
      AlbumSort.alphabeticalByArtist;

  SongSort get songSort => SongSort.byName(configStore.loadSongSort());

  /// 换专辑排序时正在重拉 —— 界面上那颗按钮转个圈,不然点了没反应像是卡的。
  bool _sortingAlbums = false;
  bool get sortingAlbums => _sortingAlbums;

  /// 换专辑排序:存下来 + **按新口径重拉这一栏**。
  ///
  /// 重拉而不是本地排:六个口径里「最近播放 / 常听」本地没有依据
  /// (那要播放次数与时间,只有在服务器上)。失败时抛出去让界面说话,
  /// 本地这份列表**保持原样** —— 排错了总比排没了强。
  Future<void> setAlbumSort(AlbumSort sort) async {
    if (sort == albumSort) return;
    await configStore.saveAlbumSort(sort.name);

    final repo = _repository;
    if (repo == null) {
      notifyListeners();
      return;
    }

    _sortingAlbums = true;
    notifyListeners();
    try {
      final albums = await repo.albums(sort: sort);
      _library = _library.copyWith(albums: albums);
    } finally {
      _sortingAlbums = false;
      notifyListeners();
    }
  }

  /// 换歌曲排序。**本地排** —— 服务器没有「按标题给我排一版歌」这种端点,
  /// 而曲子本来就在手上,再打一轮请求没有意义。
  Future<void> setSongSort(SongSort sort) async {
    if (sort == songSort) return;
    await configStore.saveSongSort(sort.name);

    _library = _library.copyWith(songs: sortSongs(_library.songs, sort));
    notifyListeners();
  }

  // ---------------- 收藏 ----------------

  final Set<String> _starredSongs = {};
  final Set<String> _starredAlbums = {};
  final Set<String> _starredArtists = {};

  bool isSongStarred(String id) => _starredSongs.contains(id);
  bool isAlbumStarred(String id) => _starredAlbums.contains(id);
  bool isArtistStarred(String id) => _starredArtists.contains(id);

  Future<void> refreshStarred() async {
    final repo = _repository;
    if (repo == null) return;
    try {
      final starred = await repo.starred();
      _starredSongs
        ..clear()
        ..addAll(starred.songs.map((s) => s.id));
      _starredAlbums
        ..clear()
        ..addAll(starred.albums.map((a) => a.id));
      _starredArtists
        ..clear()
        ..addAll(starred.artists.map((a) => a.id));
      notifyListeners();
    } catch (_) {
      // 收藏名单取不到不该阻断浏览 —— 界面显示未收藏即可。
    }
  }

  /// 切换收藏。**乐观更新**:先改本地再发请求,失败时回滚并报错。
  /// 等服务器回来再变的话,点一下心形要愣半秒,手感很差。
  Future<void> toggleSongStar(String songId) =>
      _toggleStar(_starredSongs, songId, songId: songId);

  Future<void> toggleAlbumStar(String albumId) =>
      _toggleStar(_starredAlbums, albumId, albumId: albumId);

  Future<void> toggleArtistStar(String artistId) =>
      _toggleStar(_starredArtists, artistId, artistId: artistId);

  Future<void> _toggleStar(
    Set<String> bucket,
    String id, {
    String? songId,
    String? albumId,
    String? artistId,
  }) async {
    final repo = _repository;
    if (repo == null) return;

    final wasStarred = bucket.contains(id);
    wasStarred ? bucket.remove(id) : bucket.add(id);
    notifyListeners();

    try {
      await repo.setStarred(
        songId: songId,
        albumId: albumId,
        artistId: artistId,
        starred: !wasStarred,
      );
    } catch (e) {
      // 回滚 —— 界面上不能停在一个服务器并不认的状态。
      wasStarred ? bucket.add(id) : bucket.remove(id);
      _error = '$e';
      _errorIsAuth = false;
      notifyListeners();
    }
  }

  // ---------------- 歌词 ----------------

  /// 取歌词。按歌曲 id 缓存 —— 歌词页来回进出很频繁,
  /// 每次都打一次服务器没必要。
  final Map<String, Lyrics> _lyricsCache = {};

  /// 磁盘歌词缓存,键是歌曲 id。与 LibraryCache 同目录,文件叫 lyrics.json。
  Map<String, dynamic> _lyricsDisk = {};
  bool _lyricsDiskLoaded = false;

  Future<File> _lyricsCacheFile() async {
    Directory base;
    try {
      base = await getApplicationSupportDirectory();
    } on MissingPluginException {
      base = Directory.systemTemp;
    }
    final dir = Directory('${base.path}${Platform.pathSeparator}cache');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}lyrics.json');
  }

  /// 读一次磁盘歌词缓存。读不到就当空 —— 歌词拿不到不该阻断播放。
  Future<void> _loadLyricsDisk() async {
    if (_lyricsDiskLoaded) return;
    _lyricsDiskLoaded = true;
    try {
      final file = await _lyricsCacheFile();
      if (!file.existsSync()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is Map) _lyricsDisk = json.cast<String, dynamic>();
    } catch (_) {
      // 坏文件 / 没权限:当作没有缓存。
    }
  }

  /// 把内存里的一份歌词补写进磁盘。失败不影响这次显示。
  Future<void> _saveLyricsDisk(String songId, Lyrics lyrics) async {
    _lyricsDisk[songId] = {
      'synced': lyrics.synced,
      'lines': [
        for (final line in lyrics.lines)
          {'text': line.text, 'start': line.start?.inMilliseconds},
      ],
    };
    try {
      final file = await _lyricsCacheFile();
      await file.writeAsString(jsonEncode(_lyricsDisk), flush: true);
    } catch (_) {
      // 写不进就算了 —— 下次还走网络。
    }
  }

  static Lyrics? _lyricsFromJson(Object? raw) {
    if (raw is! Map) return null;
    final lines = <LyricLine>[];
    for (final item in (raw['lines'] as List? ?? const [])) {
      if (item is! Map) continue;
      final text = item['text'];
      if (text is! String) continue;
      final start = item['start'];
      lines.add(LyricLine(
        text: text,
        start: start is num
            ? Duration(milliseconds: start.toInt())
            : null,
      ));
    }
    return Lyrics(lines: lines, synced: raw['synced'] == true);
  }

  Future<Lyrics> lyricsFor(String songId) async {
    final cached = _lyricsCache[songId];
    if (cached != null) return cached;

    // 磁盘那份先看一眼:重启之后再来听同一首,不必再打一次服务器。
    await _loadLyricsDisk();
    final disk = _lyricsFromJson(_lyricsDisk[songId]);
    if (disk != null) {
      _lyricsCache[songId] = disk;
      return disk;
    }

    final repo = _repository;
    if (repo == null) return Lyrics.empty;

    final lyrics = await repo.lyrics(songId);
    _lyricsCache[songId] = lyrics;
    // 空歌词不落盘 —— 下次服务器上有了要能重新取到。
    if (!lyrics.isEmpty) unawaited(_saveLyricsDisk(songId, lyrics));
    return lyrics;
  }

  // ---------------- 偏好 ----------------

  String? get themeModeName => configStore.loadThemeMode();

  Future<void> setThemeModeName(String name) async {
    await configStore.saveThemeMode(name);
    notifyListeners();
  }

  bool get autoRoute => configStore.loadAutoRoute();

  Future<void> setAutoRoute(bool value) async {
    await configStore.saveAutoRoute(value);
    // 开关是给**当前**这条连接用的,要立刻生效 —— 只落盘的话得等到
    // 下次重启应用才作数,用户会以为开关没反应。
    final before = activeRoute;
    _repository?.client.autoRoute = value;
    // 关掉自动择优等于改点名:生效线路可能当场换成锁定 / 首条那条,
    // 正在放的那一首也要跟着换。
    _routeMaybeChanged(before);
    notifyListeners();
    // 刚打开自动择优时手上可能还没有测速结果,顺手量一次,
    // 否则它会一直停在列表首条直到下一次请求。
    if (value) unawaited(refreshRouteLatency());
  }

  bool get backgroundPlay => configStore.loadBackgroundPlay();

  Future<void> setBackgroundPlay(bool value) async {
    await configStore.saveBackgroundPlay(value);
    notifyListeners();
  }

  bool get wifiOnlyDownload => configStore.loadWifiOnlyDownload();

  Future<void> setWifiOnlyDownload(bool value) async {
    await configStore.saveWifiOnlyDownload(value);
    // 门控条件变了:卡在「等待 Wi-Fi」的任务此刻可能就能开始了。
    downloadManager.onWifiOnlyChanged();
    notifyListeners();
  }

  // ---------------- 歌曲缓存 ----------------

  /// 缓存上限 —— 用户在设置里选的那一档。
  CacheLimit get cacheLimit => CacheLimit.byId(configStore.loadCacheLimit());

  /// 缓存眼下占了多少字节(不含半截文件)。
  int get cacheUsedBytes => mediaCache.usedBytes;

  /// 缓存里有几个文件。
  int get cachedTrackCount => mediaCache.fileCount;

  /// 换上限。**两处都要落**:设置里存档位名(以后增删档位不会把用户卡在一个
  /// 再也选不中的值上),存储层要的是字节(它按字节淘汰)。
  ///
  /// 调小到低于当前占用时会当场淘汰 —— 用户改完数字就该看见占用跟着降。
  Future<void> setCacheLimit(CacheLimit limit) async {
    await configStore.saveCacheLimit(limit.id);
    await mediaCache.setLimitBytes(limit.bytes);
    notifyListeners();
  }

  /// 清空缓存,返回释放的字节数(界面拿它说一句「释放了 138 MB」)。
  ///
  /// 删掉的只是**缓存** —— 用户点名下载的那些在另一个目录里,一行都不动。
  Future<int> clearCache() async {
    final freed = await mediaCache.clear();
    notifyListeners();
    return freed;
  }

  /// 建一个歌单。成功后就地把它插进本地快照 —— 不必整库重拉。
  ///
  /// 失败时抛 [SubsonicException] 而不是吞掉:这是用户主动发起的写操作,
  /// 「点了创建但什么都没有」比一句错误提示糟得多。
  Future<Playlist> createPlaylist(String name) async {
    final repo = _requireRepository();
    final created = await repo.createPlaylist(name);
    _library = _library.copyWith(playlists: [created, ..._library.playlists]);
    notifyListeners();
    return created;
  }

  /// 把一首歌加进歌单。
  ///
  /// 成功后**就地改本地快照的条数**,不重拉整库:重拉会把浏览位置和
  /// 滚动都打断,而用户只是想把这首歌塞进某个歌单。条数不跟着变的话,
  /// 「已加入」成功而列表里还写着旧数字,看着像没成功。
  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    final repo = _requireRepository();
    await repo.addToPlaylist(playlistId, songId);
    _bumpPlaylist(playlistId, 1);
  }

  /// 从歌单里移除某一首。[index] 是它在服务器那份列表里的位置。
  Future<void> removeSongFromPlaylist(String playlistId, int index) async {
    final repo = _requireRepository();
    await repo.removeFromPlaylist(playlistId, index);
    _bumpPlaylist(playlistId, -1);
  }

  /// 重命名歌单。
  Future<void> renamePlaylist(String playlistId, String name) async {
    final repo = _requireRepository();
    await repo.renamePlaylist(playlistId, name.trim());
    _mapPlaylist(
      playlistId,
      (p) => p.copyWith(name: name.trim()),
    );
  }

  /// 删除歌单。**服务器上的那份会被删掉**,界面要先问一句。
  Future<void> deletePlaylist(String playlistId) async {
    final repo = _requireRepository();
    await repo.deletePlaylist(playlistId);
    _library = _library.copyWith(
      playlists: [
        for (final p in _library.playlists)
          if (p.id != playlistId) p,
      ],
    );
    notifyListeners();
  }

  void _bumpPlaylist(String playlistId, int delta) {
    _mapPlaylist(
      playlistId,
      (p) => p.copyWith(songCount: (p.songCount + delta).clamp(0, 1 << 30)),
    );
  }

  /// 就地改本地快照里的一条歌单。找不到就什么也不做 ——
  /// 用户可能是在歌单详情页里操作一个已从库里消失的歌单。
  void _mapPlaylist(String playlistId, Playlist Function(Playlist) change) {
    final next = <Playlist>[];
    var changed = false;
    for (final p in _library.playlists) {
      if (p.id == playlistId) {
        changed = true;
        next.add(change(p));
      } else {
        next.add(p);
      }
    }
    if (!changed) return;

    _library = _library.copyWith(playlists: next);
    notifyListeners();
  }

  /// 取仓库,没有就抛一句人话 —— 写操作「静默失败」比报错糟得多。
  SubsonicRepository _requireRepository() {
    final repo = _repository;
    if (repo == null) {
      throw const SubsonicException('还没有连接服务器');
    }
    return repo;
  }

  Future<void> setQuality(QualityOption option) async {
    quality.set(option);
    await configStore.saveQuality(option.id);
    notifyListeners();
  }

  // ---------------- 下载 ----------------

  /// 下载任务列表。真值在 [downloadManager] 里 —— 状态层只是把它
  /// forward 给界面,免得界面为了下载再订阅第二个对象。
  List<DownloadJob> get downloads => downloadManager.jobs;

  int get activeDownloadCount => downloadManager.activeCount;

  /// 这首歌在不在本机。播放层用的是同一份索引,界面上的「已下载」标记
  /// 也据此显示 —— 两处各判一次迟早会不一致。
  bool isDownloaded(String songId) => downloadManager.isDownloaded(songId);


  /// 封面地址,**本机优先**。
  ///
  /// 给「没有服务器也要显示封面」的地方用 —— 下载管理就是那个场景:
  /// 断网时它仍要能列出已下好的内容,而封面本机就有一份。
  /// 界面其余地方的封面走 [SubsonicRepository.coverUri](同样本机优先)。
  Uri? coverUriFor(String? coverArtId, {int size = 512}) {
    if (coverArtId == null || coverArtId.isEmpty) return null;

    final local = downloadManager.coverPathForArt(coverArtId);
    if (local != null) return Uri.file(local);

    final repo = _repository;
    if (repo == null) return null;
    try {
      return repo.coverUri(coverArtId, size: size);
    } on SubsonicException {
      return null;
    }
  }

  /// 下载整张专辑的曲目。[songs] 必须是**已加载出来的曲目表** ——
  /// 只报个曲目数就下发,下载器无从知道要拉哪些文件。
  Future<DownloadJob> downloadAlbum(Album album, List<Song> songs) {
    if (songs.isEmpty) {
      throw const DownloadFailure('这张专辑还没有加载出曲目');
    }
    return downloadManager.enqueue(DownloadRequest.album(album, songs));
  }

  Future<DownloadJob> downloadSong(Song song) =>
      downloadManager.enqueue(DownloadRequest.song(song));

  /// 下载一位艺人的全部歌曲。
  ///
  /// 曲目要在全库里找齐(`getArtist` 只给几首热门),这一步会翻页,
  /// 大库上要等一会儿 —— 所以界面先提示「正在整理曲目」再调它。
  Future<DownloadJob> downloadArtist(Artist artist) async {
    final repo = _requireRepository();
    final songs = await repo.songsByArtist(artist);
    if (songs.isEmpty) {
      throw SubsonicException('在音乐库里没有找到 ${artist.name} 的歌曲');
    }
    return downloadManager.enqueue(DownloadRequest.artist(artist, songs));
  }

  Future<void> removeDownload(String id) => downloadManager.remove(id);

  Future<void> retryDownload(String id) => downloadManager.retry(id);

  @override
  void dispose() {
    downloadManager.removeListener(notifyListeners);
    mediaCache.removeListener(notifyListeners);
    super.dispose();
  }
}
