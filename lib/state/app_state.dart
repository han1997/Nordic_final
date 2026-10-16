import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/server_config.dart';
import '../data/subsonic_client.dart';
import '../data/subsonic_payload.dart';
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
  });

  final ConfigStore configStore;
  final CredentialStore credentialStore;
  final QualityController quality;

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
    _repository = SubsonicRepository(clientFor(config: config, password: password));
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
    _repository = SubsonicRepository(clientFor(config: config, password: password));
    notifyListeners();

    // 顺手测一次速并把择优结果定下来,这样第一次进音乐库就走最快那条。
    unawaited(refreshRouteLatency());
  }

  /// 断开并清除配置(设置页的「移除该服务器」)。
  Future<void> disconnect() async {
    await credentialStore.clear();
    await configStore.clearServer();
    _server = null;
    _repository = null;
    _library = LibrarySnapshot.empty;
    _phase = LoadPhase.idle;
    _error = null;
    notifyListeners();
  }

  /// 更新线路(增删 / 改名 / 锁定)。
  Future<void> updateRoutes(List<ServerRoute> routes) async {
    final current = _server;
    if (current == null) return;
    final updated = current.copyWith(routes: routes);
    await configStore.saveServer(updated);
    _server = updated;
    notifyListeners();
  }

  /// 重新测速并按结果择优。
  Future<Map<String, RoutePing>> refreshRouteLatency() async {
    final repo = _repository;
    if (repo == null) return const {};
    _pings = await repo.client.pingAll();
    // 线路可用性变了,当前生效线路也可能变 —— 界面上的延迟数字要跟着更新。
    notifyListeners();
    return _pings;
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

  LibrarySnapshot _library = LibrarySnapshot.empty;
  LibrarySnapshot get library => _library;

  /// 拉取音乐库首页需要的全部数据。
  ///
  /// 并发拉而不是串行 —— 四个端点互不依赖,串起来会让进音乐库白等三倍时间。
  /// 任何一个失败就整体失败:半截数据画出来的界面更让人困惑。
  Future<void> loadLibrary({bool silent = false}) async {
    final repo = _repository;
    if (repo == null) return;

    if (!silent) {
      _phase = LoadPhase.loading;
      _error = null;
      _errorIsAuth = false;
      notifyListeners();
    }

    try {
      final results = await Future.wait([
        repo.albums(),
        repo.artists(),
        repo.allSongs(),
        repo.playlists(),
        repo.recentlyAdded(),
      ]);

      _library = LibrarySnapshot(
        albums: results[0] as List<Album>,
        artists: results[1] as List<Artist>,
        songs: results[2] as List<Song>,
        playlists: results[3] as List<Playlist>,
        recentlyAdded: results[4] as List<Album>,
      );
      _phase = LoadPhase.ready;
      _error = null;
      _errorIsAuth = false;
      // 顺手把收藏名单取回来 —— 界面上的心形要显示当前状态,
      // 否则每次重绘都从「未收藏」开始,点了才变,看着像没记住。
      unawaited(refreshStarred());
    } on SubsonicException catch (e) {
      _phase = LoadPhase.failed;
      _error = e.message;
      _errorIsAuth = e.isAuthFailure;
    } catch (e) {
      _phase = LoadPhase.failed;
      _error = '$e';
      _errorIsAuth = false;
    }
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

  Future<Lyrics> lyricsFor(String songId) async {
    final cached = _lyricsCache[songId];
    if (cached != null) return cached;

    final repo = _repository;
    if (repo == null) return Lyrics.empty;

    final lyrics = await repo.lyrics(songId);
    _lyricsCache[songId] = lyrics;
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
    notifyListeners();
  }

  bool get backgroundPlay => configStore.loadBackgroundPlay();

  Future<void> setBackgroundPlay(bool value) async {
    await configStore.saveBackgroundPlay(value);
    notifyListeners();
  }

  bool get wifiOnlyDownload => configStore.loadWifiOnlyDownload();

  Future<void> setWifiOnlyDownload(bool value) async {
    await configStore.saveWifiOnlyDownload(value);
    notifyListeners();
  }

  /// 建一个歌单。成功后就地把它插进本地快照 —— 不必整库重拉。
  ///
  /// 失败时抛 [SubsonicException] 而不是吞掉:这是用户主动发起的写操作,
  /// 「点了创建但什么都没有」比一句错误提示糟得多。
  Future<Playlist> createPlaylist(String name) async {
    final repo = _repository;
    if (repo == null) {
      throw const SubsonicException('还没有连接服务器');
    }

    final created = await repo.createPlaylist(name);
    _library = LibrarySnapshot(
      albums: _library.albums,
      artists: _library.artists,
      songs: _library.songs,
      playlists: [created, ..._library.playlists],
      recentlyAdded: _library.recentlyAdded,
    );
    notifyListeners();
    return created;
  }

  Future<void> setQuality(QualityOption option) async {
    quality.set(option);
    await configStore.saveQuality(option.id);
    notifyListeners();
  }

  // ---------------- 下载队列 ----------------

  /// 下载任务。
  ///
  /// **这一轮的进度是模拟的**(见 [advanceDownloads]),不做真实落盘与离线播放。
  /// 界面上如实呈现即可 —— 队列能加能删、状态会走,但按钮背后的文件并不存在,
  /// 所以界面上不承诺「离线可播」。
  final List<DownloadTask> _downloads = [];
  List<DownloadTask> get downloads => List.unmodifiable(_downloads);

  int get activeDownloadCount =>
      _downloads.where((d) => d.state == DownloadState.active).length;

  void enqueueDownload(DownloadTask task) {
    // 同一条重复入队没有意义 —— 专辑页来回点两次会看到两个一样的条目。
    if (_downloads.any((d) => d.id == task.id)) {
      notifyListeners();
      return;
    }
    _downloads.insert(0, task);
    notifyListeners();
  }

  void removeDownload(String id) {
    _downloads.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  void clearDownloads() {
    _downloads.clear();
    notifyListeners();
  }

  /// 推进模拟进度。由界面上的定时器调用 —— 放在 [AppState] 里而不是
  /// 下载页内部,是为了切走再切回来时进度仍然连续。
  void advanceDownloads() {
    final active = _downloads.where((d) => d.state == DownloadState.active);
    if (active.isEmpty) return;
    for (final task in active) {
      task.pct = (task.pct + 7 + task.id.hashCode % 9).clamp(0.0, 100.0);
      if (task.pct >= 100) task.state = DownloadState.done;
    }
    notifyListeners();
  }
}

/// 下载任务的状态。
enum DownloadState {
  active('下载中'),
  done('已完成');

  const DownloadState(this.label);

  final String label;
}

/// 一条下载任务。
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.name,
    this.detail = '',
    this.sizeMb = 0,
    this.pct = 0,
    this.state = DownloadState.active,
  });

  final String id;
  final String name;
  final String detail;
  final double sizeMb;

  /// 0–100。
  double pct;

  DownloadState state;

  /// 文案里的体积。四舍五入到整 MB —— 小数位没有意义。
  String get sizeLabel => '${sizeMb.round()} MB';

  bool get isDone => state == DownloadState.done;
}

/// 音乐库的一屏数据。
@immutable
class LibrarySnapshot {
  const LibrarySnapshot({
    required this.albums,
    required this.artists,
    required this.songs,
    required this.playlists,
    required this.recentlyAdded,
  });

  final List<Album> albums;
  final List<Artist> artists;
  final List<Song> songs;
  final List<Playlist> playlists;
  final List<Album> recentlyAdded;

  static const empty = LibrarySnapshot(
    albums: <Album>[],
    artists: <Artist>[],
    songs: <Song>[],
    playlists: <Playlist>[],
    recentlyAdded: <Album>[],
  );

  bool get isEmpty =>
      albums.isEmpty &&
      artists.isEmpty &&
      songs.isEmpty &&
      playlists.isEmpty;

  /// 服务器上标称的总曲目数。取专辑的 songCount 之和而不是 songs.length ——
  /// 后者受我们一次拉多少条的限制,不是库的真实规模。
  int get totalSongs =>
      albums.fold(0, (sum, a) => sum + a.songCount);

  /// 常听艺人:按专辑数取前几位。没有真实播放统计时的合理近似。
  List<Artist> get topArtists {
    final sorted = [...artists]..sort((a, b) => b.albumCount.compareTo(a.albumCount));
    return sorted.take(6).toList();
  }
}