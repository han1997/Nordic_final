// 线路(服务器地址)这块的模型与编辑函数。
//
// 单独成文件的原因:它们是**协议无关**的 —— 一个地址、一个延迟、一个锁定
// 状态,换成别的音源也一样成立,而 `subsonic_client.dart` 讲的是 Subsonic
// 协议。放在那里会让「音源抽象层」绕不开那个文件(见 `music_source.dart`)。
//
// `subsonic_client.dart` 会 `export` 这个文件,所以原先从那儿拿
// `ServerRoute` / `RouteTag` / `RoutePing` 的地方一个字都不用改。

/// 一个服务器地址(线路)。同一个音乐库可以配多条 —— 内外网各一条,
/// 出门也能听。择优与故障切换都围绕它做。
class ServerRoute {
  const ServerRoute({
    required this.id,
    required this.name,
    required this.url,
    this.tag = RouteTag.lan,
    this.selected = false,
  });

  final String id;
  final String name;

  /// 不带尾斜杠的基址,如 `http://192.168.10.4:4533`。
  final String url;

  final RouteTag tag;

  /// 用户是否手动锁定了这条线路。锁定后不再自动切换(原型里的规则)。
  final bool selected;

  ServerRoute copyWith({String? name, String? url, RouteTag? tag, bool? selected}) =>
      ServerRoute(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        tag: tag ?? this.tag,
        selected: selected ?? this.selected,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'tag': tag.name,
        'selected': selected,
      };

  static ServerRoute fromJson(Map<String, dynamic> json) => ServerRoute(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        tag: RouteTag.values.firstWhere(
          (t) => t.name == json['tag'],
          orElse: () => RouteTag.lan,
        ),
        selected: json['selected'] as bool? ?? false,
      );
}

/// 改现有服务器时,把表单里那条地址合回线路表。
///
/// 表单上只有**一个**地址框 —— 它对应的是第一条线路。所以:
///   - 原来一条都没有:就用 [edited] 自己(表单第一次填的时候);
///   - 原来有几条:**替换第一条**,其余几条连 id 与锁定状态一起原样留着。
///
/// 为什么不能整表换掉:那些 id 是测速结果与「当前走哪条」的键,也是「锁定」
/// 挂靠的地方 —— 用户只想改个密码,不该把内外网那两条线路抹掉,也不该
/// 顺手把唯一剩下的一条锁死(锁上之后自动择优就停了)。
///
/// [edited] 的 id 在这里**被忽略**(合入时沿用原来那条的 id)。
List<ServerRoute> mergeEditedRoute(
  List<ServerRoute> existing,
  ServerRoute edited,
) {
  if (existing.isEmpty) return [edited];
  return [
    existing.first.copyWith(
      name: edited.name,
      url: edited.url,
      tag: edited.tag,
    ),
    ...existing.skip(1),
  ];
}

/// 点一条线路 —— 锁定它;**再点锁定中的那条就是解锁**(回到自动择优)。
///
/// 「锁定」是单选语义:留两条 `selected` 会让 `activeRoute` 的取值不确定
/// (它取第一条锁定的)。所以锁一条就取消其余,而只有**已经锁着的那条**能解
/// —— 先前只有「锁」没有「解」,点错了就再也回不去自动择优,真机上卡在过
/// 这一处。
///
/// 线路面板与服务器管理页两个入口原先各写了一份一模一样的实现:改一处忘
/// 另一处,两边的行为就会不一样。
List<ServerRoute> toggleRouteLock(List<ServerRoute> routes, ServerRoute route) {
  final unlocking = route.selected;
  return [
    for (final r in routes)
      r.copyWith(selected: unlocking ? false : r.id == route.id),
  ];
}

/// 线路标记 —— 原型「添加线路」页的三档。
enum RouteTag {
  lan('内网'),
  wan('公网'),
  relay('中继');

  const RouteTag(this.label);

  final String label;
}

/// 一条线路的可用性与延迟。
class RoutePing {
  const RoutePing({required this.routeId, this.latency, this.error});

  final String routeId;

  /// 往返延迟。null 表示测速失败 —— 与「还没测(user 主动跳过的档位)」区分开:
  /// 前者是 [error] 非空,后者两者都空。
  final Duration? latency;

  final String? error;

  bool get isOk => latency != null && error == null;
}