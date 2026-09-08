import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

import '../../../application/chat_controller.dart';
import '../../../domain/models.dart';

/// 统一「会话上下文」面板：一次看清并修改模型/服务、Agent、工作区、
/// 思考程度、计划模式。把原先散落在头像菜单、底栏、顶部 chip、输入区的
/// 上下文入口收拢到一处，减少用户在不同角落找配置的心智负担。
class SessionContextSheet extends StatelessWidget {
  const SessionContextSheet({
    super.key,
    required this.state,
    required this.onSelectModel,
    required this.onSelectAgent,
    required this.onPickWorkspace,
    required this.onClearWorkspace,
    required this.onReasoningEffort,
    required this.onTogglePlanMode,
  });

  final ChatState state;
  final VoidCallback onSelectModel;
  final VoidCallback onSelectAgent;
  final VoidCallback onPickWorkspace;
  final VoidCallback onClearWorkspace;
  final VoidCallback onReasoningEffort;
  final VoidCallback onTogglePlanMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ws = state.currentWorkspacePath;
    final folder =
        ws == null || ws.isEmpty ? null : ws.split(RegExp('[\\\\/]')).last;

    Widget tile({
      required IconData icon,
      required String label,
      required String value,
      required VoidCallback onTap,
      Widget? trailing,
    }) {
      return ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.tune_rounded),
              const SizedBox(width: 8),
              Text('会话上下文',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            tile(
              icon: Icons.model_training_rounded,
              label: '模型 / 服务',
              value: state.activeModel.isEmpty
                  ? '未配置'
                  : '${state.activeProviderName} · ${state.activeModel}',
              onTap: onSelectModel,
            ),
            tile(
              icon: Icons.smart_toy_outlined,
              label: 'Agent',
              value: state.agentName,
              onTap: onSelectAgent,
            ),
            tile(
              icon: Icons.psychology_outlined,
              label: '思考程度',
              value: _effortLabel(state.activeReasoningEffort),
              onTap: onReasoningEffort,
            ),
            tile(
              icon: Icons.folder_open_outlined,
              label: '项目工作区',
              value: folder ?? '未绑定本地文件夹',
              onTap: onPickWorkspace,
              trailing: folder != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.link_off_rounded, size: 20),
                          tooltip: '解绑工作区',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            onClearWorkspace();
                          },
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 20),
                      ],
                    )
                  : const Icon(Icons.chevron_right_rounded, size: 20),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.checklist_rounded,
                  color: state.planMode
                      ? AppTheme.warning
                      : theme.colorScheme.outline),
              title: const Text('计划审批模式',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('开启后首轮先生成分步计划，确认后才执行',
                  style: TextStyle(fontSize: 12)),
              value: state.planMode,
              onChanged: (_) => onTogglePlanMode(),
            ),
          ],
        ),
      ),
    );
  }

  static String _effortLabel(ReasoningEffort e) => switch (e) {
        ReasoningEffort.off => '关',
        ReasoningEffort.low => '低',
        ReasoningEffort.medium => '中',
        ReasoningEffort.high => '高',
      };
}
