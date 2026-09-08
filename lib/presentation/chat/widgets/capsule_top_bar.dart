import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/immersive_surface.dart';
import '../../widgets/nexus_status_pill.dart';

/// 顶栏统一高度常量 (由 AppTokens 统一定义)
const double kCapsuleTopBarHeight = AppTokens.kCapsuleTopBarHeight;

/// Chat 页顶部控制栏 (CapsuleTopBar)
/// 严格依据 NEXUS UI 设计优化规范重构：
/// 1. 左侧：菜单按钮 + 当前工作区徽标。
/// 2. 中间：当前会话标题（若为空显示“新会话”），第二行展示当前模型。
/// 3. 右侧：运行状态文字徽标（生成中/工具执行中/等待审批）、Token HUD 胶囊、新建会话按钮。
class CapsuleTopBar extends StatelessWidget {
  const CapsuleTopBar({
    super.key,
    this.workspaceLabel,
    this.modelLabel,
    this.sessionTitle,
    this.runningStage,
    required this.onMenu,
    required this.onNewChat,
    this.onContextGaugeTap,
    this.onTitleTap,
    this.onModelTap,
    this.onWorkspaceTap,
    this.currentContextTokens = 0,
    this.maxContextTokens = 128000,
    this.statusActive = false,
  });

  final String? workspaceLabel;
  final String? modelLabel;
  final String? sessionTitle;
  final String? runningStage;
  final VoidCallback onMenu;
  final VoidCallback onNewChat;
  final VoidCallback? onContextGaugeTap;
  final VoidCallback? onTitleTap;
  final VoidCallback? onModelTap;
  final VoidCallback? onWorkspaceTap;
  final int currentContextTokens;
  final int maxContextTokens;
  final bool statusActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppTheme.semanticOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final workspace = workspaceLabel?.trim();
    final model = modelLabel?.trim() ?? 'AI 助手';
    final hasWorkspace =
        workspace != null && workspace.isNotEmpty && workspace != '无工作区';

    final title = (sessionTitle != null && sessionTitle!.trim().isNotEmpty)
        ? sessionTitle!.trim()
        : '新会话';

    final contextRatio = maxContextTokens <= 0
        ? 0.0
        : (currentContextTokens / maxContextTokens).clamp(0.0, 1.0);
    final percent = (contextRatio * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kCapsuleTopBarHeight),
        child: ImmersiveSurface(
          level: ImmersiveMaterialLevel.ultraThin,
          borderRadius: BorderRadius.circular(AppTokens.radiusCapsule),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                // 侧边栏抽屉菜单
                IconButton(
                  tooltip: '打开功能目录',
                  icon: const Icon(Icons.menu_rounded, size: 22),
                  onPressed: onMenu,
                  visualDensity: VisualDensity.compact,
                ),

                const SizedBox(width: 6),

                // 工作区轻量胶囊按钮
                InkWell(
                  onTap: onWorkspaceTap ?? onTitleTap ?? onMenu,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: semantic.surfaceTint.withValues(alpha: isDark ? 0.6 : 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: semantic.border.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasWorkspace
                          ? Icons.folder_rounded
                          : Icons.folder_open_rounded,
                      size: 13,
                      color: hasWorkspace
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 80),
                      child: Text(
                        hasWorkspace ? workspace : '工作区',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: hasWorkspace
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 2. 中间当前会话标题与模型标签
            Expanded(
              child: GestureDetector(
                onTap: onTitleTap ?? onMenu,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. 右侧状态徽标（文字化）
            if (statusActive) ...[
              NexusStatusPill(
                status: (runningStage?.contains('审批') ?? false)
                    ? NexusStatusType.waitingApproval
                    : NexusStatusType.running,
                customLabel: runningStage ?? '生成中',
                isCompact: true,
              ),
              const SizedBox(width: 6),
            ],

            // 4. 右侧微型上下文占用胶囊 (Token HUD)
            if (currentContextTokens > 0) ...[
              ImmersiveSurface(
                level: ImmersiveMaterialLevel.thin,
                borderRadius: BorderRadius.circular(10),
                child: GestureDetector(
                  onTap: onContextGaugeTap ?? onMenu,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: contextRatio > 0.8
                            ? AppTheme.danger
                            : (contextRatio > 0.6
                                ? AppTheme.warning
                                : Colors.transparent),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5.5,
                          height: 5.5,
                          decoration: BoxDecoration(
                            color: contextRatio > 0.8
                                ? AppTheme.danger
                                : (contextRatio > 0.6
                                    ? AppTheme.warning
                                    : AppTheme.success),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$percent%',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],

            // 5. 右侧新建对话快捷按钮
            _Action(
              icon: Icons.add_rounded,
              tooltip: '新建对话',
              onTap: onNewChat,
            ),
          ],
        ),
      ),
    ),
  ),
);
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.tooltip, this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: onTap,
    );
  }
}
