import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'immersive_sheet.dart';

/// 沉浸式动作表项配置
class ActionSheetItem<T> {
  const ActionSheetItem({
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.value,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
    this.isSectionHeader = false,
  });

  const ActionSheetItem.section(this.title)
      : subtitle = null,
        icon = null,
        leading = null,
        trailing = null,
        value = null,
        onTap = null,
        enabled = false,
        selected = false,
        destructive = false,
        isSectionHeader = true;

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final T? value;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;
  final bool destructive;
  final bool isSectionHeader;
}

/// 统一的沉浸式操作表 (ImmersiveActionSheet)
/// 消除 chat_page 及全站 6+ 处重复的 showImmersiveSheet + Column + ListTile 模板，
/// 提供统一的视觉层级、安全区、图标间距与交互反馈。
Future<T?> showImmersiveActionSheet<T>({
  required BuildContext context,
  String? title,
  String? subtitle,
  Widget? header,
  required List<ActionSheetItem<T>> items,
  Widget? footer,
  bool scrollable = false,
  double? maxHeightRatio,
}) {
  return showImmersiveSheet<T>(
    context: context,
    builder: (sheetContext) {
      final theme = Theme.of(context);
      final semantic = AppTheme.semanticOf(context);
      final hasHeader = title != null || subtitle != null || header != null;

      final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasHeader) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: header ??
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null)
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 17,
                          ),
                        ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: semantic.mutedOnGlass,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
            ),
            Divider(
              height: 1,
              thickness: 0.8,
              color: semantic.border.withValues(alpha: 0.5),
            ),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height *
                    (maxHeightRatio ?? 0.72),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: scrollable
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (itemCtx, index) {
                  final item = items[index];
                  if (item.isSectionHeader) {
                    return Padding(
                      padding:
                          EdgeInsets.fromLTRB(16, index == 0 ? 4 : 16, 16, 8),
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: semantic.mutedOnGlass,
                          letterSpacing: 0.3,
                        ),
                      ),
                    );
                  }
                  final itemColor = item.destructive
                      ? semantic.danger
                      : (item.selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface);

                  Widget? leading = item.leading;
                  if (leading == null && item.icon != null) {
                    leading = Icon(
                      item.icon,
                      size: 20,
                      color: item.destructive
                          ? semantic.danger
                          : (item.selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant),
                    );
                  }

                  Widget? trailing = item.trailing;
                  if (trailing == null && item.selected) {
                    trailing = Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    );
                  }

                  return ListTile(
                    dense: true,
                    enabled: item.enabled,
                    leading: leading,
                    title: Text(
                      item.title,
                      style: TextStyle(
                        fontWeight:
                            item.selected ? FontWeight.w500 : FontWeight.w400,
                        fontSize: 14,
                        color: item.enabled
                            ? itemColor
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                      ),
                    ),
                    subtitle: item.subtitle != null
                        ? Text(
                            item.subtitle!,
                            style: TextStyle(
                              fontSize: 12,
                              color: semantic.mutedOnGlass,
                            ),
                          )
                        : null,
                    trailing: trailing,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusControl),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    onTap: () {
                      Navigator.pop(sheetContext, item.value);
                      item.onTap?.call();
                    },
                  );
                },
              ),
            ),
          ),
          if (footer != null) ...[
            Divider(
              height: 1,
              thickness: 0.8,
              color: semantic.border.withValues(alpha: 0.5),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: footer,
            ),
          ],
        ],
      );

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        ),
      );
    },
  );
}
