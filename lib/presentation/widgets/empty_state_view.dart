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
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final hairline = isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    final resolvedAction = action ??
        (actionLabel != null && onAction != null
            ? OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                    side: BorderSide(color: hairline, width: 1.0),
                  ),
                  minimumSize: const Size(0, AppTokens.kControlHeight),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              )
            : null);

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisAlignment: mainAxisAlignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: iconColor ?? textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
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
              const SizedBox(height: 16),
              resolvedAction,
            ],
            if (footer != null) ...[
              const SizedBox(height: 16),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
