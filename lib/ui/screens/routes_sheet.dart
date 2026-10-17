import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/subsonic_client.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../widgets/components.dart';

/// 揭开线路切换面板 —— 播放中随时可换。
void showRoutesSheet(BuildContext context) {
  showNordicSheet<void>(
    context: context,
    builder: (sheetContext) => const _RoutesSheet(),
  );
}

class _RoutesSheet extends StatefulWidget {
  const _RoutesSheet();

  @override
  State<_RoutesSheet> createState() => _RoutesSheetState();
}

class _RoutesSheetState extends State<_RoutesSheet> {

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = context.watch<AppState>();
    final routes = state.server?.routes ?? const <ServerRoute>[];
    final active = state.activeRoute;

    return NordicScrim(
      onTap: () => Navigator.of(context).pop(),
      child: NordicSheet(
        title: '线路',
        subtitle: '播放中可随时切换',
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (routes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: NordicSpace.s6),
                  child: EmptyState(
                    title: '还没有配置线路',
                    detail: '一个账号可以配多条地址,内外网各留一条。',
                    topPadding: 0,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
                  child: Column(
                    children: [
                      for (var i = 0; i < routes.length; i++)
                        _RouteRow(
                          route: routes[i],
                          ping: state.pings[routes[i].id],
                          selected: routes[i].id == active?.id,
                          locked: routes[i].selected,
                          onTap: () => _select(state, routes[i]),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NordicSpace.s5, NordicSpace.s3, NordicSpace.s5, 0),
                child: Row(
                  children: [
                    NordicChip(
                      label: state.pinging ? '测速中' : '立即测速',
                      icon: Icons.refresh,
                      height: 32,
                      selected: state.pinging,
                      onTap: state.pinging ? null : () => state.refreshRouteLatency(),
                    ),
                    const Spacer(),
                    Text(
                      '${routes.where((r) => (state.pings[r.id]?.isOk ?? true)).length}'
                      ' / ${routes.length} 条可用',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: t.ok),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NordicSpace.s5, NordicSpace.s4, NordicSpace.s5, 0),
                child: Text(
                  '播放时优先走延迟最低的可用线路,当前线路中断会自动换到下一条'
                  '并接着放。手动锁定后不再自动切换 —— 想放手,再点一下锁定中的那条。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.fg3, height: 1.6),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NordicSpace.s5, NordicSpace.s4, NordicSpace.s5, 0),
                child: GhostButton(
                  label: '管理服务器与线路',
                  icon: Icons.settings_outlined,
                  onPressed: () {
                    Navigator.of(context).pop();
                    AppRoutes.openServers(context);
                  },
                ),
              ),
              const SizedBox(height: NordicSpace.s3),
            ],
          ),
        ),
      ),
    );
  }

  /// 选中一条线路。**再点一下锁定中的那条就是解除锁定**(回到自动择优)。
  ///
  /// 「锁定」是单选语义:留两条 `selected` 会让 [AppState.activeRoute] 的取值
  /// 不确定。所以锁一条就取消其余;而只有**已经锁着的那条**能解 ——
  /// 之前只有「锁」没有「解」,点错了就再也回不到自动择优,真机上就卡在这儿。
  Future<void> _select(AppState state, ServerRoute route) async {
    final unlocking = route.selected;
    final routes = (state.server?.routes ?? const <ServerRoute>[])
        .map((r) => r.copyWith(selected: unlocking ? false : r.id == route.id))
        .toList();
    await state.updateRoutes(routes);
    await state.refreshRouteLatency();
  }

}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.route,
    required this.ping,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final ServerRoute route;
  final RoutePing? ping;

  /// 当前生效的那条(界面上的勾)。
  final bool selected;

  /// 用户手动锁定的那条。锁定与生效是两件事 —— 自动择优下生效的未必被锁,
  /// 而只有锁着的那条点一下能解。
  final bool locked;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final failed = ping != null && !ping!.isOk;

    return Pressable(
      onTap: onTap,
      pressedDecoration: BoxDecoration(color: t.fill1),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: NordicSpace.s4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(
          children: [
            NordicTick(selected: selected),
            const SizedBox(width: NordicSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          route.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: selected ? context.accentSafe : t.fg,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 锁着的那条挂一枚标记 —— 勾只说「现在走它」,说不了
                      // 「它被点名了」,而这两件事点一下的结果完全不同
                      // (锁着的点了解锁,没锁的点上锁)。
                      if (locked) ...[
                        Icon(Icons.push_pin, size: 13, color: context.accentSafe),
                        const SizedBox(width: 5),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: t.fill2,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          route.tag.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: t.fg3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    route.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          // 地址用等宽字体 —— 数字与冒号对齐才好扫读。
                          fontFamily: 'monospace',
                          color: t.fg4,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NordicSpace.s3),
            // 通着的线路给一眼「快不快」的信号条;不通的不给 —— 空条说不出
            // 比「不可用」更多的话。
            if (ping?.isOk ?? false) ...[
              SignalBars(bars: SignalBars.forLatency(ping!.latency)),
              const SizedBox(width: NordicSpace.s4),
            ],
            if (failed)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '不可用',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.bad,
                    ),
                  ),
                  Text(
                    '连接失败',
                    style: TextStyle(fontSize: 10, color: t.fg4),
                  ),
                ],
              )
            else if (ping == null)
              Text(
                '未测速',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: t.fg3),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${ping!.latency!.inMilliseconds}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.fg,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text('ms', style: TextStyle(fontSize: 10, color: t.fg4)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}