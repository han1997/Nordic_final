
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/media_cache.dart';
import '../../data/music_source.dart';
import '../../data/server_config.dart';
import '../../playback/quality.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/theme_mode.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../shell/bottom_stack.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/rows.dart';
import 'config_export_sheet.dart';
import 'cache_sheet.dart';
import 'quality_sheet.dart';
import 'scan_sheet.dart';

/// 这一屏真正订阅的那几件 `AppState` 数据。
///
/// **别换回 `watch<AppState>()`。** 下载进度最多每秒播报四次、缓存淘汰也会播报,
/// 而它们一件都不在这张表里 —— 记录按**值**比较,于是那些通知到不了这一屏。
/// 表里每一件都必须是 build 体(含它调用的私有方法)真正读到的,漏一件就是
/// 那一件不再更新。**注意收的是「算好的标量」而不是那一整条列表**:
/// 下载进度每跳一次都会换掉列表里的 job 对象,收 `downloads` 整条等于白收。
typedef _SettingsView = ({
  bool autoRoute,
  bool backgroundPlay,
  ServerConfig? server,
});

/// 设置 —— 外观 / 播放 / 服务器 / 下载 / 隐私。
///
/// 这里的每一个开关都**真的生效并落盘**,不做「点了变个样子」的假开关。
/// 播放时后台运行那一项对应 audio_service 的前台服务;主题那一项换的是
/// 整个应用的两套 token。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 开关与跳转是动作,用取值函数(不参与重建判定)。
    final state = context.read<AppState>();
    final quality = context.select<QualityController, QualityOption>(
      (c) => c.value,
    );
    final view = context.select<AppState, _SettingsView>((s) => (
          autoRoute: s.autoRoute,
          backgroundPlay: s.backgroundPlay,
          server: s.server,
        ));

    return Scaffold(
      backgroundColor: context.nordic.bg,
      body: DismissKeyboardOnTap(
        child: ListView(
          padding: EdgeInsets.only(
            bottom: BottomStack.listInset(context),
          ),
          children: [
            NordicAppBar(
              title: '设置',
              subtitle: 'Nordic',
            ),
            const _ThemeSection(),
            const SectionHeader(title: '播放'),
            NordicCard(
              children: [
                NordicIconRow(
                  icon: Icons.graphic_eq,
                  title: '默认转码质量',
                  subtitle: quality.description,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        quality.name,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.nordic.fg2,
                            ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 17, color: context.nordic.fg3),
                    ],
                  ),
                  onTap: () => showQualitySheet(context),
                ),
                NordicIconRow(
                  icon: Icons.route_outlined,
                  title: '线路自动择优',
                  subtitle: view.autoRoute ? '按延迟选择最快可用地址' : '每条线路要手动锁定',
                  trailing: NordicSwitch(
                    value: view.autoRoute,
                    onChanged: state.setAutoRoute,
                  ),
                ),
                NordicIconRow(
                  icon: Icons.notifications_none,
                  title: '播放时后台运行',
                  subtitle: view.backgroundPlay
                      ? '通知栏与锁屏可控制'
                      : '切到后台即暂停',
                  trailing: NordicSwitch(
                    value: view.backgroundPlay,
                    onChanged: state.setBackgroundPlay,
                  ),
                ),
              ],
            ),
            const SectionHeader(title: '服务器'),
            NordicCard(
              children: [
                NordicIconRow(
                  icon: Icons.dns_outlined,
                  title: view.server?.name ?? '还没有连接服务器',
                  subtitle: view.server == null
                      ? '填上地址、账号与密码就能开始'
                      : '${view.server!.kind.label} · '
                          '${view.server!.routes.length} 条线路',
                  // 右边明说点进去是什么。原先只有一颗箭头,而这一屏里
                  // 「服务器」到底是**改配置**还是**只看线路**说不清 ——
                  // 点进去能改的其实是账号 / 密码 / 地址那整张表单。
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '服务器与线路',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: context.nordic.fg3),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 18, color: context.nordic.fg3),
                    ],
                  ),
                  onTap: () => AppRoutes.openServers(context),
                ),
                NordicIconRow(
                  icon: Icons.add_circle_outline,
                  title: '添加服务器',
                  subtitle: '用另一个账号或另一台机器',
                  trailing: Icon(Icons.chevron_right,
                      size: 18, color: context.nordic.fg3),
                  // 直接落在表单上 —— 用户已经说了要填新的,不必再自己找一下
                  // 「服务器设置」(那是改现有配置的入口)。
                  onTap: () => AppRoutes.openServers(context, form: true),
                ),
                NordicIconRow(
                  icon: Icons.qr_code_scanner,
                  title: '扫码同步',
                  subtitle: '扫码或粘贴，把服务器与线路带到这台设备',
                  trailing: Icon(Icons.chevron_right,
                      size: 18, color: context.nordic.fg3),
                  onTap: () => AppRoutes.openSync(context),
                ),
                // 只在真连着的时候出现。[NordicIconRow] 没有禁用态,给一个
                // `onTap: null` 的行既不置灰也不回弹,读起来就是个坏按钮。
                // 曲库扫描 —— 这一行原先**只存在于文案里**:首页 / 音乐库 / 搜索的
                // 空态都写着「到设置里重新扫描一次曲库」,而设置里没有这一条。
                if (view.server != null) const _ScanRow(),
                if (view.server != null)
                  NordicIconRow(
                    icon: Icons.qr_code_2,
                    title: '导出配置',
                    subtitle: '二维码 · 可复制成一段文本',
                    trailing: Icon(Icons.chevron_right,
                        size: 18, color: context.nordic.fg3),
                    onTap: () => showConfigExportSheet(context),
                  ),
              ],
            ),
            const _StorageSection(),
            const SectionHeader(title: '关于'),
            NordicCard(
              children: [
                NordicIconRow(
                  icon: Icons.info_outline,
                  title: '关于 Nordic',
                  subtitle: '版本 · 开源许可 · 服务器与隐私',
                  trailing: Icon(Icons.chevron_right,
                      size: 18, color: context.nordic.fg3),
                  onTap: () => AppRoutes.openAbout(context),
                ),
              ],
            ),
            const SizedBox(height: NordicSpace.s6),
          ],
        ),
      ),
    );
  }
}

/// 存储:听过顺手留下的(缓存)与点名要下的(下载)。
///
/// 这两件事原先各占一栏,可它们回答的是同一个问题 ——「盘上有什么」。
/// 摆在一起才看得出来「清缓存」清掉的是哪一半(下载**不受影响**)。
///
/// 这一块自己 select 它真正显示的那几件:**下载进度最多每秒播报四次**,
/// 那不该把上面那几栏(主题 / 播放 / 服务器 / 关于)也跟着重建。
/// 收的仍是算好的标量,不是那整条列表 —— 进度每跳一次都会换掉列表里的 job 对象。
class _StorageSection extends StatelessWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final (limit, used) = context
        .select<AppState, (CacheLimit, int)>((s) => (s.cacheLimit, s.cacheUsedBytes));
    final (downloadCount, active, wifiOnly) =
        context.select<AppState, (int, int, bool)>(
      (s) => (s.downloads.length, s.activeDownloadCount, s.wifiOnlyDownload),
    );
    final state = context.read<AppState>();

    return Column(
      children: [
        const SectionHeader(title: '存储'),
        NordicCard(
          children: [
            NordicIconRow(
              icon: Icons.storage_outlined,
              title: '歌曲缓存',
              subtitle: limit.isOff
                  ? '已关闭：听过的歌每次都从服务器拉'
                  : '听过的歌留在本机，再听不用重新拉',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    limit.label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: t.fg2),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: t.fg3),
                ],
              ),
              onTap: () => showCacheSheet(context),
            ),
            NordicIconRow(
              icon: Icons.album_outlined,
              title: '已用空间',
              // 关掉缓存那一刻占用会被清成 0,但**账还没数到**的窗口里可能还有数 ——
              // 那种时候说「缓存里还没有东西」,而右边却挂着一颗「清除」,两句话
              // 自相矛盾。所以:占用非 0 就如实报数,上限只在缓存开着时才提。
              subtitle: switch ((used > 0, limit.isOff)) {
                (false, true) => '缓存已关闭，本机没有留下东西',
                (false, false) => '缓存里还没有东西',
                (true, true) => '占用 ${formatBytes(used)} · 缓存已关闭',
                (true, false) => '占用 ${formatBytes(used)} · 上限 ${limit.label}',
              },
              trailing: used == 0
                  ? null
                  : SizedBox(
                      width: 72,
                      child: GhostButton(
                        label: '清除',
                        height: 34,
                        onPressed: () => _clear(context),
                      ),
                    ),
            ),
            // 「仅 Wi-Fi 下载」原先挂在**播放**那一栏里 —— 它管的是下载,不是播放。
            NordicIconRow(
              icon: Icons.download_outlined,
              title: '下载管理',
              subtitle: downloadCount == 0
                  ? '队列是空的'
                  : '$active 个进行中 · $downloadCount 项',
              trailing: Icon(Icons.chevron_right, size: 18, color: t.fg3),
              onTap: () => AppRoutes.openDownloads(context),
            ),
            NordicIconRow(
              icon: Icons.wifi,
              title: '仅 Wi-Fi 下载',
              subtitle: wifiOnly ? '流量下不缓存' : '流量下也会预取',
              trailing: NordicSwitch(
                value: wifiOnly,
                onChanged: state.setWifiOnlyDownload,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 清缓存。**先问一句** —— 清掉的是「断网时还能听的那些」,
  /// 下次再听到是重新花流量拉一遍。
  Future<void> _clear(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.nordic.glass3,
        title: const Text('清除歌曲缓存？'),
        content: Text(
          '本机留着的 ${formatBytes(state.cacheUsedBytes)} 会删掉，'
          '其中断网时还能听的那些就听不到了 —— 下次播放会从服务器重新拉。'
          '点名下好的内容不受影响。',
          style: Theme.of(dialogContext).textTheme.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('清除', style: TextStyle(color: context.nordic.bad)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final freed = await state.clearCache();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('已清除缓存，释放 ${formatBytes(freed)}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// 「关于」那一栏的落地页在 about_screen.dart —— 这一屏只留入口。

/// 外观:主题三档(跟随系统 / 深色 / 浅色)。
class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    // 主题档位这一位**单独订阅**:换主题才重建这一块,别的通知(下载进度、
    // 缓存淘汰)到不了这里。
    final state = context.read<AppState>();
    final current = NordicThemeMode.byName(
      context.select<AppState, String?>((s) => s.themeModeName),
    );

    return Column(
      children: [
        const SectionHeader(title: '外观'),
        NordicCard(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NordicSpace.s4, NordicSpace.s3, NordicSpace.s4, NordicSpace.s4),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: NordicSpace.s3),
                    child: Row(
                      children: [
                        const SettingIcon(icon: Icons.contrast),
                        const SizedBox(width: NordicSpace.s3),
                        Expanded(
                          child: Text(
                            '主题',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SegmentedControl<NordicThemeMode>(
                    options: NordicThemeMode.values,
                    value: current,
                    labelOf: (m) => m.label,
                    onChanged: (mode) => state.setThemeModeName(mode.name),
                  ),
                  const SizedBox(height: NordicSpace.s2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      current == NordicThemeMode.follow
                          ? '跟随系统。深浅两套共用同一份结构，只换材质。'
                          : '深浅两套共用同一份结构，只换材质。',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: t.fg3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 设置页里「曲库扫描」那一行。
///
/// 副标题报服务器那边的状态,**但这一行自己不去问** —— 它在打开那张纸的时候
/// 问(`scan_sheet.dart`),问过之后这里就跟着显示。理由有两条:
///
///   1. 「进一次设置页 = 打一次服务器」是不该有的副作用(它在别的 tab 上也被保活);
///   2. 进了设置页还没点过那一行时,说「看看服务器上有没有新加的歌」是**真的**
///      —— 我们此刻确实不知道;编一个「未在扫描」出来才是假的。
///
/// 做成一个自己订阅的小组件,而不是往设置页那份 select 记录里再加一件:
/// 扫描状态与这一屏其余部分无关,加进那张表等于让主题 / 播放 / 服务器每一栏
/// 都跟着它重建(那张表的口径是「表里每一件都必须被 build 体读到」)。
class _ScanRow extends StatelessWidget {
  const _ScanRow();

  @override
  Widget build(BuildContext context) {
    final status = context.select<AppState, ScanStatus?>((s) => s.scanStatus);
    final String subtitle;
    if (status == null) {
      subtitle = '看看服务器上有没有新加的歌';
    } else if (status.scanning) {
      subtitle = '正在扫描 · 已扫 ${status.count ?? 0} 首';
    } else if (status.count != null) {
      subtitle = '上次扫到 ${status.count} 首 · 随时可以再扫';
    } else {
      subtitle = '看看服务器上有没有新加的歌';
    }

    return NordicIconRow(
      icon: Icons.refresh,
      title: '曲库扫描',
      subtitle: subtitle,
      trailing: Icon(Icons.chevron_right, size: 18, color: context.nordic.fg3),
      onTap: () => showScanSheet(context),
    );
  }
}