import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/config_transfer.dart';
import '../../data/server_config.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/qr_view.dart';

/// 「导出配置」那张纸:二维码 + 「包含密码」开关 + 「复制文本」。
///
/// 走弹层而不是新开一屏 —— 它是「看一眼 / 复制一下」,不是走进去再走出来的一段路。
///
/// 二维码里那串与「复制文本」复制走的那串**是同一个字符串**(见 [ConfigTransfer]):
/// 有相机的设备扫码,没相机的那台(桌面 / 浏览器)复制过去粘进「扫码同步」那一屏,
/// 一样能带过去。所以下面那串文本是**可选中的**,不是装饰 —— 复制失败时
/// 那就是唯一的路。
Future<void> showConfigExportSheet(BuildContext context) {
  final state = context.read<AppState>();
  final server = state.server;
  // 没有服务器就没有配置可导出。设置页那行入口本来就只在已连接时出现,
  // 这里再兜一次,是因为别处也可能调进来。
  if (server == null) return Future<void>.value();

  return showNordicSheet<void>(
    context: context,
    builder: (sheetContext) =>
        _ExportSheet(server: server, credentialStore: state.credentialStore),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.server, required this.credentialStore});

  final ServerConfig server;
  final CredentialStore credentialStore;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  /// **默认关。** 与「落盘不带密码」是同一口径 —— 打开之后这张二维码就等于
  /// 密码本身,那是个要用户自己点头的决定。
  bool _withPassword = false;

  /// 本机密钥库里存着的密码。读不出来(没存过 / 读不了)时那颗开关整个不出现:
  /// 没东西可选的时候摆一个开关只是骗人。
  String? _password;

  @override
  void initState() {
    super.initState();
    _loadPassword();
  }

  Future<void> _loadPassword() async {
    String? saved;
    try {
      saved = await widget.credentialStore.readPassword();
    } catch (_) {
      // 读不出来就当没存过。
      saved = null;
    }
    if (!mounted) return;
    setState(() => _password = (saved == null || saved.isEmpty) ? null : saved);
  }

  String get _payload => ConfigTransfer.encode(
    kind: widget.server.kind,
    name: widget.server.name,
    username: widget.server.username,
    routes: widget.server.routes,
    password: _withPassword ? _password : null,
  );

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = _payload;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('已复制到剪贴板'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      // 浏览器的剪贴板 API 在非安全上下文里就是会被拒 —— 所以下面那串文本
      // 必须能手动选中。
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('复制不了 —— 选中下面那段文本，手动复制一遍。'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final payload = _payload;

    return NordicScrim(
      onTap: () => Navigator.of(context).pop(),
      child: NordicSheet(
        title: '导出配置',
        subtitle: '扫码带走，或复制成文本',
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: QrView(data: payload, size: 216)),
              if (_password != null) ...[
                const SizedBox(height: NordicSpace.s5),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NordicSpace.s5,
                  ),
                  child: Row(
                    children: [
                      const SettingIcon(icon: Icons.lock_outline_rounded),
                      const SizedBox(width: NordicSpace.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '包含密码',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _withPassword ? '扫到的人可以直接连上' : '只带地址与账号，新设备补一次密码',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(color: t.fg3),
                            ),
                          ],
                        ),
                      ),
                      NordicSwitch(
                        value: _withPassword,
                        onChanged: (value) =>
                            setState(() => _withPassword = value),
                      ),
                    ],
                  ),
                ),
              ],
              if (_withPassword) ...[
                const SizedBox(height: NordicSpace.s4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: NordicSpace.s5),
                  child: NordicNote(
                    '打开之后，这张二维码与这段文本就等于密码本身 —— 别截图、别发群里。',
                    tone: NordicNoteTone.warn,
                  ),
                ),
              ],
              const SizedBox(height: NordicSpace.s5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
                child: GhostButton(
                  label: '复制文本',
                  icon: Icons.copy_rounded,
                  onPressed: _copy,
                ),
              ),
              const SizedBox(height: NordicSpace.s4),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
                padding: const EdgeInsets.all(NordicSpace.s4),
                constraints: const BoxConstraints(maxHeight: 88),
                decoration: BoxDecoration(
                  color: t.fill1,
                  borderRadius: BorderRadius.circular(NordicRadius.md),
                  border: Border.all(color: t.line),
                ),
                // 里面自己滚:这串可能上百个字符,而外面那层已经在滚了。
                child: SingleChildScrollView(
                  child: SelectableText(
                    payload,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.7,
                      color: t.fg3,
                    ),
                  ),
                ),
              ),
              const ListNote(
                '没有摄像头的设备（桌面 / 浏览器）扫不了码 —— 把这段文本复制过去，'
                '粘进「扫码同步」那一屏，一样能带过去。',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
