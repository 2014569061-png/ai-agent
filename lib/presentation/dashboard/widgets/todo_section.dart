import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/chat_controller.dart';
import '../../../application/dashboard_service.dart';
import '../../../application/providers.dart';
import '../../../application/task_service.dart';
import '../../../domain/models.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../l10n/app_strings.dart';
import '../../tasks/task_details_page.dart';
import '../../theme/app_theme.dart';
import '../../widgets/floating_toast.dart';
import '../../widgets/nexus_section.dart';
import '../../widgets/section_card.dart';
import '../dashboard_provider.dart';

/// 待我处理聚合区：工具审批、计划确认和可恢复任务。
///
/// 仪表盘只负责聚合和跳转，具体审批仍由任务详情页或聊天页处理。
class TodoSection extends ConsumerStatefulWidget {
  const TodoSection({
    super.key,
    required this.todos,
    this.onConversationSelected,
  });

  final List<DashboardTodoItem> todos;
  final ValueChanged<Conversation>? onConversationSelected;

  @override
  ConsumerState<TodoSection> createState() => _TodoSectionState();
}

class _TodoSectionState extends ConsumerState<TodoSection> {
  final Set<String> _busyTodoIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final todos = widget.todos;
    if (todos.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return NexusSection(
      title: '${AppStrings.pendingActions} (${todos.length})',
      icon: Icons.notifications_active_outlined,
      child: Column(
        children: todos.map((item) {
          final isApproval = item.type == TodoItemType.approval;
          final isPlan = item.type == TodoItemType.plan;
          final isRecoverable = item.type == TodoItemType.recoverable;
          final canResumeDirectly = isRecoverable &&
              ref.read(chatControllerProvider).approvalMode ==
                  ApprovalMode.fullAccess;
          final isBusy = _busyTodoIds.contains(item.id);

          final badgeColor = isApproval
              ? AppTheme.warning
              : (isPlan ? theme.colorScheme.primary : AppTheme.success);

          final badgeText = isApproval
              ? AppStrings.pendingApproval
              : (isPlan
                  ? AppStrings.pendingPlanConfirm
                  : AppStrings.pendingResume);

          final actionLabel = isApproval
              ? AppStrings.approve
              : (isPlan || !canResumeDirectly)
                  ? AppStrings.goTo
                  : AppStrings.resume;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isApproval
                          ? Icons.shield_outlined
                          : (isPlan
                              ? Icons.front_hand_rounded
                              : Icons.replay_rounded),
                      size: 18,
                      color: badgeColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed:
                        isBusy ? null : () => _handleAction(context, item),
                    child: isBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(actionLabel),
                  ),
                ],
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    DashboardTodoItem item,
  ) async {
    if (!mounted || _busyTodoIds.contains(item.id)) return;
    setState(() => _busyTodoIds.add(item.id));

    final isApproval = item.type == TodoItemType.approval;
    final isPlan = item.type == TodoItemType.plan;

    try {
      if (isApproval && item.taskId != null) {
        final db = await ref.read(databaseProvider.future);
        final task = await db.findTask(item.taskId!);
        if (task != null && context.mounted) {
          final info = DevelopmentTaskInfo.fromTask(task);
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TaskDetailsPage(
                task: info,
                onConversationSelected: widget.onConversationSelected,
              ),
            ),
          );
        }
      } else if (isPlan && item.conversationId != null) {
        await _jumpToConversation(context, item.conversationId!);
      } else if (item.type == TodoItemType.recoverable) {
        final canResumeDirectly =
            ref.read(chatControllerProvider).approvalMode ==
                ApprovalMode.fullAccess;

        if (canResumeDirectly && item.taskId != null) {
          FloatingToast.show(context, AppStrings.resumingTask);
          await ref.read(chatControllerProvider.notifier).resumeTask(
                item.taskId!,
                approveTool: (call, risk) async => ToolApproval.allowOnce,
              );
          if (context.mounted) Navigator.of(context).pop();
        } else if (item.conversationId != null) {
          await _jumpToConversation(context, item.conversationId!);
        }
      }

      if (mounted) {
        ref.invalidate(dashboardSummaryProvider);
      }
    } catch (err) {
      if (context.mounted) {
        FloatingToast.error(context, '$err');
      }
    } finally {
      if (mounted) {
        setState(() => _busyTodoIds.remove(item.id));
      }
    }
  }

  Future<void> _jumpToConversation(
    BuildContext context,
    String conversationId,
  ) async {
    final db = await ref.read(databaseProvider.future);
    final conv = await db.findConversation(conversationId);
    if (conv != null && context.mounted) {
      widget.onConversationSelected?.call(conv);
      Navigator.of(context).pop();
    }
  }
}
