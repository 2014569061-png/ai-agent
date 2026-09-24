import 'package:flutter/material.dart';
import '../../motion/motion_preferences.dart';
import '../../motion/nexus_motion.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/nexus_pressable.dart';
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
    final reduceMotion = MotionPreferences.shouldReduceMotion(context);
    final duration = reduceMotion ? Duration.zero : NexusMotion.fast;

    return Semantics(
      button: true,
      label: hasUnread ? '有 $unreadCount 条新消息，点击回到底部' : '回到底部',
      child: AnimatedSize(
        duration: duration,
        reverseDuration: duration,
        curve: NexusMotion.curveStandard,
        alignment: Alignment.bottomRight,
        child: NexusSurface(
          level: SurfaceLevel.thick,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          child: NexusPressable(
            onTap: onTap,
            pressedScale: 0.96,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            child: AnimatedContainer(
              duration: duration,
              curve: NexusMotion.curveStandard,
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
                    AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: NexusMotion.curveEnter,
                      switchOutCurve: NexusMotion.curveExit,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.92, end: 1.0)
                              .animate(animation),
                          child: child,
                        ),
                      ),
                      child: Container(
                        key: ValueKey(unreadCount),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: foreground.withValues(alpha: 0.18),
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusPill),
                        ),
                        child: Text(
                          '$unreadCount',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                            height: 1.1,
                          ),
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
