import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'screens/add_route_screen.dart';
import 'screens/album_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/library_screen.dart';
import 'screens/lyrics_screen.dart';
import 'screens/new_playlist_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/player_screen.dart';
import 'screens/servers_screen.dart';

/// 路由约定。
///
/// 沉浸页(播放 / 歌词 / 专辑 / 艺人 / 歌单)统一从**右侧滑入**,
/// 与「从列表钻进一个详情」的心理模型一致;它们各自带返回按钮。
///
/// 集中在这里而不是散在调用点,是为了让「哪些页面对外可见」一眼看全 ——
/// 也让 [openSearchTab] 这类「先切 tab 再定位」的复合跳转有地方放。
abstract final class AppRoutes {
  static const player = '/player';
  static const lyrics = '/lyrics';
  static const album = '/album';
  static const artist = '/artist';
  static const playlist = '/playlist';
  static const servers = '/servers';
  static const downloads = '/downloads';
  static const newPlaylist = '/new-playlist';
  static const addRoute = '/add-route';

  /// 全部具名路由。挂在 `MaterialApp.routes` 上。
  static Map<String, WidgetBuilder> get table => {
        player: (_) => const PlayerScreen(),
        lyrics: (_) => const LyricsScreen(),
        servers: (_) => const ServersScreen(),
        downloads: (_) => const DownloadsScreen(),
        newPlaylist: (_) => const NewPlaylistScreen(),
        addRoute: (_) => const AddRouteScreen(),
      };

  /// 带参数的路由 —— 用 `onGenerateRoute` 接。
  static Route<dynamic>? generate(RouteSettings settings) {
    switch (settings.name) {
      case album:
        return _slide(settings, AlbumScreen(albumId: settings.arguments as String));
      case artist:
        return _slide(settings,
            ArtistScreen(artistId: settings.arguments as String));
      case playlist:
        return _slide(settings,
            PlaylistScreen(playlistId: settings.arguments as String));
      default:
        return null;
    }
  }

  /// 详情页统一的滑入过渡。用平台默认的 [CupertinoPageRoute] 语义
  /// (从右滑入 + 手势返回),而不是 Material 的默认上浮 ——
  /// 这个应用全屏沉浸,侧滑返回更符合直觉。
  static Route<dynamic> _slide(RouteSettings settings, Widget page) =>
      PageRouteBuilder(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: const Cubic(0.22, 0.61, 0.36, 1),
          );
          return SlideTransition(
            position: Tween(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      );

  // ---- 调用入口。参数传递与路由名收在一处。 ----

  static Future<void> openPlayer(BuildContext context) =>
      Navigator.of(context).pushNamed(player);

  static Future<void> openLyrics(BuildContext context) =>
      Navigator.of(context).pushNamed(lyrics);

  static Future<void> openAlbum(BuildContext context, String albumId) =>
      Navigator.of(context).pushNamed(album, arguments: albumId);

  static Future<void> openArtist(BuildContext context, String artistId) =>
      Navigator.of(context).pushNamed(artist, arguments: artistId);

  static Future<void> openPlaylist(BuildContext context, String playlistId) =>
      Navigator.of(context).pushNamed(playlist, arguments: playlistId);

  static Future<void> openServers(BuildContext context) =>
      Navigator.of(context).pushNamed(servers);

  static Future<void> openDownloads(BuildContext context) =>
      Navigator.of(context).pushNamed(downloads);

  static Future<void> openNewPlaylist(BuildContext context) =>
      Navigator.of(context).pushNamed(newPlaylist);

  static Future<void> openAddRoute(BuildContext context) =>
      Navigator.of(context).pushNamed(addRoute);

  /// 顶栏那个放大镜:切到搜索 tab。
  ///
  /// 搜索是**一级 tab** 而不是二级页面(原型里就是这么分的),
  /// 所以这里不能 push,得让主壳换 tab。用一个全局通知把意图传上去。
  static void openSearchTab(BuildContext context) {
    searchTabRequest.value++;
  }
}

/// 请求切到搜索 tab 的信号。
///
/// 用 [ValueNotifier] 而不是回调 —— 顶栏与主壳隔着好几层,
/// 逐层传回调会把中间层弄脏;而「切到某个 tab」本来就是个全局界面意图。
final searchTabRequest = ValueNotifier<int>(0);

/// 进入页面时若尚未加载过曲库,顺手拉一次。
Future<void> ensureLibrary(BuildContext context) async {
  final state = context.read<AppState>();
  if (state.hasServer && state.phase == LoadPhase.idle) {
    await state.loadLibrary();
  }
}