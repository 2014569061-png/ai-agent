import 'package:flutter/material.dart';

/// 统一的二级页面头部组件 (NexusPageHeader)
/// 统一样式：返回按钮、主标题、副标题/状态徽标、右侧操作区与底部指示器。
class NexusPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const NexusPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.statusPill,
    this.leading,
    this.actions,
    this.bottom,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final Widget? statusPill;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0.0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      leading: leading ??
          (canPop
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  tooltip: '返回',
                  onPressed: onBack ?? () => Navigator.maybePop(context),
                )
              : null),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 17,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (statusPill != null) ...[
            const SizedBox(width: 8),
            statusPill!,
          ],
        ],
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}
