import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/immersive_surface.dart';

/// 底部输入框小工具呼出 8 宫格面板
/// 替代原输入框内展开的拥挤微型图标行，提供现代聊天应用标准的工具操作台。
class InputToolGridSheet extends StatelessWidget {
  final VoidCallback onCommandMenu;
  final VoidCallback onMcpMenu;
  final VoidCallback onTerminalPreview;
  final VoidCallback onEnvSetup;
  final VoidCallback? onVoiceToggle;
  final bool isListening;
  final VoidCallback? onOpenDashboard;
  final bool planModeEnabled;
  final VoidCallback onPlanModeToggle;
  final ApprovalMode approvalMode;
  final VoidCallback onApprovalModeTap;

  const InputToolGridSheet({
    super.key,
    required this.onCommandMenu,
    required this.onMcpMenu,
    required this.onTerminalPreview,
    required this.onEnvSetup,
    this.onVoiceToggle,
    this.isListening = false,
    this.onOpenDashboard,
    required this.planModeEnabled,
    required this.onPlanModeToggle,
    required this.approvalMode,
    required this.onApprovalModeTap,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onCommandMenu,
    required VoidCallback onMcpMenu,
    required VoidCallback onTerminalPreview,
    required VoidCallback onEnvSetup,
    VoidCallback? onVoiceToggle,
    bool isListening = false,
    VoidCallback? onOpenDashboard,
    required bool planModeEnabled,
    required VoidCallback onPlanModeToggle,
    required ApprovalMode approvalMode,
    required VoidCallback onApprovalModeTap,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => InputToolGridSheet(
        onCommandMenu: onCommandMenu,
        onMcpMenu: onMcpMenu,
        onTerminalPreview: onTerminalPreview,
        onEnvSetup: onEnvSetup,
        onVoiceToggle: onVoiceToggle,
        isListening: isListening,
        onOpenDashboard: onOpenDashboard,
        planModeEnabled: planModeEnabled,
        onPlanModeToggle: onPlanModeToggle,
        approvalMode: approvalMode,
        onApprovalModeTap: onApprovalModeTap,
      ),
    );
  }

  String _approvalLabel(ApprovalMode mode) => switch (mode) {
        ApprovalMode.ask => '每次询问',
        ApprovalMode.autoSafe => '自动低风险',
        ApprovalMode.fullAccess => '完全访问',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final semantic = AppTheme.semanticOf(context);

    final tools = <_ToolDefinition>[
      _ToolDefinition(
        icon: Icons.keyboard_command_key_rounded,
        title: '提示词库',
        subtitle: '预设任务指令',
        color: AppTheme.brandBright,
        onTap: onCommandMenu,
      ),
      _ToolDefinition(
        icon: Icons.widgets_outlined,
        title: 'MCP 服务',
        subtitle: '扩展工具生态',
        color: const Color(0xFF6366F1),
        onTap: onMcpMenu,
      ),
      _ToolDefinition(
        icon: Icons.terminal_rounded,
        title: '终端预览',
        subtitle: '命令行与脚本',
        color: const Color(0xFF0EA5E9),
        onTap: onTerminalPreview,
      ),
      _ToolDefinition(
        icon: Icons.build_circle_outlined,
        title: '开发环境',
        subtitle: '运行时与依赖',
        color: const Color(0xFF10B981),
        onTap: onEnvSetup,
      ),
      if (onOpenDashboard != null)
        _ToolDefinition(
          icon: Icons.dashboard_outlined,
          title: '仪表盘',
          subtitle: '工作负载总览',
          color: const Color(0xFF8B5CF6),
          onTap: onOpenDashboard!,
        ),
      _ToolDefinition(
        icon: planModeEnabled
            ? Icons.front_hand_rounded
            : Icons.pan_tool_alt_rounded,
        title: '计划模式',
        subtitle: planModeEnabled ? '已开启 · 需确认' : '已关闭 · 自动执行',
        color: planModeEnabled ? AppTheme.warning : semantic.textMuted,
        isActive: planModeEnabled,
        onTap: onPlanModeToggle,
      ),
      _ToolDefinition(
        icon: approvalMode == ApprovalMode.fullAccess
            ? Icons.shield_outlined
            : Icons.verified_user_outlined,
        title: '审批策略',
        subtitle: _approvalLabel(approvalMode),
        color: approvalMode == ApprovalMode.fullAccess
            ? AppTheme.warning
            : const Color(0xFF3B82F6),
        onTap: onApprovalModeTap,
      ),
      if (onVoiceToggle != null)
        _ToolDefinition(
          icon: isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
          title: isListening ? '停止录音' : '语音输入',
          subtitle: isListening ? '正在收音…' : '语音转文字',
          color: isListening ? AppTheme.danger : const Color(0xFFEC4899),
          isActive: isListening,
          onTap: onVoiceToggle!,
        ),
    ];

    return ImmersiveSurface(
      level: ImmersiveMaterialLevel.ultraThick,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部指示条
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 标题栏
              Row(
                children: [
                  const Icon(Icons.apps_rounded, size: 18, color: AppTheme.brandBright),
                  const SizedBox(width: 8),
                  Text(
                    '工作台工具箱',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 工具网格：固定 4 列，整洁对称
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tools.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.78,
                ),
                itemBuilder: (context, index) {
                  final tool = tools[index];
                  return _ToolGridCard(
                    tool: tool,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                      tool.onTap();
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolDefinition {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolDefinition({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.isActive = false,
    required this.onTap,
  });
}

class _ToolGridCard extends StatelessWidget {
  final _ToolDefinition tool;
  final VoidCallback onPressed;

  const _ToolGridCard({
    required this.tool,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Tooltip(
      message: tool.title,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tool.color.withValues(alpha: isDark ? 0.16 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: tool.color.withValues(alpha: tool.isActive ? 0.5 : 0.25),
                    width: tool.isActive ? 1.5 : 1.0,
                  ),
                  boxShadow: tool.isActive
                      ? [
                          BoxShadow(
                            color: tool.color.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Icon(tool.icon, size: 24, color: tool.color),
              ),
              const SizedBox(height: 6),
              Text(
                tool.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tool.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
