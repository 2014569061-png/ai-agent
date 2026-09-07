import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/immersive_surface.dart';

/// 顶栏统一高度常量
const double kCapsuleTopBarHeight = 56.0;

/// Chat 页顶部极简会话栏：
/// 左侧汉堡菜单，中间会话标题与模型标签，右侧状态胶囊与新建会话按钮。
class CapsuleTopBar extends StatelessWidget {
  const CapsuleTopBar({
    super.key,
    this.workspaceLabel,
    this.modelLabel,
    required this.onMenu,
    required this.onNewChat,
    this.onContextGaugeTap,
    this.onTitleTap,
    this.currentContextTokens = 0,
    this.maxContextTokens = 128000,
    this.statusActive = false,
  });

  final String? workspaceLabel;
  final String? modelLabel;
  final VoidCallback onMenu;
  final VoidCallback onNewChat;
  final VoidCallback? onContextGaugeTap;
  final VoidCallback? onTitleTap;
  final int currentContextTokens;
  final int maxContextTokens;
  final bool statusActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workspace = workspaceLabel?.trim();
    final model = modelLabel?.trim() ?? 'AI 助手';
    final hasWorkspace =
        workspace != null && workspace.isNotEmpty && workspace != '无工作区';

    final contextRatio =
        (currentContextTokens / maxContextTokens).clamp(0.0, 1.0);
    final percent = (contextRatio * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: SizedBox(
        height: 46, // Total 56
        child: Row(
          children: [
            // 1. 左侧汉堡菜单按钮
            _Action(
              icon: Icons.menu_rounded,
              tooltip: '打开功能目录',
              onTap: onMenu,
            ),
            const SizedBox(width: 8),

            // 2. 中间当前会话/环境面包屑标题
            Expanded(
              child: GestureDetector(
                onTap: onTitleTap ?? onMenu,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            hasWorkspace ? workspace : '工作台',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_right_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      ],
                    ),
                    Text(
                      model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. 右侧微型上下文占用胶囊 (HUD) 缩减尺寸
            if (currentContextTokens > 0)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ImmersiveSurface(
                  level: ImmersiveMaterialLevel.thin,
                  borderRadius: BorderRadius.circular(10),
                  child: GestureDetector(
                    onTap: onContextGaugeTap ?? onMenu,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
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
                            width: 6,
                            height: 6,
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
              ),

            // 4. 右侧新建对话快捷按钮
            _Action(
              icon: Icons.add_rounded,
              tooltip: '新建对话',
              onTap: onNewChat,
            ),
          ],
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
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: ImmersiveSurface(
        level: ImmersiveMaterialLevel.thin,
        borderRadius: BorderRadius.circular(10),
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
