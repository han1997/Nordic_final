import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import 'components.dart';

/// 加载中。
///
/// 刻意**不是**骨架屏:骨架屏在一屏列表上看着像「内容已经在路上了」,
/// 但这里往往要等好几秒的网络往返,骨架会一直空着,反而更焦虑。
/// 一个居中的转圈 + 一行说明,诚实地表达「正在取」。
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message = '正在读取音乐库', this.topPadding = 120});

  final String message;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        NordicSpace.s6,
        topPadding,
        NordicSpace.s6,
        NordicSpace.s6,
      ),
      child: Column(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.accentSafe,
              backgroundColor: t.line2,
            ),
          ),
          const SizedBox(height: NordicSpace.s4),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 出错。
///
/// **不叠加空态** —— 出错了就说出了什么事,不要再说「暂无内容」。
/// 认证失败时按钮是「去设置凭据」而不是「重试」:密码错了重试一百次也一样,
/// 让用户做那件真正有用的事。
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.isAuthFailure = false,
    this.onRetry,
    this.onOpenSettings,
    this.topPadding = 120,
  });

  final String message;
  final bool isAuthFailure;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        NordicSpace.s5,
        topPadding,
        NordicSpace.s5,
        NordicSpace.s5,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(NordicSpace.s5),
            decoration: BoxDecoration(
              color: t.fill1,
              borderRadius: BorderRadius.circular(NordicRadius.lg),
              border: Border.all(color: t.line),
            ),
            child: Column(
              children: [
                Icon(
                  isAuthFailure ? Icons.lock_outline : Icons.cloud_off_outlined,
                  size: 28,
                  color: isAuthFailure ? t.warn : t.bad,
                ),
                const SizedBox(height: NordicSpace.s4),
                Text(
                  isAuthFailure ? '登录被拒绝' : '连不上服务器',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: NordicSpace.s2),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(height: 1.6),
                ),
                const SizedBox(height: NordicSpace.s5),
                if (isAuthFailure && onOpenSettings != null)
                  PrimaryButton(
                    label: '检查服务器设置',
                    icon: Icons.settings_outlined,
                    height: 46,
                    onPressed: onOpenSettings,
                  )
                else if (onRetry != null)
                  PrimaryButton(
                    label: '重试',
                    icon: Icons.refresh,
                    height: 46,
                    onPressed: onRetry,
                  ),
              ],
            ),
          ),
          if (isAuthFailure) ...[
            const SizedBox(height: NordicSpace.s4),
            Text(
              '凭据存在本机的系统密钥库里,不会上传。到设置里改一次就能继续。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// 全局顶部的气泡提示 —— `.toast`。
/// 用 overlay 而不是 SnackBar:SnackBar 会顶起底部内容,而底部常驻着播放坞。
class NordicToast extends StatelessWidget {
  const NordicToast({super.key, required this.message, this.bottom = 168});

  final String message;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.8,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: t.glass,
              borderRadius: BorderRadius.circular(NordicRadius.full),
              border: Border.all(color: t.line2),
              boxShadow: [
                BoxShadow(
                  color: t.depth,
                  blurRadius: 36,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// 表单输入框 —— `.field .input`。聚焦时描边转成强调色。
class NordicField extends StatelessWidget {
  const NordicField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600, color: t.fg3),
          ),
        ),
        child,
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              hint!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(height: 1.55),
            ),
          ),
      ],
    );
  }
}

/// 单行输入框本体 —— `.input`。
class NordicTextField extends StatelessWidget {
  const NordicTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.obscure = false,
    this.keyboardType,
    this.prefixIcon,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String? hintText;
  final bool obscure;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: t.fill1,
        borderRadius: BorderRadius.circular(NordicRadius.md),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          if (prefixIcon != null) ...[
            Icon(prefixIcon, size: 18, color: t.fg3),
            const SizedBox(width: 11),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              onChanged: onChanged,
              autofocus: autofocus,
              enabled: enabled,
              style: Theme.of(context).textTheme.bodyLarge,
              cursorColor: context.accent.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: t.fg4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}