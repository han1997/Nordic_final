
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import 'cache_sheet.dart';
import 'quality_sheet.dart';

/// 设置 —— 外观 / 播放 / 服务器 / 下载 / 隐私。
///
/// 这里的每一个开关都**真的生效并落盘**,不做「点了变个样子」的假开关。
/// 播放时后台运行那一项对应 audio_service 的前台服务;主题那一项换的是
/// 整个应用的两套 token。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final quality = context.watch<QualityController>().value;

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
            _ThemeSection(state: state),
            const SectionHeader(title: '播放'),
            _Card(
              children: [
                _SettingRow(
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
                _SettingRow(
                  icon: Icons.route_outlined,
                  title: '线路自动择优',
                  subtitle: state.autoRoute ? '按延迟选择最快可用地址' : '每条线路要手动锁定',
                  trailing: NordicSwitch(
                    value: state.autoRoute,
                    onChanged: state.setAutoRoute,
                  ),
                ),
                _SettingRow(
                  icon: Icons.notifications_none,
                  title: '播放时后台运行',
                  subtitle: state.backgroundPlay
                      ? '通知栏与锁屏可控制'
                      : '切到后台即暂停',
                  trailing: NordicSwitch(
                    value: state.backgroundPlay,
                    onChanged: state.setBackgroundPlay,
                  ),
                ),
              ],
            ),
            const SectionHeader(title: '服务器'),
            _Card(
              children: [
                _SettingRow(
                  icon: Icons.dns_outlined,
                  title: state.server?.name ?? '还没有连接服务器',
                  subtitle: state.server == null
                      ? '填上地址、账号与密码就能开始'
                      : '${state.server!.kind.label} · '
                          '${state.server!.routes.length} 条线路',
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
                _SettingRow(
                  icon: Icons.add_circle_outline,
                  title: '添加服务器',
                  subtitle: '用另一个账号或另一台机器',
                  trailing: Icon(Icons.chevron_right,
                      size: 18, color: context.nordic.fg3),
                  // 直接落在表单上 —— 用户已经说了要填新的,不必再自己找一下
                  // 「服务器设置」(那是改现有配置的入口)。
                  onTap: () => AppRoutes.openServers(context, form: true),
                ),
              ],
            ),
            const SectionHeader(title: '缓存'),
            _CacheSection(state: state),
            const SectionHeader(title: '下载'),
            _Card(
              children: [
                _SettingRow(
                  icon: Icons.download_outlined,
                  title: '下载管理',
                  subtitle: state.downloads.isEmpty
                      ? '队列是空的'
                      : '${state.activeDownloadCount} 个进行中 · '
                          '${state.downloads.length} 项',
                  trailing: Icon(Icons.chevron_right,
                      size: 18, color: context.nordic.fg3),
                  onTap: () => AppRoutes.openDownloads(context),
                ),
                _SettingRow(
                  icon: Icons.wifi,
                  title: '仅 Wi-Fi 下载',
                  subtitle: state.wifiOnlyDownload ? '流量下不缓存' : '流量下也会预取',
                  trailing: NordicSwitch(
                    value: state.wifiOnlyDownload,
                    onChanged: state.setWifiOnlyDownload,
                  ),
                ),
              ],
            ),
            const SectionHeader(title: '隐私'),
            _Card(
              children: const [
                _SettingRow(
                  icon: Icons.shield_outlined,
                  title: '凭据仅存本机',
                  subtitle: '密码交给系统密钥库加密保存,不上传任何数据',
                ),
                Divider(height: 1, thickness: 0.5),
                _SettingRow(
                  icon: Icons.history,
                  title: '播放记录',
                  subtitle: '只用于服务器端的播放统计,本机不另存一份',
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

/// 缓存:听过的歌留在本机的那一份。
///
/// 与「下载」分开成一栏,因为它们是两件事:下载是**点名要的**(不会被自动删,
/// 在 Nordic/Music 里看得见),缓存是**顺手留的**(上限一到就按最久没听淘汰)。
/// 摆在一起会让人以为「清缓存」会连下载一起清掉 —— 不会。
class _CacheSection extends StatelessWidget {
  const _CacheSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final limit = state.cacheLimit;
    final used = state.cacheUsedBytes;

    return _Card(
      children: [
        _SettingRow(
          icon: Icons.storage_outlined,
          title: '歌曲缓存',
          subtitle: limit.isOff
              ? '已关闭:听过的歌每次都从服务器拉'
              : '听过的歌留在本机,再听不用重新拉',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                limit.label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: context.nordic.fg2),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 17, color: context.nordic.fg3),
            ],
          ),
          onTap: () => showCacheSheet(context),
        ),
        _SettingRow(
          icon: Icons.album_outlined,
          title: '已用空间',
          // 关掉缓存那一刻占用会被清成 0,但**账还没数到**的窗口里可能还有数 ——
          // 那种时候说「缓存里还没有东西」,而右边却挂着一颗「清除」,两句话
          // 自相矛盾。所以:占用非 0 就如实报数,上限只在缓存开着时才提。
          subtitle: switch ((used > 0, limit.isOff)) {
            (false, true) => '缓存已关闭,本机没有留下东西',
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
      ],
    );
  }

  /// 清缓存。**先问一句** —— 清掉的是「断网时还能听的那些」,
  /// 下次再听到是重新花流量拉一遍。
  Future<void> _clear(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.nordic.glass3,
        title: const Text('清除歌曲缓存?'),
        content: Text(
          '本机留着的 ${formatBytes(state.cacheUsedBytes)} 会删掉,'
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
        content: Text('已清除缓存,释放 ${formatBytes(freed)}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// 外观:主题三档(跟随系统 / 深色 / 浅色)。
class _ThemeSection extends StatelessWidget {
  const _ThemeSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final current = NordicThemeMode.byName(state.themeModeName);

    return Column(
      children: [
        const SectionHeader(title: '外观'),
        _Card(
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
                          ? '跟随系统。深浅两套共用同一份结构,只换材质。'
                          : '深浅两套共用同一份结构,只换材质。',
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

/// 设置里的一张卡 —— `.card`,带发丝分隔线。
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: NordicSpace.s5),
      decoration: BoxDecoration(
        color: t.glass3,
        borderRadius: BorderRadius.circular(NordicRadius.lg),
        border: Border.all(color: t.line2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && children[i] is! Divider)
              Divider(height: 1, thickness: 1, color: t.line, indent: NordicSpace.s5),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 设置行 —— `.row`。图标 + 标题 + 说明 + 右侧控件。
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Pressable(
      onTap: onTap,
      pressedDecoration: BoxDecoration(color: t.fill1),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NordicSpace.s5, vertical: NordicSpace.s4),
        child: Row(
          children: [
            SettingIcon(icon: icon),
            const SizedBox(width: NordicSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.fg3),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: NordicSpace.s3),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
