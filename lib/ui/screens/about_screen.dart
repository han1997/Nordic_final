import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../data/server_config.dart';
import '../../playback/quality.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../routes.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';

/// 关于 —— 设置里「关于」那一栏的落地页。
///
/// 它回答的是「这是什么软件、什么版本、我的东西在哪儿」,而这三件事原先在设置里
/// 一个字都没有(版本号只存在于产物文件名里,隐私那两条陈述和一堆开关混在一屏)。
///
/// **这一屏只写真的**:版本号从**装上的那个包**里读([PackageInfo] 读出的就是
/// `pubspec.yaml` 那一行落进包里的结果,不是另存的一份);服务器那行读当前配置;
/// 隐私那两条是**陈述不是开关** —— 原先它们和开关挨着读起来像可以关掉的东西。
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    // 只订「服务器」这一件:别的通知(下载进度、缓存淘汰)与这一屏无关。
    final server = context.select<AppState, ServerConfig?>((s) => s.server);
    final quality = context.select<QualityController, QualityOption>(
      (c) => c.value,
    );

    return ImmersiveScaffold(
      accent: context.accent,
      showAmbient: false,
      child: Column(
        children: [
          NordicAppBar(
            title: '关于',
            big: false,
            leading: IconButtonRound(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: NordicSpace.s6),
              children: [
                const _Hero(),
                _Card(
                  children: [
                    const _VersionRow(),
                    Divider(height: 1, thickness: 1, color: t.line),
                    _InfoRow(
                      icon: Icons.dns_outlined,
                      title: server?.name ?? '还没有连接服务器',
                      subtitle: server == null
                          ? '填上地址、账号与密码就能开始'
                          : '${server.kind.label} · ${server.routes.length} 条线路',
                      onTap: () => AppRoutes.openServers(context),
                    ),
                    Divider(height: 1, thickness: 1, color: t.line),
                    // 「默认转码质量」当前那一档 —— 与设置页那一行同一件事的另一处
                    // 来路。**报的是所选档,不是此刻在用哪一档**:后者属于正在放的
                    // 那一首,在播放页上(见 playbackOriginLabel)。
                    _InfoRow(
                      icon: Icons.graphic_eq,
                      title: '默认转码质量',
                      subtitle: quality.description,
                      trailing: quality.name,
                    ),
                    Divider(height: 1, thickness: 1, color: t.line),
                    _InfoRow(
                      icon: Icons.book_outlined,
                      title: '开源许可',
                      subtitle: 'Flutter 与各第三方包各自的许可证',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Nordic',
                        applicationLegalese: '多平台 NAS 音乐播放器',
                        applicationIcon: const Padding(
                          padding: EdgeInsets.all(12),
                          child: _AppMark(size: 64),
                        ),
                      ),
                    ),
                  ],
                ),
                const SectionHeader(title: '隐私'),
                _Card(
                  children: const [
                    // 这两条**不是开关**:凭据怎么存、播放记录去哪儿,都是这个应用
                    // 已经定死的行为,给一个可以关掉的开关才是骗人。
                    _InfoRow(
                      icon: Icons.shield_outlined,
                      title: '凭据仅存本机',
                      subtitle: '密码交给系统密钥库加密保存，不上传任何数据',
                    ),
                    Divider(height: 1, thickness: 1),
                    _InfoRow(
                      icon: Icons.history,
                      title: '播放记录',
                      subtitle: '只用于服务器端的播放统计，本机不另存一份',
                    ),
                  ],
                ),
                const SizedBox(height: NordicSpace.s2),
                const ListNote(
                  'Nordic 连着的是**你自己的**服务器：歌在你的机器上，'
                  '播放统计也在你的机器上。远程仓库见 github.com/han1997/Nordic_final。',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部那一块:图标 + 名字 + 一句话 + 版本号。
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NordicSpace.s5, NordicSpace.s4, NordicSpace.s5, NordicSpace.s5),
      child: Column(
        children: [
          const _AppMark(size: 96),
          const SizedBox(height: NordicSpace.s4),
          Text(
            'Nordic',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            '多平台 NAS 音乐播放器',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: t.fg3),
          ),
          const SizedBox(height: 9),
          const _VersionText(),
        ],
      ),
    );
  }
}

/// 应用图标 —— 与启动器里那颗是**同一份产物**(`tool/app_icon.py` 生成,
/// Android 五档 mipmap 与 web 的 favicon / Icon-512 都从它出)。
///
/// 这里引的是 web 那份 512:它是同一次生成留下的文件,不另存一份。
class _AppMark extends StatelessWidget {
  const _AppMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.27),
      child: Image.asset(
        'web/icons/Icon-512.png',
        width: size,
        height: size,
        // 图标加载不出来也不该崩:这一屏上少一张图,其余信息照旧。
        errorBuilder: (context, _, _) => SizedBox(
          width: size,
          height: size,
          child: ColoredBox(color: context.nordic.glass4),
        ),
      ),
    );
  }
}

/// 版本号 —— 从**装上的那个包**里读。
///
/// 读不到就明说读不到(`—`):这一屏上写死一个版本号,换一版装上去就对不上了,
/// 而「这一页上的版本是不是装的那个」正是它唯一要回答的问题。
class _VersionText extends StatelessWidget {
  const _VersionText();

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final label = info == null ? '—' : versionLabel(info);
        return Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.w600, color: t.fg2),
        );
      },
    );
  }
}

/// 「关于」里那个版本行 —— 与顶部那份同一个值(两处都说同一件事)。
class _VersionRow extends StatelessWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return _InfoRow(
          icon: Icons.info_outline,
          title: '版本',
          subtitle: '与侧载包的名字同一份 —— 名字是从 pubspec.yaml 拼的',
          trailing: info == null ? '—' : versionLabel(info),
        );
      },
    );
  }
}

/// `1.0.42+43` —— 与产物名里那一份**逐字相同**(tool/build.sh 也是从 pubspec
/// 拼出来的这个名字)。两处展示共用一份口径,免得一个带 build 号一个不带。
String versionLabel(PackageInfo info) => info.buildNumber.isEmpty
    ? info.version
    : '${info.version}+${info.buildNumber}';

/// 「关于」里的一行:图标 + 标题 + 说明 + 右侧的值。
///
/// 与设置页那张卡同一副骨架(`_SettingRow`),但没有开关 —— 这一屏上除了两条
/// 去路(服务器 / 许可),其余都是**只读的陈述**。
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Pressable(
      onTap: onTap,
      pressedDecoration: BoxDecoration(color: t.fill1),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NordicSpace.s5,
          vertical: NordicSpace.s4,
        ),
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
              Text(
                trailing!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: t.fg2),
              ),
            ],
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: t.fg3),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「关于」里的一张卡 —— 与设置页那张同一副材质(那一张是私有的,这一屏
/// 照搬一层壳;两边哪天合并成一个共享组件也不亏)。
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
      child: Column(children: children),
    );
  }
}