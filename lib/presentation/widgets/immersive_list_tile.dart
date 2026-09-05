import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// 二级页面统一的列表行，提供图标、标题、副标题、可选开关/尾巴、内嵌式分隔。
/// 避免各页面各自用原始 ListTile + 硬编码字体颜色。
class ImmersiveListTile extends StatelessWidget {
  const ImmersiveListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.switchValue,
    this.onChanged,
    this.danger = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.showDivider = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool? switchValue;
  final ValueChanged<bool>? onChanged;
  final bool danger;
  final EdgeInsetsGeometry padding;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.semanticOf(context);
    final theme = Theme.of(context);
    final titleColor = danger
        ? colors.danger
        : (enabled ? colors.textPrimary : colors.textMuted);

    Widget content = Container(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 22,
              color: danger ? colors.danger : theme.colorScheme.primary,
            ),
            const SizedBox(width: AppTokens.spacingMd),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (switchValue != null) ...[
            _Switch(
                value: switchValue!, enabled: enabled, onChanged: onChanged),
          ] else if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      content = InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTokens.smallControlRadius),
        child: content,
      );
    }

    if (!showDivider) return content;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        Divider(
            height: 1,
            thickness: 1,
            color: colors.border.withValues(alpha: .5)),
      ],
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.enabled, this.onChanged});

  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}
