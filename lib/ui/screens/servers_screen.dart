import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/server_config.dart';
import '../../data/subsonic_client.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../shell/bottom_stack.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/states.dart';

/// 服务器与线路管理。
///
/// 未配置时这是一张**录入表单**(填地址 / 账号 / 密码 → 测速 → 进库);
/// 已配置时是**管理页**(看线路状态、切换、增删、重配、移除服务器)。
/// 两种状态同一个页面,因为对用户来说是同一件事:「我的服务器」。
///
/// **改配置的入口**(2026-10-17 修):表单原先只在「还没配过」时出现,于是连上
/// 之后再想改账号 / 密码 / 地址就无处可去 —— 这一屏只剩线路能改。而 `connect()`
/// 一直是按「首次配置 / 修改配置」写的,`initState` 也早就把现有值填回表单了,
/// 差的只是那个入口。
class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key, this.startInForm = false});

  /// 一进来就停在**表单**(而不是管理页)。
  ///
  /// 设置页那颗「添加服务器」走的是这条:用户已经说了要填新服务器,
  /// 再让他自己找一下「服务器设置」是多余的一步。
  final bool startInForm;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  // ---- 表单状态 ----
  final _nameController = TextEditingController(text: '我的音乐库');
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();

  ServerKind _kind = ServerKind.navidrome;
  bool _busy = false;
  String? _formError;
  String? _formSuccess;

  /// 停在表单上(而不是管理页)。已配置过时才需要这个开关 ——
  /// 没配置过的话表单本来就是这一屏的正文。
  late bool _editing = widget.startInForm;

  /// 这张表单是**给另一台服务器**填的(设置页那颗「添加服务器」),不是改现有
  /// 那台。两处区别:
  ///
  ///   - 不预填现有配置 —— 用户说的是「另一台」,填上旧的会让他以为在改旧的;
  ///   - 保存时不把现有那几条线路合回来(那是另一台机器的事)。
  ///
  /// 从管理页点「服务器设置」进来的是**改现有那台**,这条路要预填、也要保住
  /// 其余线路(见 [_mergeIntoExisting])。
  bool _creatingNew = false;

  @override
  void initState() {
    super.initState();
    // 已经配过服务器、而且是来**改配置**的,就把现有值填回表单。
    _creatingNew = !context.read<AppState>().hasServer ? true : widget.startInForm;
    if (!_creatingNew) unawaited(_prefillFrom(context.read<AppState>()));
  }

  /// 把已配置的值填回表单 —— 进表单时、以及**按「取消」时**都要用。
  ///
  /// 「取消」也要填回来:只把 `_editing` 翻回去的话,扔掉的改动还留在输入框里,
  /// 下一次进表单看到的还是那半份 —— 那时一次误点就把它存下去了。
  Future<void> _prefillFrom(AppState appState) async {
    final server = appState.server;
    if (server == null) return;
    _nameController.text = server.name;
    _userController.text = server.username;
    _kind = server.kind;
    if (!mounted) return;
    setState(() {
      if (server.routes.isNotEmpty) {
        _urlController.text = server.routes.first.url;
      }
    });
    // 密码在系统密钥库里,表单自己拿不到 —— 但也得填上:
    // 只想改个地址却要重打一遍密码,那种「改一处」没人愿意做。
    await _prefillPassword();
  }

  /// 把已存的密码读进表单。失败(密钥库读不出来 / 本机没存)就留空,
  /// 用户重填一遍即可 —— 这里不该报错打断整个页面。
  Future<void> _prefillPassword() async {
    try {
      final saved = await context.read<AppState>().credentialStore.readPassword();
      if (!mounted || saved == null || saved.isEmpty) return;
      if (_passwordController.text.isNotEmpty) return;
      setState(() => _passwordController.text = saved);
    } catch (_) {
      // 读不出来就当没存过。
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _urlController.text.trim().isNotEmpty &&
      _userController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      !_busy;

  Future<void> _connect() async {
    final appState = context.read<AppState>();
    final url = _normalizeUrl(_urlController.text);

    if (url == null) {
      setState(() => _formError = '地址要以 http:// 或 https:// 开头。');
      return;
    }

    setState(() {
      _busy = true;
      _formError = null;
      _formSuccess = null;
    });

    await appState.connect(
      name: _nameController.text,
      kind: _kind,
      username: _userController.text,
      password: _passwordController.text,
      // 改现有那台:表单里这条地址**替换掉第一条线路**,其余几条原样留着;
      // 新接一台:就一条线路。
      //
      // 早先这里无条件提交一条 `route-1`:用户只想改个密码,内外网那两条线路
      // 就被抹掉了,活下来的那条还被强制锁定(于是「自动择优」也一起停了)——
      // 而这条路是这一轮才开的入口,所以以前碰不到。
      routes: _creatingNew
          ? [_routeFor(url)]
          : mergeEditedRoute(appState.server?.routes ?? const [], _routeFor(url)),
    );

    if (!mounted) return;

    // 连上之后立刻拉一次库 —— 让用户在这里就看到「成没成」,
    // 而不是跳到音乐库再看一片空白。
    await appState.loadLibrary();
    if (!mounted) return;

    final saved = appState.phase != LoadPhase.failed;
    // 从管理页进来改配置的,存完回到管理页 —— 那一页上的名字、线路、
    // 曲库数字都已经是新的了,再把用户留在表单里等于让他自己猜「成没成」。
    final backToManage = saved && _editing && appState.server != null;

    setState(() {
      _busy = false;
      if (!saved) {
        _formError = appState.error;
      } else {
        _formSuccess = '连接成功,已读取 ${appState.library.totalSongs} 首曲目。';
        if (backToManage) _editing = false;
      }
    });

    if (backToManage) {
      // 表单那句「连接成功」随表单一起收掉了,这里补一句 ——
      // 保存是个主动动作,做完总得有个回执。
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('已保存,正在用新配置读取曲库'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 补全协议头。用户常只填 `192.168.10.4:4533`,直接拼 URL 会解析失败。
  static String? _normalizeUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  /// 从地址里起个线路名 —— 内网地址标「内网」,其余标「公网」。
  static String _routeNameFor(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    if (_looksLocal(host)) return '局域网直连';
    return host;
  }

  /// 表单里那条「地址」拼成一条线路(名字与标记都从地址推)。
  static ServerRoute _routeFor(String url) => ServerRoute(
        id: 'route-1',
        name: _routeNameFor(url),
        url: url,
        tag: _tagFor(url),
      );

  static RouteTag _tagFor(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return _looksLocal(host) ? RouteTag.lan : RouteTag.wan;
  }

  /// 私有网段判定 —— 只为给线路起个像样的名字,不做任何安全判断。
  static bool _looksLocal(String host) {
    if (host == 'localhost' || host.startsWith('127.')) return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == null || second == null) return false;
    if (first == 10) return true;
    if (first == 192 && second == 168) return true;
    if (first == 172 && second >= 16 && second <= 31) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // 表单什么时候露:还没配过服务器(它就是正文),或者用户点了「服务器设置」。
    final showForm = !state.hasServer || _editing;

    return Scaffold(
      backgroundColor: context.nordic.bg,
      body: DismissKeyboardOnTap(
        // 这一屏用生 Scaffold 而不是 ImmersiveScaffold(它要自己排底部的胶囊),
        // 收键盘那一层就得自己包 —— 表单里有地址 / 账号 / 密码三个输入框。
        child: Stack(
          children: [
            Column(
              children: [
                NordicAppBar(
                  title: showForm && state.hasServer
                      ? (_creatingNew ? '添加服务器' : '服务器设置')
                      : (state.hasServer ? '服务器与线路' : '连接服务器'),
                  subtitle: showForm
                      ? (_creatingNew
                          ? (state.hasServer
                              // 说清代价:这一版一次只接一台,连上的是新的那台。
                              ? '接一台新的。本版一次只连一台,连上会替换当前这台'
                              : '填上你自己的音乐服务器')
                          : '改地址、账号或密码,保存后重连')
                      : '一个账号,多个地址',
                  big: false,
                  leading: IconButtonRound(
                    icon: Icons.arrow_back,
                    // 箭头就是「退出这一屏」,不兼职「退回管理页」——
                    // 表单里的取消有自己那颗按钮(按箭头会让人以为改了就算数)。
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Expanded(
                  child: showForm ? _formBody(state) : _manageBody(state),
                ),
              ],
            ),
            // 线路列表这一屏原型也浮着胶囊;**还没配服务器时的录入表单不给**
            // ——那是「添加服务器」那张表单,原型上同样没有。
            if (state.hasServer && !showForm)
              BottomStack(
                activeTab: null,
                onTabSelected: (tab) => openTab(context, tab),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------- 未配置:录入表单 ----------------

  Widget _formBody(AppState state) {
    final t = context.nordic;
    // 这张表单在**改现有那台**吗 —— 决定按钮的字,以及保存时要不要把现有
    // 那几条线路合回来。
    final editingExisting = _editing && !_creatingNew && state.hasServer;
    // 「取消」是「退回管理页」,与新填 / 改配置无关:表单叠在管理页上时都得有
    // 这条路(否则只能按返回箭头退出整屏)。
    final overManagePage = _editing && state.hasServer;

    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + NordicSpace.s6,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s5),
          child: Text(
            '支持 Navidrome、Subsonic / OpenSubsonic,以及飞牛音乐。'
            '不确定的话选 Subsonic,大多数兼容服务器都能用它接进来。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: t.fg2, height: 1.7),
          ),
        ),
        const SectionHeader(title: '接入类型'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
          child: Column(
            children: [
              for (final kind in ServerKind.values)
                _KindCard(
                  kind: kind,
                  selected: _kind == kind,
                  onTap: () => setState(() => _kind = kind),
                ),
            ],
          ),
        ),
        const SectionHeader(title: '账户'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
          child: Column(
            children: [
              NordicField(
                label: '显示名称',
                child: NordicTextField(
                  controller: _nameController,
                  hintText: '例如:客厅 Navidrome',
                ),
              ),
              const SizedBox(height: NordicSpace.s4),
              NordicField(
                label: '服务器地址',
                hint: '支持 http / https,可以是域名、IP 或 IPv6。',
                child: NordicTextField(
                  controller: _urlController,
                  hintText: 'http://192.168.10.4:4533',
                  prefixIcon: Icons.dns_outlined,
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: NordicSpace.s4),
              NordicField(
                label: '用户名',
                child: NordicTextField(
                  controller: _userController,
                  hintText: '服务器上的账号',
                  prefixIcon: Icons.person_outline,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: NordicSpace.s4),
              NordicField(
                label: '密码',
                hint: '密码只交给系统密钥库加密保存,登录时用它派生令牌,不保存明文。',
                child: NordicTextField(
                  controller: _passwordController,
                  hintText: '服务器密码',
                  obscure: true,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        if (_formError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NordicSpace.s5, NordicSpace.s5, NordicSpace.s5, 0),
            child: _Notice(message: _formError!, isError: true),
          ),
        if (_formSuccess != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NordicSpace.s5, NordicSpace.s5, NordicSpace.s5, 0),
            child: _Notice(message: _formSuccess!, isError: false),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NordicSpace.s5, NordicSpace.s6, NordicSpace.s5, NordicSpace.s4),
          child: Column(
            children: [
              PrimaryButton(
                // 从管理页进来的是**改**不是**连** —— 按钮上得说对这件事。
                label: _busy
                    ? (editingExisting ? '正在保存' : '正在连接')
                    : (editingExisting ? '保存并重新连接' : '连接'),
                icon: _busy
                    ? null
                    : (editingExisting ? Icons.check : Icons.link),
                onPressed: _canSubmit ? _connect : null,
              ),
              if (overManagePage) ...[
                const SizedBox(height: NordicSpace.s3),
                GhostButton(
                  label: '取消',
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() {
                            _formError = null;
                            _formSuccess = null;
                            _editing = false;
                            // 取消之后这张表单回到「改现有那台」的样子 ——
                            // 下次从「服务器设置」进来时别再当成新填一台。
                            _creatingNew = false;
                          });
                          // 扔掉的那半份改动也**从输入框里清掉**(见 [_prefillFrom])。
                          await _prefillFrom(state);
                        },
                ),
              ],
            ],
          ),
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: NordicSpace.s2),
            child: LoadingState(
              message: editingExisting ? '正在保存并重连' : '正在验证凭据并读取曲库',
              topPadding: 0,
            ),
          ),
      ],
    );
  }

  // ---------------- 已配置:管理 ----------------

  Widget _manageBody(AppState state) {
    final t = context.nordic;
    final server = state.server!;
    final active = state.activeRoute;

    return ListView(
      // 这一屏浮着播放坞 + 标签栏,列表要让出它的高度。
      padding: EdgeInsets.only(bottom: BottomStack.listInset(context)),
      children: [
        // 服务器概览卡。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NordicSpace.s5, NordicSpace.s2, NordicSpace.s5, NordicSpace.s2),
          child: Container(
            padding: const EdgeInsets.all(NordicSpace.s5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NordicRadius.xl),
              border: Border.all(color: t.line),
              gradient: LinearGradient(
                begin: const Alignment(-1, -1.2),
                end: const Alignment(0.6, 1),
                colors: [t.bg3, t.bg1],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(NordicRadius.md),
                        gradient: LinearGradient(
                          begin: const Alignment(-0.7, -1),
                          end: const Alignment(0.7, 1),
                          colors: [
                            Color.lerp(context.accent.accent, Colors.white, 0.12)!,
                            context.accent.accent,
                          ],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          server.kind.badge,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.03,
                            color: t.bg,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: NordicSpace.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            server.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: t.ok,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  '${server.kind.label} · ${server.username}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: t.fg3),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NordicSpace.s5),
                Divider(height: 1, color: t.line),
                const SizedBox(height: NordicSpace.s4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _Stat(
                        label: '正在使用',
                        value: active?.name ?? '未确定',
                        valueSize: 17,
                      ),
                    ),
                    _Stat(
                      label: '延迟',
                      value: _latencyLabel(state, active),
                      unit: _latencyUnit(state, active),
                      alignEnd: true,
                    ),
                    const SizedBox(width: NordicSpace.s5),
                    _Stat(
                      label: '曲库',
                      value: '${state.library.totalSongs}',
                      unit: '首',
                      alignEnd: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        SectionHeader(
          title: '线路',
          count: '${server.routes.length} 条',
          trailing: NordicChip(
            // 测速中要给状态:局域网一次 ping 是个位数毫秒,不变的话
            // 用户只会觉得「按了没反应」(真机反馈过这一条)。
            label: state.pinging
                ? '测速中'
                : state.pings.isEmpty
                    ? '测速'
                    : '重新测速',
            icon: Icons.refresh,
            height: 30,
            selected: state.pinging,
            onTap: state.pinging ? null : () => _pingAll(state),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
          child: Container(
            decoration: BoxDecoration(
              color: t.glass3,
              borderRadius: BorderRadius.circular(NordicRadius.lg),
              border: Border.all(color: t.line2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < server.routes.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: t.line),
                  _RouteManageRow(
                    route: server.routes[i],
                    ping: state.pings[server.routes[i].id],
                    pinging: state.pinging,
                    selected: server.routes[i].id == active?.id,
                    onSelect: () => _selectRoute(state, server.routes[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NordicSpace.s5, NordicSpace.s4, NordicSpace.s5, 0),
          child: GhostButton(
            label: '添加线路地址',
            icon: Icons.add,
            onPressed: () => AppRoutes.openAddRoute(context),
          ),
        ),
        // 账号 / 密码 / 地址的入口。原先这一屏只有线路能改 ——
        // 「服务器设置」这张表单写完就没再露过面(`_formBody` 只在没配过服务器时出现),
        // 于是改个地址得把服务器移除重加一遍。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NordicSpace.s5, NordicSpace.s3, NordicSpace.s5, 0),
          child: GhostButton(
            label: '服务器设置',
            icon: Icons.tune,
            onPressed: () async {
              setState(() {
                _formError = null;
                _formSuccess = null;
                _editing = true;
                // 这条路是**改现有那台** —— 之前那张表单可能是「添加服务器」
                // 那条路留下的标记,不清掉的话进来会是一张空白表单。
                _creatingNew = false;
              });
              // 填回现有的值(上一次可能是新填一台上半途退出来的)。
              await _prefillFrom(state);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NordicSpace.s5, NordicSpace.s6, NordicSpace.s5, 0),
          child: Text(
            '一个账号可以配多条线路,客户端按延迟自动择优。内外网各留一条,'
            '出门也能听。点一条线路就锁定它,再点一下解除、回到自动择优。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: t.fg3, height: 1.7),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NordicSpace.s5, NordicSpace.s6, NordicSpace.s5, 0),
          child: GhostButton(
            label: '移除该服务器',
            icon: Icons.delete_outline,
            onPressed: () => _confirmRemove(state),
          ),
        ),
      ],
    );
  }

  String _latencyLabel(AppState state, ServerRoute? route) {
    if (route == null) return '--';
    final ping = state.pings[route.id];
    if (ping == null) return '--';
    if (!ping.isOk) return '不可用';
    return '${ping.latency?.inMilliseconds ?? '--'}';
  }

  /// 测速,并在结束时说一句结果 —— 否则数字没变就等于什么都没发生。
  Future<void> _pingAll(AppState state) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final pings = await state.refreshRouteLatency();
    if (!mounted) return;

    final route = state.activeRoute;
    final ping = route == null ? null : pings[route.id];
    final where = route == null
        ? '没有可用线路'
        : (ping?.isOk ?? false)
            ? '当前走 ${route.name} · ${ping!.latency!.inMilliseconds}ms'
            : '当前走 ${route.name} · 不可用';
    messenger?.showSnackBar(
      SnackBar(content: Text('测速完成 · $where'), duration: const Duration(seconds: 2)),
    );
  }

  String? _latencyUnit(AppState state, ServerRoute? route) {
    if (route == null) return null;
    final ping = state.pings[route.id];
    return ping != null && ping.isOk ? 'ms' : null;
  }

  /// 锁定某条线路。锁定是单选 —— 同时取消其它线路的选中;
  /// **再点锁定中的那条就是解锁**(回到自动择优)。只有「锁」没有「解」的话,
  /// 点错了就再也回不去自动择优。
  Future<void> _selectRoute(AppState state, ServerRoute route) async {
    final unlocking = route.selected;
    final routes = (state.server?.routes ?? const <ServerRoute>[])
        .map((r) => r.copyWith(selected: unlocking ? false : r.id == route.id))
        .toList();
    await state.updateRoutes(routes);
  }

  Future<void> _confirmRemove(AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.nordic.glass3,
        title: const Text('移除这台服务器?'),
        content: Text(
          '本机保存的地址与凭据会被清除。服务器上的音乐不受影响,'
          '以后可以重新添加。',
          style: Theme.of(dialogContext).textTheme.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '移除',
              style: TextStyle(color: context.nordic.bad),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await state.disconnect();
  }
}

/// 接入类型卡片 —— `.card` 的单选形态。
class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final ServerKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final accent = context.accent.accent;

    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        margin: const EdgeInsets.only(bottom: NordicSpace.s3),
        padding: const EdgeInsets.all(NordicSpace.s4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NordicRadius.lg),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.46) : t.line,
          ),
          color: selected ? accent.withValues(alpha: 0.08) : t.fill1,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NordicRadius.md),
                gradient: LinearGradient(
                  begin: const Alignment(-0.7, -1),
                  end: const Alignment(0.7, 1),
                  colors: [
                    Color.lerp(accent, Colors.white, 0.12)!,
                    accent,
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  kind.badge,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.03,
                    color: t.bg,
                  ),
                ),
              ),
            ),
            const SizedBox(width: NordicSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind.label,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    kind.description,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: t.fg3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NordicSpace.s2),
            if (selected)
              NordicTick(selected: true)
            else
              Icon(Icons.chevron_right, size: 18, color: t.fg3),
          ],
        ),
      ),
    );
  }
}

/// 管理页里的线路行。
class _RouteManageRow extends StatelessWidget {
  const _RouteManageRow({
    required this.route,
    required this.ping,
    required this.selected,
    required this.onSelect,
    this.pinging = false,
  });

  final ServerRoute route;
  final RoutePing? ping;
  final bool selected;
  final VoidCallback onSelect;

  /// 正在测速 —— 这一行的延迟位置显示「测速中」,而不是旧数字。
  final bool pinging;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final failed = ping != null && !ping!.isOk;

    return Pressable(
      onTap: onSelect,
      pressedDecoration: BoxDecoration(color: t.fill1),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NordicSpace.s5, vertical: NordicSpace.s4),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: failed ? t.bad : (ping == null ? t.fg4 : t.ok),
              ),
            ),
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
                      _Tag(label: route.tag.label),
                      // 锁定的那条标「已锁定」而不是「使用中」:它俩说的是两件事,
                      // 而点一下的结果不同(锁着的点了解锁,没锁的点上锁)。
                      if (route.selected) ...[
                        const SizedBox(width: 6),
                        _Tag(label: '已锁定', highlight: true),
                      ] else if (selected) ...[
                        const SizedBox(width: 6),
                        _Tag(label: '使用中', highlight: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    route.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.fg4,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NordicSpace.s3),
            if (ping?.isOk ?? false) ...[
              SignalBars(bars: SignalBars.forLatency(ping!.latency)),
              const SizedBox(width: NordicSpace.s4),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  pinging
                      ? '测速中'
                      : failed
                          ? '不可用'
                          : ping == null
                              ? '未测速'
                              : '${ping!.latency!.inMilliseconds}',
                  style: TextStyle(
                    fontSize: failed ? 13 : 16,
                    fontWeight: FontWeight.w700,
                    color: failed ? t.bad : t.fg,
                  ),
                ),
                if (!pinging && !failed && ping != null)
                  Text('ms', style: TextStyle(fontSize: 10, color: t.fg4)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? context.accent.accent.withValues(alpha: 0.18)
            : t.fill2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: highlight ? context.accentSafe : t.fg3,
        ),
      ),
    );
  }
}

/// 概览卡里的一格统计。
class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.unit,
    this.valueSize = 21,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final String? unit;
  final double valueSize;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: t.fg3, letterSpacing: 0.02),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: valueSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.03,
                  color: t.fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.fg3,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 表单提示条。
class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final tone = isError ? t.bad : t.ok;

    return Container(
      padding: const EdgeInsets.all(NordicSpace.s4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NordicRadius.md),
        color: tone.withValues(alpha: 0.11),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: tone,
          ),
          const SizedBox(width: NordicSpace.s3),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: t.fg,
                    height: 1.6,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}