import 'package:flutter/material.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/nexus_surface.dart';

/// 聊天消息流“回到底部”悬浮按钮（带未读新消息数量指示）
class NexusBackToLatestButton extends StatelessWidget {
  final VoidCallback onTap;
  final int unreadCount;
  final bool isRunning;

  const NexusBackToLatestButton({
    super.key,
    required this.onTap,
    this.unreadCount = 0,
    this.isRunning = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = unreadCount > 0;
    final foreground = theme.colorScheme.onPrimary;
    final background = theme.colorScheme.primary;

    return Semantics(
      button: true,
      label: hasUnread ? '有 $unreadCount 条新消息，点击回到底部' : '回到底部',
      child: NexusSurface(
        level: SurfaceLevel.thick,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            child: Container(
              constraints:
                  const BoxConstraints(minHeight: AppTokens.kControlHeight),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                border: Border.all(
                  color: foreground.withValues(alpha: 0.28),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 16,
                    color: foreground,
                  ),
                  if (hasUnread) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: foreground.withValues(alpha: 0.18),
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusPill),
                      ),
                      child: Text(
                        '$unreadCount',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                  if (isRunning) ...[
                    const SizedBox(width: 6),
                    Text(
                      '生成中…',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ] else if (!hasUnread) ...[
                    const SizedBox(width: 4),
                    Text(
                      '回到底部',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
