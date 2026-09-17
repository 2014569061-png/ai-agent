import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;
  final double iconSize;
  final Color? iconColor;
  final MainAxisAlignment mainAxisAlignment;
  final Widget? footer;
  final bool compact;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.all(32),
    this.iconSize = 40,
    this.iconColor,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.footer,
    this.compact = false,
  });

  const EmptyStateView.compact({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.all(16),
    this.iconSize = 32,
    this.iconColor,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.footer,
  }) : compact = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    final resolvedAction = action ??
        (actionLabel != null && onAction != null
            ? FilledButton.tonal(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: isDark
                      ? AppPalette.brandSoftDark
                      : AppPalette.brandSoftLight,
                  foregroundColor: AppPalette.brand,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusControl),
                    side: BorderSide(
                      color: isDark
                          ? AppPalette.brand.withValues(alpha: 0.24)
                          : AppPalette.brand.withValues(alpha: 0.18),
                      width: 0.8,
                    ),
                  ),
                  minimumSize: const Size(0, AppTokens.kControlHeight),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              )
            : null);

    final discSize = compact ? 52.0 : 64.0;

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisAlignment: mainAxisAlignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: discSize,
              height: discSize,
              decoration: BoxDecoration(
                color: isDark
                    ? AppPalette.brandSoftDark
                    : AppPalette.brandSoftLight,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? AppPalette.brand.withValues(alpha: 0.20)
                      : AppPalette.brand.withValues(alpha: 0.16),
                  width: 0.8,
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: iconColor ?? AppPalette.brand,
                ),
              ),
            ),
            SizedBox(height: compact ? 12 : 18),
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 15 : 17,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null && message!.isNotEmpty) ...[
              SizedBox(height: compact ? 4 : 8),
              Text(
                message!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.55,
                  color: textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (resolvedAction != null) ...[
              SizedBox(height: compact ? 12 : 16),
              resolvedAction,
            ],
            if (footer != null) ...[
              SizedBox(height: compact ? 12 : 16),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
