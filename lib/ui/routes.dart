import 'package:flutter/material.dart';

import '../data/config_transfer.dart';
import '../theme/tokens.dart';
import 'screens/add_route_screen.dart';
import 'screens/about_screen.dart';
import 'screens/album_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/lyrics_screen.dart';
import 'screens/new_playlist_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/servers_screen.dart';
import 'screens/sync_screen.dart';

/// 路由约定。
///
/// 沉浸页(播放 / 歌词 / 专辑 / 艺人 / 歌单)一律**自己带返回按钮**、盖住标签栏。
/// 过渡分两种:详情页(专辑 / 艺人 / 歌单 / 服务器…)从**右侧滑入**,
/// 与「从列表钻进一个详情」的心理模型一致;播放页**整屏淡入**(与切 tab 同一套,
/// 见 [fade]);歌词页与播放页是同一个播放对象的两面,直接换(见 [flip])。
///
/// 集中在这里而不是散在调用点,是为了让「哪些页面对外可见」一眼看全 ——
/// 也让 [openSearch] 这类跳转有唯一一处入口。
/// 「服务器与线路」那一屏的路由参数 —— 见 [AppRoutes.openServers]。
///
/// 用一个 record 而不是「先传个 bool、再想办法塞个对象进去」:`RouteSettings`
/// 只有一个 `arguments` 槽,record 让两个值一起过去,而且调用点一眼看得见
/// `form` 是真是假(与 `openAlbum` 的 `(id:, heroTag:)` 同一个做法)。
typedef ServersArgs = ({bool form, TransferredServer? prefill});

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
  static const sync = '/sync';
  static const about = '/about';

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
        return fade(settings, const PlayerScreen());
      case lyrics:
        // 歌词与播放页是**同一个播放对象的两面** —— 见 [flip]。
        return flip(settings, const LyricsScreen());
      case servers: {
        // 两种调用点:老的那几个传一个 bool;「扫码同步」传一个 record
        // (它还要把读出来那份配置带进去预填)。**不为迁就 record 把老的改一遍** ——
        // `args == true` 那条兜底让它们原样可用。
        final args = settings.arguments;
        final (form, prefill) = args is ServersArgs
            ? (args.form, args.prefill)
            : (args == true, null);
        return slide(
          settings,
          ServersScreen(startInForm: form, prefill: prefill),
        );
      }
      case sync:
        // 二级页,走滑入 —— 它不是播放页那种「同一张封面翻个面」。
        return slide(settings, const SyncScreen());
      case about:
        return slide(settings, const AboutScreen());
      case downloads:
        return slide(settings, const DownloadsScreen());
      case newPlaylist:
        return slide(settings, const NewPlaylistScreen());
      case addRoute:
        return slide(settings, const AddRouteScreen());
      case album: {
        final args = settings.arguments as ({String id, String? heroTag});
        return slide(
          settings,
          AlbumScreen(albumId: args.id, heroTag: args.heroTag),
        );
      }
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

  /// 播放页的进出:**整屏淡入** —— 与切 tab 是同一套(`NordicMotion.screenFade`
  /// 加 `NordicMotion.ease`)。
  ///
  /// 2026-10-18 用户提的:滑入那 320ms 在真机上读得出顿挫,「试试切 tab 那套动画」。
  /// 这一版的读法是:旧那一屏原地不动,新那一屏从透明淡上来 —— 两屏底色是同款深色
  /// 氛围,于是是一屏「化」进另一屏,而不是「一个页面从右边压上来」。原型已同步
  /// (`prototype/app.js` 的 `navKind` / `styles.css` 的 `vt-fade-in|out`)。
  ///
  /// 与 [slide] 共用一条纪律:**不做缩放**。淡入会为整棵子树开一个离屏合成层,
  /// 所以这里照 `shell.dart` 切 tab 那处的做法垫一层 [RepaintBoundary] —— 少了它,
  /// 沉浸页那 62px 的氛围模糊与玻璃 `BackdropFilter` 每帧都要在新缓冲里重做一遍
  /// (理由见 [generate] 上那段)。
  ///
  /// **这是一次试,手感要真机上才有结论**;别顺手把专辑 / 艺人 / 歌单也换成它 ——
  /// 那几屏读的是「从列表钻进一个详情」,位移那一下正是它要说的意思。
  static Route<dynamic> fade(RouteSettings settings, Widget page) =>
      PageRouteBuilder(
        settings: settings,
        transitionDuration: NordicMotion.screenFade,
        reverseTransitionDuration: NordicMotion.screenFade,
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: NordicMotion.ease),
          child: RepaintBoundary(child: child),
        ),
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

  /// 打开专辑页。
  ///
  /// [heroTag] 是**起点那张封面**的共享元素 tag。它必须跟着路由走,不能写死:
  /// 专辑页的封面只能挂一个 `Hero`,而来源不止一处 —— 音乐库的网格用的是
  /// `cover-{id}`,首页那两条货架用的是各自的前缀(`cover-rail-recent-` /
  /// `cover-rail-frequent-`)。前缀逐条不同是硬要求:同一张专辑常常同时在两条
  /// 货架上,同一条路由里重名 `Hero` 会直接断言失败(见 `docs/performance.md`)。
  ///
  /// 不传就退回网格那个 tag —— 从艺人页 / 播放页 / 歌单菜单进来时来路本身
  /// 没有 `Hero`,挂什么都无所谓。
  static Future<void> openAlbum(BuildContext context, String albumId,
          {String? heroTag}) =>
      Navigator.of(context).pushNamed(
        album,
        arguments: (id: albumId, heroTag: heroTag),
      );

  static Future<void> openArtist(BuildContext context, String artistId) =>
      Navigator.of(context).pushNamed(artist, arguments: artistId);

  static Future<void> openPlaylist(BuildContext context, String playlistId) =>
      Navigator.of(context).pushNamed(playlist, arguments: playlistId);

  /// 打开服务器与线路。
  ///
  /// [form] 为真时**直接落在录入表单上**(设置页那颗「添加服务器」),
  /// 否则落在管理页 —— 那一页里的「服务器设置」才是改账号 / 密码 / 地址的入口。
  ///
  /// [prefill] 是「扫码同步」读出来那份配置:落在表单上、除密码以外全部填好,
  /// 用户补一次密码就能连。
  static Future<void> openServers(
    BuildContext context, {
    bool form = false,
    TransferredServer? prefill,
  }) =>
      Navigator.of(context).pushNamed(
        servers,
        arguments: (form: form, prefill: prefill),
      );

  /// 打开扫码同步 —— 把另一台设备上的服务器与线路带到这台设备来。
  static Future<void> openSync(BuildContext context) =>
      Navigator.of(context).pushNamed(sync);

  /// 打开「关于」—— 设置里那一栏的落地页。
  ///
  /// 与别的二级页一样**推入**(不是弹层):它有一屏内容,还可能从那里翻到
  /// 系统的开源许可页(那是另一层)。
  static Future<void> openAbout(BuildContext context) =>
      Navigator.of(context).pushNamed(about);

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