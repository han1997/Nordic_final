
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
      body: ListView(
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
                trailing: Icon(Icons.chevron_right,
                    size: 18, color: context.nordic.fg3),
                onTap: () => AppRoutes.openServers(context),
              ),
            ],
          ),
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
    return InkWell(
      onTap: onTap,
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}