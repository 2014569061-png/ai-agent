import 'package:flutter/material.dart';
import '../theme/desktop_theme.dart';

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
    final desktop = DesktopTheme.maybeOf(context);
    if (desktop != null) {
      return Center(
          child: SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: mainAxisAlignment,
              children: [
                Container(
                    padding: EdgeInsets.all(compact ? 12 : 18),
                    decoration: BoxDecoration(
                        color: desktop.selected,
                        borderRadius: BorderRadius.circular(18)),
                    child: Icon(icon,
                        size: iconSize, color: iconColor ?? desktop.accent)),
                SizedBox(height: compact ? 12 : 20),
                Semantics(
                    header: true,
                    child: Text(title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: desktop.text))),
                if (message?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(message!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(height: 1.6)),
                ],
                if (action != null ||
                    (actionLabel != null && onAction != null)) ...[
                  const SizedBox(height: 20),
                  action ??
                      FilledButton(
                          onPressed: onAction, child: Text(actionLabel!)),
                ],
                if (footer != null) ...[const SizedBox(height: 16), footer!],
              ]),
        ),
      ));
    }
    final scheme = Theme.of(context).colorScheme;
    final textColor = scheme.onSurface;
    final textMuted = scheme.onSurfaceVariant;
    final resolvedAction = action ??
        (actionLabel != null && onAction != null
            ? FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!))
            : null);

    final discSize = compact ? 40.0 : 48.0;
    final effectivePadding = padding == const EdgeInsets.all(32)
        ? const EdgeInsets.fromLTRB(24, 40, 24, 24)
        : padding;

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        primary: false,
        padding: effectivePadding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisAlignment: mainAxisAlignment,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: discSize,
                height: discSize,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: compact ? 24 : 28,
                    color: iconColor ?? scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: compact ? 15 : 17,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: textColor,
                    ),
                    textAlign: TextAlign.center,
                  )),
              if (message != null && message!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: TextStyle(
                    fontSize: 14,
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
      ),
    );
  }
}
