import 'package:flutter/material.dart';

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
    this.iconSize = 72,
    this.iconColor,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedAction = action ??
        (actionLabel != null && onAction != null
            ? OutlinedButton(onPressed: onAction, child: Text(actionLabel!))
            : null);
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisAlignment: mainAxisAlignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: iconSize,
                color: iconColor ??
                    theme.colorScheme.primary.withValues(alpha: 0.2)),
            const SizedBox(height: 24),
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(message!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
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
