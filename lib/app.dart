import 'package:flutter/material.dart';

import 'theme/context_ext.dart';
import 'theme/nordic_theme.dart';
import 'theme/theme_mode.dart';
import 'theme/tokens.dart';

/// 应用根。主题在这里定调,其余一切都在它之下。
class NordicApp extends StatefulWidget {
  const NordicApp({super.key});

  @override
  State<NordicApp> createState() => _NordicAppState();
}

class _NordicAppState extends State<NordicApp> {
  NordicThemeMode _mode = NordicThemeMode.follow;

  void setThemeMode(NordicThemeMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nordic',
      debugShowCheckedModeBanner: false,
      theme: NordicTheme.build(NordicTokens.light),
      darkTheme: NordicTheme.build(NordicTokens.dark),
      themeMode: _mode.material,
      home: _ThemeSmoke(screenMode: _mode, onModeChanged: setThemeMode),
    );
  }
}

/// 阶段 1 的自检页:确认 token、玻璃、氛围背景、主题切换都接对了。
/// 阶段 4 用真正的主壳替换它。
class _ThemeSmoke extends StatelessWidget {
  const _ThemeSmoke({required this.screenMode, required this.onModeChanged});

  final NordicThemeMode screenMode;
  final ValueChanged<NordicThemeMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NordicSpace.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nordic', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: NordicSpace.s2),
              Text('设计 token 自检', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: NordicSpace.s6),
              Wrap(
                spacing: NordicSpace.s3,
                runSpacing: NordicSpace.s3,
                children: [
                  for (final c in [
                    t.fg, t.fg2, t.fg3, t.fg4,
                    t.ok, t.warn, t.bad,
                    t.bg, t.bg1, t.bg2, t.bg3,
                  ])
                    _Swatch(color: c),
                ],
              ),
              const SizedBox(height: NordicSpace.s6),
              Wrap(
                spacing: NordicSpace.s3,
                children: [
                  for (final m in NordicThemeMode.values)
                    _ModeChip(
                      label: m.label,
                      selected: m == screenMode,
                      onTap: () => onModeChanged(m),
                    ),
                ],
              ),
              const Spacer(),
              Text('亮色 ${t.brightness == Brightness.light} · glow ${t.glow}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(NordicRadius.sm),
          border: Border.all(color: context.nordic.line2),
        ),
      );
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? t.fill3 : t.fill1,
          borderRadius: BorderRadius.circular(NordicRadius.full),
          border: Border.all(color: t.line2),
        ),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}