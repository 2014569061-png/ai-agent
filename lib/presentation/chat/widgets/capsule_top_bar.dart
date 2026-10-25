import '../../navigation/mobile_navigation_scope.dart';
import 'package:flutter/material.dart';
import '../../../domain/model_failure.dart';
import '../../theme/app_tokens.dart';
import '../../theme/desktop_theme.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/nexus_home_visuals.dart';
import 'chat_execution_stage.dart';

/// 顶栏统一高度常量 (56px)
const double kCapsuleTopBarHeight = AppTokens.kTopBarHeight;

/// Reserve the same space in the overlay and message list at large text sizes.
double capsuleTopBarHeight(BuildContext context) =>
    (DesktopTheme.maybeOf(context) != null ? 40 : kCapsuleTopBarHeight) +
    (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0.0, 48.0) * 2;

/// Phone toolbar: conversations, NEXUS/session title, and new conversation.
/// Detailed execution settings remain available through the title selector.
/// Desktop retains its model picker and context gauge.
class CapsuleTopBar extends StatelessWidget {
  const CapsuleTopBar({
    super.key,
    this.workspaceLabel,
    this.modelLabel,
    this.sessionTitle,
    this.runningStage,
    this.runningStageKind,
    this.modelServiceStatus = ModelServiceStatus.online,
    required this.onMenu,
    required this.onNewChat,
    this.onContextGaugeTap,
    this.onTitleTap,
    this.onModelTap,
    this.onWorkspaceTap,
    this.modeLabel,
    this.onModeTap,
    this.currentContextTokens = 0,
    this.maxContextTokens = 128000,
    this.statusActive = false,
    this.glassIntensity = GlassIntensity.liquid,
  });

  final String? workspaceLabel;
  final String? modelLabel;
  final String? sessionTitle;
  final String? runningStage;
  final ChatExecutionStage? runningStageKind;
  final ModelServiceStatus modelServiceStatus;
  final VoidCallback onMenu;
  final VoidCallback onNewChat;
  final VoidCallback? onContextGaugeTap;
  final VoidCallback? onTitleTap;
  final VoidCallback? onModelTap;
  final VoidCallback? onWorkspaceTap;
  final String? modeLabel;
  final VoidCallback? onModeTap;
  final int currentContextTokens;
  final int maxContextTokens;
  final bool statusActive;
  final GlassIntensity glassIntensity;

  Widget _desktopBar(BuildContext context, DesktopTheme colors) {
    final theme = Theme.of(context);
    final isRunning = statusActive;
    final offlineLabel = _serviceStatusLabel(modelServiceStatus);
    return Container(
      height: capsuleTopBarHeight(context),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.canvas,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            IconButton(
              tooltip: '打开会话列表',
              onPressed: onMenu,
              icon: const Icon(Icons.view_sidebar_outlined, size: 16),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: onTitleTap ?? onModelTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          (sessionTitle ?? '').trim().isEmpty
                              ? '新会话'
                              : sessionTitle!,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: (sessionTitle ?? '').trim().isEmpty
                                ? FontWeight.w400
                                : FontWeight.w600,
                            color: (sessionTitle ?? '').trim().isEmpty
                                ? colors.muted
                                : colors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isRunning && constraints.maxWidth > 550) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.selected,
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: colors.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 8,
                      height: 8,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      runningStage?.isNotEmpty == true ? runningStage! : '运行中',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (offlineLabel != null && constraints.maxWidth > 500) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 12, color: theme.colorScheme.error),
                    const SizedBox(width: 4),
                    Text(
                      offlineLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 8),
            Tooltip(
              message: '选择模型',
              child: TextButton(
                onPressed: onModelTap,
                style: TextButton.styleFrom(
                  foregroundColor: colors.muted,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: colors.border),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        (modelLabel ?? '').isEmpty ? '选择模型' : modelLabel!,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'Consolas',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more, size: 14),
                  ],
                ),
              ),
            ),
            if (onContextGaugeTap != null)
              IconButton(
                tooltip:
                    '上下文 ${_formatTokens(currentContextTokens)} / ${_formatTokens(maxContextTokens)}',
                onPressed: onContextGaugeTap,
                icon: Icon(
                  Icons.data_usage_outlined,
                  size: 16,
                  color: currentContextTokens /
                              maxContextTokens.clamp(1, 1 << 30) >
                          .85
                      ? Theme.of(context).colorScheme.error
                      : colors.muted,
                ),
              ),
            IconButton(
              tooltip: '新会话',
              onPressed: onNewChat,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = DesktopTheme.maybeOf(context);
    if (desktop != null) return _desktopBar(context, desktop);
    final scheme = Theme.of(context).colorScheme;
    final textColor = scheme.onSurface;
    final iconColor = scheme.onSurfaceVariant;

    final title = (sessionTitle ?? '').trim();
    final service = _serviceStatusLabel(modelServiceStatus);
    return SizedBox(
      height: capsuleTopBarHeight(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          if (MobileNavigationScope.maybeOf(context) != null)
            const MobileNavigationMenuButton()
          else
            IconButton(
                tooltip: '打开会话列表',
                onPressed: onMenu,
                icon: NexusHomeIcon(NexusHomeSymbol.menu, color: iconColor)),
          Expanded(
              child: InkWell(
            onTap: onTitleTap ?? onModelTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(
                      child: Tooltip(
                          message: title.isEmpty ? '新对话' : title,
                          child: Text(title.isEmpty ? '新对话' : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                  letterSpacing: 0)))),
                  const SizedBox(width: 3),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ]),
                if (service != null)
                  Text(service,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.error)),
              ]),
            ),
          )),
          IconButton(
              tooltip: '新建对话',
              onPressed: onNewChat,
              icon: NexusHomeIcon(NexusHomeSymbol.compose, color: iconColor)),
        ]),
      ),
    );
  }

  static String _formatTokens(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k';
    }
    return '$value';
  }

  static String? _serviceStatusLabel(ModelServiceStatus status) =>
      switch (status) {
        ModelServiceStatus.offline => '模型服务连接失败',
        ModelServiceStatus.authRequired => '需要配置模型凭证',
        ModelServiceStatus.rateLimited => '模型服务限流',
        ModelServiceStatus.serverError => '模型服务异常',
        ModelServiceStatus.billing => '模型额度不足',
        ModelServiceStatus.online || ModelServiceStatus.unknown => null,
      };
}
