import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/subsonic_client.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/states.dart';

/// 添加线路地址 —— 一个账号可以配多条,客户端按延迟择优。
///
/// 校验与服务器设置页同一条规则:地址填完整了才让按「添加」,
/// 按下之前就能看出还差什么。
class AddRouteScreen extends StatefulWidget {
  const AddRouteScreen({super.key});

  @override
  State<AddRouteScreen> createState() => _AddRouteScreenState();
}

class _AddRouteScreenState extends State<AddRouteScreen> {
  final _urlController = TextEditingController();
  RouteTag _tag = RouteTag.lan;
  bool _saving = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// 补全协议头并校验。返回规范化后的地址,不合法时返回 null。
  String? get _normalized {
    var value = _urlController.text.trim();
    if (value.isEmpty) return null;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  bool get _typed => _urlController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final state = context.watch<AppState>();
    final normalized = _normalized;

    return ImmersiveScaffold(
      accent: context.accent,
      showAmbient: false,
      child: Column(
        children: [
          NordicAppBar(
            title: '添加线路地址',
            big: false,
            leading: IconButtonRound(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              PillButton(
                label: _saving ? '添加中' : '添加',
                solid: true,
                onPressed: normalized != null && !_saving ? _save : null,
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + NordicSpace.s6,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NordicSpace.s5, NordicSpace.s4, NordicSpace.s5, NordicSpace.s5),
                  child: Text(
                    '一个账号可以配多条线路,客户端按延迟自动择优。'
                    '内外网各留一条,出门也能听。',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: t.fg2, height: 1.7),
                  ),
                ),
                if (state.server == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: NordicSpace.s5),
                    child: _Warning('还没有配置服务器,先去「服务器与线路」填一次账号。'),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
                    child: Column(
                      children: [
                        NordicField(
                          label: '服务器地址',
                          hint: '支持 http / https,也可以是域名或 IPv6。',
                          child: NordicTextField(
                            controller: _urlController,
                            hintText: 'http://192.168.1.10:4533',
                            prefixIcon: Icons.dns_outlined,
                            keyboardType: TextInputType.url,
                            autofocus: true,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: NordicSpace.s4),
                        _TagPicker(
                          value: _tag,
                          onChanged: (tag) => setState(() => _tag = tag),
                        ),
                        if (_typed && normalized == null)
                          const Padding(
                            padding: EdgeInsets.only(top: NordicSpace.s5),
                            child: _Warning(
                              '这个地址还不完整 —— 要以 http:// 或 https:// 开头,'
                              '并且带上主机名。',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final server = state.server;
    final url = _normalized;
    if (server == null || url == null) return;

    // 同一条地址不必重复添加 —— 择优表里两条一样的线路没有意义。
    if (server.routes.any((r) => r.url == url)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('这条地址已经加过了'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final host = Uri.tryParse(url)?.host ?? url;
    await state.updateRoutes([
      ...server.routes,
      ServerRoute(
        id: 'route-${server.routes.length + 1}-${DateTime.now().millisecondsSinceEpoch}',
        name: host,
        url: url,
        tag: _tag,
      ),
    ]);
    // 加完立刻测一次,用户马上能看到这条线通不通。
    await state.refreshRouteLatency();

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('线路已添加,正在测速'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _TagPicker extends StatelessWidget {
  const _TagPicker({required this.value, required this.onChanged});

  final RouteTag value;
  final ValueChanged<RouteTag> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '标记',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600, color: t.fg3),
          ),
        ),
        SegmentedControl<RouteTag>(
          options: RouteTag.values,
          value: value,
          labelOf: (tag) => tag.label,
          onChanged: onChanged,
        ),
        const SizedBox(height: NordicSpace.s2),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '标记只影响显示,择优仍按实测延迟来。',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Container(
      padding: const EdgeInsets.all(NordicSpace.s4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NordicRadius.md),
        color: t.warn.withValues(alpha: 0.11),
        border: Border.all(color: t.warn.withValues(alpha: 0.28)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Color.lerp(t.warn, t.fg, 0.24),
              height: 1.6,
            ),
      ),
    );
  }
}