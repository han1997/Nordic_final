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
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => const _RoutesSheet(),
  );
}

class _RoutesSheet extends StatefulWidget {
  const _RoutesSheet();

  @override
  State<_RoutesSheet> createState() => _RoutesSheetState();
}

class _RoutesSheetState extends State<_RoutesSheet> {
  bool _pinging = false;

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
                      label: _pinging ? '测速中' : '立即测速',
                      icon: Icons.refresh,
                      height: 32,
                      selected: _pinging,
                      onTap: _pinging ? null : () => _pingAll(state),
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
                  '并接着放。手动锁定后不再自动切换。',
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

  /// 选中一条线路。**同时取消其它线路的锁定** —— 「锁定」是单选语义,
  /// 留两条 selected 会让 activeRoute 的取值变得不确定。
  Future<void> _select(AppState state, ServerRoute route) async {
    final routes = (state.server?.routes ?? const <ServerRoute>[])
        .map((r) => r.copyWith(selected: r.id == route.id))
        .toList();
    await state.updateRoutes(routes);
    await state.refreshRouteLatency();
  }

  Future<void> _pingAll(AppState state) async {
    setState(() => _pinging = true);
    await state.refreshRouteLatency();
    if (mounted) setState(() => _pinging = false);
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.route,
    required this.ping,
    required this.selected,
    required this.onTap,
  });

  final ServerRoute route;
  final RoutePing? ping;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final failed = ping != null && !ping!.isOk;

    return InkWell(
      onTap: onTap,
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