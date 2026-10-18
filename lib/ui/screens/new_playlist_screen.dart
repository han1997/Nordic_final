import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/music_source.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../shell/shell.dart';
import '../widgets/components.dart';
import '../widgets/cover.dart';
import '../widgets/states.dart';

/// 新建歌单 —— 名字与封面色实时反映在预览卡上。
///
/// **如实告知能力边界**:本地这一轮不建真歌单到服务器(建歌单要写
/// `createPlaylist`,而歌单的封面色 Navidrome 也不支持自定义)。
/// 所以这里说明「会创建在哪里」,不假装那条封面色真的会被存下来。
class NewPlaylistScreen extends StatefulWidget {
  const NewPlaylistScreen({super.key});

  @override
  State<NewPlaylistScreen> createState() => _NewPlaylistScreenState();
}

class _NewPlaylistScreenState extends State<NewPlaylistScreen> {
  final _nameController = TextEditingController();
  int _hue = 268;
  bool _creating = false;

  /// 可选色相。与原型「新建歌单」的色板同一组。
  static const _hues = [268, 210, 168, 24, 336, 44, 186];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canCreate => _nameController.text.trim().isNotEmpty && !_creating;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final name = _nameController.text.trim();

    return ImmersiveScaffold(
      accent: context.accent,
      showAmbient: false,
      child: Column(
        children: [
          NordicAppBar(
            title: '新建歌单',
            big: false,
            leading: IconButtonRound(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              PillButton(
                label: _creating ? '创建中' : '创建',
                solid: true,
                onPressed: _canCreate ? _create : null,
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + NordicSpace.s6,
              ),
              children: [
                // 预览卡:名字与颜色实时跟着走。
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NordicSpace.s5, NordicSpace.s4, NordicSpace.s5, 0),
                  child: Container(
                    padding: const EdgeInsets.all(NordicSpace.s4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(NordicRadius.xl),
                      border: Border.all(color: t.line),
                      gradient: LinearGradient(
                        begin: const Alignment(-1, -1.2),
                        end: const Alignment(0.6, 1),
                        colors: [t.bg3, t.bg1],
                      ),
                    ),
                    child: Row(
                      children: [
                        Cover(
                          coverArtId: null,
                          seed: 'playlist-$_hue',
                          size: 92,
                          radius: 20,
                        ),
                        const SizedBox(width: NordicSpace.s4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name.isEmpty ? '未命名歌单' : name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                name.isEmpty ? '起个名字就能创建' : '0 首 · 等待添加',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: t.fg2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NordicSpace.s5, NordicSpace.s5, NordicSpace.s5, 0),
                  child: NordicField(
                    label: '歌单名称',
                    hint: '创建后可以先加几首打底，以后随时从歌曲菜单里追加。',
                    child: NordicTextField(
                      controller: _nameController,
                      hintText: '例如：深夜驾驶',
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NordicSpace.s5, NordicSpace.s5, NordicSpace.s5, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          '封面配色',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  fontWeight: FontWeight.w600, color: t.fg3),
                        ),
                      ),
                      Row(
                        children: [
                          for (final hue in _hues)
                            Padding(
                              padding:
                                  const EdgeInsets.only(right: NordicSpace.s3),
                              child: _Swatch(
                                hue: hue,
                                selected: hue == _hue,
                                onTap: () => setState(() => _hue = hue),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: NordicSpace.s3),
                      Text(
                        '服务器不支持自定义歌单封面，这里选的是本机显示用的配色 —— '
                        '同一账号在别的设备上看到的会是自动生成的封面。',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: t.fg3, height: 1.6),
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

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _creating = true);
    final state = context.read<AppState>();

    try {
      await state.createPlaylist(name);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('「$name」已创建'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on MusicSourceException catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(e.message), duration: const Duration(seconds: 3)),
      );
    }
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.hue, required this.selected, required this.onTap});

  final int hue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = HSLColor.fromAHSL(1, hue.toDouble(), 0.68, 0.66).toColor();
    final c1 = HSLColor.fromAHSL(1, hue.toDouble(), 0.42, 0.30).toColor();
    final c2 = HSLColor.fromAHSL(1, hue.toDouble(), 0.48, 0.12).toColor();

    return Pressable(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: const Alignment(-0.7, -1),
            end: const Alignment(0.7, 1),
            colors: [Color.lerp(c1, accent, 0.25)!, c2],
          ),
          border: Border.all(
            color: selected ? context.nordic.fg : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }
}