import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../data/config_transfer.dart';
import '../../data/scan_capability.dart';
import '../../data/server_route.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../connect_flow.dart';
import '../routes.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/states.dart';

/// 「扫码同步」—— 把另一台设备上的服务器与线路带到**这台**设备来。
///
/// 两种输入方式,一个结果:
///   - 有相机的(原生 Android / iOS)扫那张二维码;
///   - 没有的(Windows 桌面、浏览器)粘贴**同一串**文本 —— 见 [ScanCapability]。
///
/// 读完**不直接连上去**:先把读出来的东西摆出来给用户看一眼(哪台服务器、几条线路、
/// 带不带密码),再让他点头。因为导入会把本机当前那台**替换掉**。
///
/// 导出那一半在设置页那张弹层里(见 `config_export_sheet.dart`)。
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, this.capability});

  /// 这台设备能不能起摄像头。不传就走 [ScanCapability.auto]。
  ///
  /// 测试从这里注入一份固定的 —— 于是「安卓上的 Chrome」那种组合
  /// (`defaultTargetPlatform` 说是 android,但它其实是网页)也能真的跑到,
  /// 而那正是**绝不能**把摄像头建起来的那一种。
  final ScanCapability? capability;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

enum _Mode { scan, paste }

class _SyncScreenState extends State<SyncScreen> {
  late final bool _canScan =
      (widget.capability ?? ScanCapability.auto()).isSupported;

  _Mode _mode = _Mode.scan;
  final _text = TextEditingController();

  /// **只在支持扫码时才建。** 它就是「把 mobile_scanner 拉进来」的那一步 ——
  /// 那个包在 web 上要页面自己去 unpkg 取 `@zxing`(见 [ScanCapability] 那段)。
  MobileScannerController? _controller;

  /// 读出来的那份配置。与 [_error] 互斥。
  TransferredServer? _read;
  TransferError? _error;

  /// 一次扫码只认第一下 —— 连续命中同一张码不该反复触发。
  bool _handled = false;

  /// 摄像头起不来(权限被拒 / 没有 / 通道不在)。与「这台设备没有相机」分开记:
  /// 前者是**试一试才发现**的,后者是一开始就知道的。
  bool _cameraDown = false;

  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    if (!_canScan) {
      _mode = _Mode.paste;
      return;
    }
    _controller = MobileScannerController(
      // 只认二维码:这是一段配置载荷,不是商品条码。少认几种,也少一次误判。
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// 文本看着像不像我们的载荷。**这只是「按不按得动那颗键」的判据**,
  /// 真正的判决在 [ConfigTransfer.decode] —— 前缀对、内容坏的那份照样会被它拒,
  /// 并且给出准确的原因。
  bool get _looksLikePayload =>
      _text.text.trim().startsWith(ConfigTransfer.prefix);

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _handled = true;
      _consume(raw);
      return;
    }
  }

  /// 读一段载荷。扫到的与粘进来的走**同一条路** —— 两端本来就是同一串文本。
  void _consume(String raw) {
    final result = ConfigTransfer.decode(raw);
    // 读到了就让摄像头停下:预览已经出来了,再让它转着只是费电。
    unawaited(_controller?.stop() ?? Future<void>.value());

    setState(() {
      switch (result) {
        case TransferOk(:final server):
          _read = server;
          _error = null;
        case TransferFailed(:final reason):
          _read = null;
          _error = reason;
      }
    });
  }

  void _switchMode(_Mode mode) {
    setState(() {
      _mode = mode;
      // 换一种输入方式,上一份读出来的东西就不算数了 —— 它说的是**另一种**方式的
      // 结果,留着会让人以为换模式也换了内容。
      _read = null;
      _error = null;
      _handled = false;
    });
  }

  /// 载荷没带密码那条路:落到录入表单,除密码以外全部预填。
  void _openForm(TransferredServer server) {
    AppRoutes.openServers(context, form: true, prefill: server);
  }

  /// 载荷带密码那条路:直接连。
  Future<void> _connect(TransferredServer server) async {
    final password = server.password;
    if (password == null) return;

    final state = context.read<AppState>();
    if (state.hasServer) {
      final confirmed = await _confirmReplace();
      if (confirmed != true || !mounted) return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _connecting = true);

    try {
      await connectAndLoad(
        state,
        name: server.name,
        kind: server.kind,
        username: server.username,
        password: password,
        routes: server.routes,
      );
    } on ConnectFailure catch (f) {
      if (!mounted) return;
      setState(() => _connecting = false);
      messenger?.showSnackBar(SnackBar(
        content: Text(f.message),
        duration: const Duration(seconds: 4),
      ));
      return;
    }

    if (!mounted) return;
    setState(() => _connecting = false);
    messenger?.showSnackBar(SnackBar(
      content: Text('连接成功，已读取 ${state.library.totalSongs} 首曲目。'),
      duration: const Duration(seconds: 3),
    ));
    Navigator.of(context).pop();
  }

  Future<bool?> _confirmReplace() => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: context.nordic.glass3,
          title: const Text('替换当前的服务器？'),
          content: Text(
            '本机留着的曲库快照与缓存会一起清掉。服务器上的音乐不受影响。',
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('替换'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    // watch:主按钮的文案取决于本机现在连没连着服务器。
    final hasServer = context.watch<AppState>().hasServer;
    final read = _read;

    return ImmersiveScaffold(
      accent: context.accent,
      showAmbient: false,
      child: Column(
        children: [
          NordicAppBar(
            title: '扫码同步',
            big: false,
            leading: IconButtonRound(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              if (_mode == _Mode.paste)
                PillButton(
                  label: '读取',
                  solid: true,
                  onPressed: _looksLikePayload ? () => _consume(_text.text) : null,
                ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + NordicSpace.s6,
              ),
              children: [
                // 没有相机时**整个不出现**:一个只有一项的分段控件只是噪音。
                if (_canScan)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      NordicSpace.s5,
                      NordicSpace.s3,
                      NordicSpace.s5,
                      NordicSpace.s4,
                    ),
                    child: SegmentedControl<_Mode>(
                      options: const [_Mode.scan, _Mode.paste],
                      value: _mode,
                      labelOf: (mode) => mode == _Mode.scan ? '扫码' : '粘贴',
                      onChanged: _switchMode,
                    ),
                  ),
                if (!_canScan)
                  const ListNote(
                    '这台设备没有摄像头 —— 用粘贴文本一样能同步。',
                    padding: EdgeInsets.fromLTRB(
                      NordicSpace.s5,
                      NordicSpace.s3,
                      NordicSpace.s5,
                      0,
                    ),
                  ),
                if (_cameraDown)
                  const ListNote(
                    '摄像头起不来（可能是没给权限） —— 用粘贴文本一样能同步。',
                    padding: EdgeInsets.fromLTRB(
                      NordicSpace.s5,
                      NordicSpace.s3,
                      NordicSpace.s5,
                      0,
                    ),
                  ),
                if (_mode == _Mode.scan) _scanPane() else _pastePane(),
                if (_error != null) ...[
                  const SizedBox(height: NordicSpace.s5),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NordicSpace.s5,
                    ),
                    child: NordicNote(
                      _error!.message,
                      tone: NordicNoteTone.bad,
                    ),
                  ),
                ],
                if (read != null) ...[
                  const SizedBox(height: NordicSpace.s2),
                  _preview(read, hasServer: hasServer),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanPane() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(NordicRadius.lg),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 底色固定黑 —— 那是相机画面该有的样子,不是界面的一部分。
                    const ColoredBox(color: Color(0xFF000000)),
                    if (!_cameraDown && _controller != null)
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (_, error) {
                          // 权限被拒 / 没有摄像头 / 插件通道不在,都落到这儿。
                          // **不能在这里 setState**(还在 build 里),所以推到下一帧;
                          // 退到粘贴,而不是把一屏黑留在那儿。
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted || _cameraDown) return;
                            setState(() {
                              _cameraDown = true;
                              _mode = _Mode.paste;
                            });
                          });
                          return const SizedBox.shrink();
                        },
                      ),
                    const _ViewfinderFrame(),
                  ],
                ),
              ),
            ),
          ),
          const ListNote('把另一台设备上的二维码放进框里 —— 扫到之后先读出配置给你看一眼，不会直接连上去。'),
        ],
      );

  Widget _pastePane() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
        child: NordicField(
          label: '配置文本',
          hint: '从另一台设备的「导出配置」复制过来，或者直接扫它的二维码。',
          child: NordicTextField(
            controller: _text,
            maxLines: 6,
            monospace: true,
            hintText: 'nordic://config/1/...',
            onChanged: (_) => setState(() {}),
          ),
        ),
      );

  Widget _preview(TransferredServer server, {required bool hasServer}) {
    final t = context.nordic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '读出来的配置', count: '1 台服务器'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
          child: Container(
            decoration: BoxDecoration(
              color: t.fill1,
              borderRadius: BorderRadius.circular(NordicRadius.md),
              border: Border.all(color: t.line),
            ),
            child: Column(
              children: [
                for (var i = 0; i < server.routes.length; i++) ...[
                  if (i > 0) const NordicDivider(),
                  _routeRow(server.routes[i]),
                ],
              ],
            ),
          ),
        ),
        if (server.droppedRoutes > 0) ...[
          const SizedBox(height: NordicSpace.s4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
            child: NordicNote(
              '这段配置里的地址有 ${server.droppedRoutes} 条读不出来，已经跳过。',
            ),
          ),
        ],
        if (server.carriedPassword) ...[
          const SizedBox(height: NordicSpace.s4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: NordicSpace.s5),
            child: NordicNote(
              '这段配置带着密码 —— 连上之后它就是本机唯一一份凭据，别把这张二维码留在别人手机上。',
            ),
          ),
        ] else
          const ListNote('这段配置没带密码，接下来会落到录入表单 —— 地址与账号都填好了，只差密码。'),
        if (hasServer) ...[
          const SizedBox(height: NordicSpace.s4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: NordicSpace.s5),
            child: NordicNote('导入会替换当前这台服务器，本机留着的曲库快照与缓存会一起清掉。'),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NordicSpace.s5,
            NordicSpace.s5,
            NordicSpace.s5,
            NordicSpace.s2,
          ),
          child: PrimaryButton(
            label: _ctaLabel(server, hasServer: hasServer),
            onPressed: _connecting
                ? null
                : () => server.carriedPassword
                    ? _connect(server)
                    : _openForm(server),
          ),
        ),
      ],
    );
  }

  /// 主按钮说什么,取决于接下来要用户做的是哪件事 —— 三件事各有各的说法。
  String _ctaLabel(TransferredServer server, {required bool hasServer}) {
    if (_connecting) return '正在连接';
    if (!server.carriedPassword) return '填上密码';
    return hasServer ? '连接并替换' : '连接';
  }

  Widget _routeRow(ServerRoute route) {
    final t = context.nordic;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NordicSpace.s4,
        vertical: NordicSpace.s3,
      ),
      child: Row(
        children: [
          Icon(Icons.dns_outlined, size: 18, color: context.accentSafe),
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
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      route.tag.label,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.fg4),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  route.url,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.fg3),
                ),
              ],
            ),
          ),
          if (route.selected)
            Text(
              '锁定',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.accentSafe),
            ),
        ],
      ),
    );
  }
}

/// 取景框:四个角括号 + 一条来回走的扫描线。与原型那一块同一样子。
class _ViewfinderFrame extends StatelessWidget {
  const _ViewfinderFrame();

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _CornerPainter(context.accentSafe)),
          const _ScanLine(),
        ],
      );
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final inset = size.width * 0.08;
    const arm = 33.0;

    for (final (dx, dy) in const [
      (1.0, 1.0),
      (-1.0, 1.0),
      (1.0, -1.0),
      (-1.0, -1.0),
    ]) {
      final origin = Offset(
        dx > 0 ? inset : size.width - inset,
        dy > 0 ? inset : size.height - inset,
      );
      canvas.drawLine(origin, origin.translate(dx * arm, 0), paint);
      canvas.drawLine(origin, origin.translate(0, dy * arm), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => oldDelegate.color != color;
}

/// 那条扫描线。**单独一个 [RepaintBoundary]**:它每帧都在动,不该把角括号
/// 与上面那层相机预览一起拖着重画。
class _ScanLine extends StatefulWidget {
  const _ScanLine();

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // 与原型 `.scanline` 的 2.4s 同一个节拍。
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentSafe;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Align(
          alignment: Alignment(0, -0.85 + 1.7 * _controller.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SizedBox(
              height: 2,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0),
                      accent,
                      accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}