import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'context_ext.dart';
import 'tokens.dart';

/// 磨砂玻璃材质 —— `styles.css` 里 `.glass` / `.glass-panel` / `.glass-thin` 的等价物。
///
/// 三层做法:半透明底 + 模糊身后 + **上缘一道高光内描边**。
/// 那道高光是玻璃感的关键 —— 没有它,半透明色块只会读成「一块灰」。
///
/// 注意:玻璃必须真的**浮在内容之上**才有东西可模糊。放在正常流里、
/// 身后是空的,模糊出来只是一块灰。
class NordicGlass extends StatelessWidget {
  const NordicGlass({
    super.key,
    required this.child,
    this.panel = NordicGlassPanel.thin,
    this.borderRadius,
    this.border = true,
  });

  final Widget child;
  final NordicGlassPanel panel;

  /// 未指定时跟随面板默认圆角。
  final BorderRadius? borderRadius;

  final bool border;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    final spec = switch (panel) {
      // 面板玻璃:卡片 / 弹层 / 分段控件 —— 底下的内容透得最少,文字最稳。
      NordicGlassPanel.panel => (t.glass3, t.blur, NordicRadius.lg, true),
      // 薄玻璃:输入框 / 筛选胶囊 —— 能透出较多背景,但不承载长文本。
      NordicGlassPanel.thin => (t.glass4, t.blurSm, NordicRadius.full, false),
      // 导航玻璃:播放坞 / 标签栏 —— 常驻且要压住滚过去的列表。
      NordicGlassPanel.nav => (t.glass, t.blur, NordicRadius.full, true),
    };
    final fill = spec.$1;
    final blur = spec.$2;
    final radius = borderRadius ?? BorderRadius.circular(spec.$3);
    final wantsShadow = spec.$4;

    return DecoratedBox(
      // 外部那道深度影放在**裁剪外面** —— 放里面的话,圆角一裁就没了
      // (这正是它一直没出现过的一半原因)。
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          if (wantsShadow)
            BoxShadow(
              color: t.depth,
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          // **只能是裸模糊**。原先这里是
          // `ImageFilter.compose(outer: 饱和度矩阵, inner: blur)` —— 真机上
          // 那条路不生效:坞背后的曲目文字照样清晰可读(见真机截图),
          // 而 80% 不透明叠 34px 模糊本该把它糊成认不出的色块。
          //
          // 原型的 `saturate(1.8)` 只能跟着组合过滤器走,先放下 ——
          // 用「模糊真的生效」换「玻璃灰一点点」。若之后确实嫌灰,
          // 再给 fill 掺一点强调色(那是另一件事)。
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              border: border ? Border.all(color: t.line2, width: 1) : null,
            ),
            child: Stack(
              children: [
                child,
                // 上缘那道光 —— 玻璃感的关键。
                //
                // 原先它写成 `BoxShadow(offset: (0,1), spreadRadius: -0.5)`,
                // 但 BoxShadow **没有 inset 语义**:画出来是往盒子外面(下方)
                // 投的一道影,而且被圆角裁掉 —— 等于从来没出现过。
                // 这里改成贴顶边的一条 1px 实线(圆角处自然收细)。
                if (border)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: IgnorePointer(
                      child: SizedBox(
                        height: 1,
                        child: ColoredBox(color: t.glassRim),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

enum NordicGlassPanel {
  /// 卡片 / 弹层 / 分段控件。
  panel,

  /// 输入框 / 筛选胶囊。
  thin,

  /// 播放坞 / 标签栏。
  nav,
}

/// 玻璃上的 1px 发丝分隔线 —— `.divider`。
///
/// **两侧都留 `s5`**:原型那句 `margin: 0 var(--s5)` 就是这个意思。早先各处手写的
/// `Divider(...)` 只写了 `indent`(或者一整个都没写、或者由外层再包一层 Padding),
/// 与原型对不上 —— 收成一份,两侧的留白只有一处说法。
class NordicDivider extends StatelessWidget {
  const NordicDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: NordicSpace.s5,
        endIndent: NordicSpace.s5,
        color: context.nordic.line,
      );
}
