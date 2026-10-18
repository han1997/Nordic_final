import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'screens/add_route_screen.dart';
import 'screens/album_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/lyrics_screen.dart';
import 'screens/new_playlist_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/servers_screen.dart';

/// 路由约定。
///
/// 沉浸页(播放 / 歌词 / 专辑 / 艺人 / 歌单)统一从**右侧滑入**,
/// 与「从列表钻进一个详情」的心理模型一致;它们各自带返回按钮。
///
/// 集中在这里而不是散在调用点,是为了让「哪些页面对外可见」一眼看全 ——
/// 也让 [openSearch] 这类跳转有唯一一处入口。
abstract final class AppRoutes {
  static const player = '/player';
  static const lyrics = '/lyrics';
  static const album = '/album';
  static const artist = '/artist';
  static const playlist = '/playlist';
  static const search = '/search';
  static const servers = '/servers';
  static const downloads = '/downloads';
  static const newPlaylist = '/new-playlist';
  static const addRoute = '/add-route';

  /// 所有页面的路由都从这里出。
  ///
  /// **不挂 `MaterialApp.routes` 表**:那张表走 Material 的默认过渡
  /// (Android 上是缩放 + 淡入)。缩放一路要重画,而淡入会强制 saveLayer ——
  /// 这两件事叠在本应用的页面上(整屏氛围模糊 + 两片玻璃胶囊)就是切页面时
  /// 的顿挫。统一走 [slide] 的纯位移:位移不改几何,模糊层可以直接复用。
  ///
  /// 2026-10-17 补记:[slide] 原先**自己也叠了一层淡入**,等于把上面这段话
  /// 又踩了一遍 —— 真机反馈「切页面 / 返回卡顿」就是它。整屏不透明度会为整棵
  /// 子树开一个离屏缓冲,于是那 62px 的氛围模糊与播放坞的 `BackdropFilter`
  /// 每帧都要在新缓冲里重做一遍;而位移只是把**已经缓存的层**平移,几乎不花钱。
  /// 现在淡入拿掉了。敢拿掉是因为两屏的底色是同款深色氛围,那层淡入本来也
  /// 几乎看不出来,真正被看见的一直是位移。
  static Route<dynamic>? generate(RouteSettings settings) {
    switch (settings.name) {
      case player:
        return slide(settings, const PlayerScreen());
      case lyrics:
        // 歌词与播放页是**同一个播放对象的两面** —— 见 [flip]。
        return flip(settings, const LyricsScreen());
      case servers:
        return slide(
          settings,
          ServersScreen(startInForm: settings.arguments == true),
        );
      case downloads:
        return slide(settings, const DownloadsScreen());
      case newPlaylist:
        return slide(settings, const NewPlaylistScreen());
      case addRoute:
        return slide(settings, const AddRouteScreen());
      case album:
        return slide(settings, AlbumScreen(albumId: settings.arguments as String));
      case artist:
        return slide(settings,
            ArtistScreen(artistId: settings.arguments as String));
      case playlist:
        return slide(settings, PlaylistScreen(playlistId: settings.arguments as String));
      case search:
        return slide(settings, const SearchScreen());
      default:
        return null;
    }
  }

  /// 播放页 ↔ 歌词页:直接换,**不滑也不飞**。
  ///
  /// 这两屏是同一个东西的两面(点封面互相翻):位移会读成「进了一个新页面」,
  /// 而这里要的是「同一张封面翻了个面」。原型也是这么分的 ——
  /// `go('lyrics')` 不走 View Transition,`render(false)` 原地换掉。
  ///
  /// [reverseTransitionDuration] 同样给 0:点歌词回封面也是直接变,
  /// 不然来路与去路的手感不一致。
  static Route<dynamic> flip(RouteSettings settings, Widget page) =>
      PageRouteBuilder(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, _, _, child) => child,
      );

  /// 页面统一的滑入过渡。用平台默认的 [CupertinoPageRoute] 语义
  /// (从右滑入 + 手势返回),而不是 Material 的默认上浮 ——
  /// 这个应用全屏沉浸,侧滑返回更符合直觉。
  ///
  /// 缓动与时长对齐底部悬浮 tab 的胶囊(`NordicMotion.ease`)。
  ///
  /// **只有位移,没有淡入** —— 见 [generate] 上那段:整屏不透明度会把氛围模糊
  /// 与玻璃 `BackdropFilter` 关进离屏层,每帧重做。少了淡入之后「新页盖上来」
  /// 那一下会不会读成硬切?不会:两屏的底色是同款深色氛围,真正被看见的是
  /// 从右边推进来的那道边,而那正是位移在做的。
  static Route<dynamic> slide(RouteSettings settings, Widget page) =>
      PageRouteBuilder(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, animation, secondary, child) => SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: NordicMotion.ease,
          )),
          child: child,
        ),
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

  /// 打开服务器与线路。
  ///
  /// [form] 为真时**直接落在录入表单上**(设置页那颗「添加服务器」),
  /// 否则落在管理页 —— 那一页里的「服务器设置」才是改账号 / 密码 / 地址的入口。
  static Future<void> openServers(BuildContext context, {bool form = false}) =>
      Navigator.of(context).pushNamed(servers, arguments: form);

  static Future<void> openDownloads(BuildContext context) =>
      Navigator.of(context).pushNamed(downloads);

  static Future<void> openNewPlaylist(BuildContext context) =>
      Navigator.of(context).pushNamed(newPlaylist);

  static Future<void> openAddRoute(BuildContext context) =>
      Navigator.of(context).pushNamed(addRoute);

  /// 打开搜索 —— **一张推入的页面**,不再是常驻 tab。
  ///
  /// 2026-10-17 用户提出「搜索不需要单独一个悬浮 tab」:搜索是「知道要找什么」
  /// 时的动作,用完就退;常驻位置留给首页那种「不知道听什么」时的落点。
  ///
  /// 原先这条路靠一个全局 [ValueNotifier] 通知主壳换 tab —— 那套**断过一阵**
  /// (有人发没人听,顶栏放大镜成了死按钮)。改成 push 之后这条隐式依赖没了:
  /// 谁点谁 push,不依赖主壳是否在场。
  static Future<void> openSearch(BuildContext context) =>
      Navigator.of(context).pushNamed(search);
}