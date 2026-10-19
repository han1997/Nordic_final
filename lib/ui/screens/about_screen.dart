import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';

/// 关于 —— 设置里「关于」那一栏的落地页。
///
/// 它回答的是「这是什么软件、什么版本、我的东西在哪儿」。**只写真的**:
/// 版本号从**装上的那个包**里读([PackageInfo] 读出的就是 `pubspec.yaml`
/// 那一行落进包里的结果,不是另存的一份);名字、图标与启动器里那颗同源;
/// 隐私那两条是**陈述不是开关** —— 原先它们和一堆开关挨着,读起来像可以关掉。
///
/// **这一屏只有三件东西,是故意的**:版本在顶上、许可一条、隐私两条。
/// 早先这里还摆过「版本」「服务器」「默认转码质量」三行,后来全删了 ——
/// 它们分别与顶部、设置页「服务器」那一栏、设置页第一行说同一件事,
/// 摆在这里既不解释「这是什么软件」,又让这一页显得啰嗦。**别再加回来。**
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                    // 这两条**不是开关**:凭据怎么存、播放记录发到哪儿,都是这个应用
                    // 已经定死的行为,给一个可以关掉的开关才是骗人。
                    _InfoRow(
                      icon: Icons.shield_outlined,
                      title: '凭据仅存本机',
                      subtitle: '密码交给系统密钥库加密保存，不上传任何数据',
                    ),
                    Divider(height: 1, thickness: 1),
                    // 措辞按**实际行为**写(见 playback/scrobble.dart):开播报一次
                    // 「正在播放」、听够一半报一次「听过」。原先那句「只用于服务器端的
                    // 播放统计」在真的接了 scrobble 之前是一句空话 —— 现在它说的是真的。
                    _InfoRow(
                      icon: Icons.history,
                      title: '播放记录',
                      subtitle: '开播报一次「正在播放」，听够一半报一次「听过」——'
                          '只发给服务器，本机不另存',
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

/// `1.0.42+43` —— 与产物名里那一份**逐字相同**(tool/build.sh 也是从 pubspec
/// 拼出来的这个名字)。两处展示共用一份口径,免得一个带 build 号一个不带。
String versionLabel(PackageInfo info) => info.buildNumber.isEmpty
    ? info.version
    : '${info.version}+${info.buildNumber}';

/// 「关于」里的一行:图标 + 标题 + 说明。
///
/// 与设置页那张卡同一副骨架(`_SettingRow`),但没有开关、也没有右侧的值 ——
/// 这一屏上只剩下**陈述**(隐私那两条)与**一条去路**(开源许可),
/// 而每条陈述要说的话就是它自己那句说明。「版本」那一行删掉之后 `trailing`
/// 再没人用过,一并去掉,免得留一个永远空着的口子。
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
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