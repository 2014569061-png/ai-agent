import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// 胶囊右侧的操作项。
class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.label, this.icon, this.onPressed});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: .07)
          : Colors.black.withValues(alpha: .05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.smallControlRadius), // 14
        side: BorderSide(color: border.withValues(alpha: .5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.smallControlRadius),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minHeight: 36), // 视觉 36；语义目标 >=44 由外层 padding 补足
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 14),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
