import '../../theme/mobile_theme.dart';
import '../../widgets/nexus_disclosure.dart';
import 'package:flutter/material.dart';

import '../../../application/result_action_service.dart';
import '../../../domain/result_card.dart';
import '../../theme/app_theme.dart';
import '../../widgets/nexus_status_badge.dart';

/// 单个动作在界面上的反馈阶段。
///
/// 与 [ResultActionStatus] 分开：界面需要「准备中/执行中」这类纯 UI 阶段，
/// 而服务层状态是持久化的业务事实，两者不能混用。
enum ResultCardFeedbackPhase {
  idle,
  preparing,
  pendingConfirm,
  executing,
  succeeded,
  failed,
}

/// 一条动作的界面反馈。
class ResultCardActionFeedback {
  const ResultCardActionFeedback({
    this.phase = ResultCardFeedbackPhase.idle,
    this.message = '',
    this.errorCode,
  });

  /// 从服务返回构造反馈；冲突/失效统一进入失败阶段，
  /// 但保留 [errorCode] 让界面显示「刷新」而不是泛化失败。
  factory ResultCardActionFeedback.fromRun(ResultActionRun run) {
    final phase = run.hasError
        ? ResultCardFeedbackPhase.failed
        : switch (run.status) {
            ResultActionStatus.prepared => ResultCardFeedbackPhase.idle,
            ResultActionStatus.pendingConfirm =>
              ResultCardFeedbackPhase.pendingConfirm,
            ResultActionStatus.running => ResultCardFeedbackPhase.executing,
            ResultActionStatus.succeeded => ResultCardFeedbackPhase.succeeded,
            ResultActionStatus.failed ||
            ResultActionStatus.stale ||
            ResultActionStatus.conflict =>
              ResultCardFeedbackPhase.failed,
          };
    return ResultCardActionFeedback(
      phase: phase,
      message: run.feedback,
      errorCode: run.error,
    );
  }

  final ResultCardFeedbackPhase phase;
  final String message;
  final ResultActionErrorCode? errorCode;

  bool get busy =>
      phase == ResultCardFeedbackPhase.preparing ||
      phase == ResultCardFeedbackPhase.executing;

  bool get needsRefresh =>
      phase == ResultCardFeedbackPhase.failed &&
      (errorCode == ResultActionErrorCode.stale ||
          errorCode == ResultActionErrorCode.conflict);
}

/// 六类结果卡共用的卡片组件。
///
/// 组件只负责展示与派发用户意图，不自己执行动作：所有按钮都来自
/// [ResultActionRegistry]（或调用方传入的已注册动作列表），
/// 未注册动作根本不会出现在界面上。
class ResultCardView extends StatelessWidget {
  const ResultCardView({
    super.key,
    required this.card,
    this.feedback = const <String, ResultCardActionFeedback>{},
    this.actions,
    this.onAction,
    this.onConfirm,
    this.onRefresh,
    this.onOpenTask,
    this.readOnly = false,
    this.compact = false,
  });

  final ResultCard card;

  /// actionType -> 反馈；缺省视为 idle。
  final Map<String, ResultCardActionFeedback> feedback;

  /// 显式动作列表（必须已注册）；为空时使用注册表中该卡片类型的动作。
  final List<ResultActionSpec>? actions;

  final ValueChanged<ResultActionSpec>? onAction;
  final ValueChanged<ResultActionSpec>? onConfirm;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpenTask;
  final bool readOnly;

  /// 列表页使用的紧凑形态：只展示标题/摘要/状态，动作进入详情页再做。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppTheme.semanticOf(context);
    final specs = actions ?? ResultActionRegistry.forKind(card.kind);
    final visibleSpecs = [
      for (final spec in specs)
        if (ResultActionRegistry.supports(spec.actionType)) spec,
    ];
    final latest = _latestFeedback(visibleSpecs);
    final badge = _badgeState(latest);
    final primaryActionType = visibleSpecs
        .where((spec) => !spec.isDangerous)
        .map((spec) => spec.actionType)
        .firstOrNull;
    return Container(
      decoration: BoxDecoration(
        color: semantic.surface,
        border: Border.all(
          color:
              latest?.needsRefresh == true ? semantic.warning : semantic.border,
        ),
        borderRadius: BorderRadius.circular(MobileTheme.cardRadius(context)),
      ),
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kindIcon(context, semantic),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          card.kind.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: semantic.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        NexusStatusBadge(
                          label: badge.label,
                          tone: badge.tone,
                          showDot: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      card.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        height: 1.32,
                      ),
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (compact) ...[
            if (card.summary.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                card.summary,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: semantic.textMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ] else ...[
            if (card.summary.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                card.summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: semantic.textMuted,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 6),
            NexusDisclosure(
              title: Text(
                '资源详情',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: semantic.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              headerPadding: EdgeInsets.zero,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '资源：${card.resourceType}/${card.resourceId} · '
                      '版本 v${card.resourceVersion} · 卡片 r${card.revision}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: semantic.textFaint),
                    ),
                    if (card.taskId.trim().isNotEmpty)
                      Text(
                        '关联任务：${card.taskId}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: semantic.textFaint),
                      ),
                  ]),
            ),
            if (card.status != ResultCardStatus.active ||
                latest?.needsRefresh == true) ...[
              const SizedBox(height: 10),
              _conflictBanner(context, theme, semantic, latest),
            ],
            if (visibleSpecs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final spec in visibleSpecs)
                    _actionButton(
                      context,
                      theme,
                      semantic,
                      spec,
                      isPrimary: spec.actionType == primaryActionType,
                    ),
                ],
              ),
            ],
            if (!readOnly && onAction == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '当前无法执行这些操作。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: semantic.textFaint),
                ),
              ),
            if (latest != null && latest.message.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _feedbackPanel(context, theme, semantic, latest),
            ],
            if (card.taskId.trim().isNotEmpty && onOpenTask != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenTask,
                  icon: const Icon(Icons.assignment_outlined, size: 18),
                  label: const Text('返回关联任务'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  ResultCardActionFeedback? _latestFeedback(List<ResultActionSpec> specs) {
    ResultCardActionFeedback? found;
    for (final spec in specs) {
      final item = feedback[spec.actionType];
      if (item == null || item.phase == ResultCardFeedbackPhase.idle) continue;
      found = item;
      if (item.busy || item.phase == ResultCardFeedbackPhase.pendingConfirm) {
        // 进行中/待确认优先展示，避免被另一动作的旧成功提示掩盖。
        return item;
      }
    }
    return found;
  }

  _BadgeState _badgeState(ResultCardActionFeedback? item) {
    switch (item?.phase) {
      case ResultCardFeedbackPhase.preparing:
        return const _BadgeState('准备中', NexusBadgeTone.brand);
      case ResultCardFeedbackPhase.executing:
        return const _BadgeState('执行中', NexusBadgeTone.brand);
      case ResultCardFeedbackPhase.pendingConfirm:
        return const _BadgeState('待确认', NexusBadgeTone.warning);
      case ResultCardFeedbackPhase.succeeded:
        return const _BadgeState('已成功', NexusBadgeTone.success);
      case ResultCardFeedbackPhase.failed:
        return _BadgeState(
          item?.needsRefresh == true ? '需刷新' : '失败',
          NexusBadgeTone.danger,
        );
      case ResultCardFeedbackPhase.idle:
      case null:
        return _BadgeState(
            card.status.label,
            switch (card.status) {
              ResultCardStatus.active => NexusBadgeTone.brand,
              ResultCardStatus.expired => NexusBadgeTone.warning,
              ResultCardStatus.changed => NexusBadgeTone.warning,
              ResultCardStatus.unavailable => NexusBadgeTone.danger,
              ResultCardStatus.unknown => NexusBadgeTone.neutral,
            });
    }
  }

  Widget _kindIcon(BuildContext context, AppSemanticColors semantic) =>
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: semantic.brandSoft,
          borderRadius:
              BorderRadius.circular(MobileTheme.controlRadius(context)),
        ),
        child: Icon(
          switch (card.kind) {
            ResultCardKind.reminder => Icons.alarm_outlined,
            ResultCardKind.calendar => Icons.event_outlined,
            ResultCardKind.file => Icons.insert_drive_file_outlined,
            ResultCardKind.route => Icons.alt_route,
            ResultCardKind.workflowTrial => Icons.play_circle_outline,
            ResultCardKind.codeDiff => Icons.difference_outlined,
          },
          size: 18,
          color: semantic.brand,
        ),
      );

  Widget _conflictBanner(
    BuildContext context,
    ThemeData theme,
    AppSemanticColors semantic,
    ResultCardActionFeedback? item,
  ) {
    final conflict = card.status == ResultCardStatus.changed ||
        item?.errorCode == ResultActionErrorCode.conflict;
    final text = conflict
        ? '资源已被其他设备或页面修改；请刷新后确认最新状态，再重新发起操作。'
        : card.status == ResultCardStatus.expired
            ? '资源已过期或卡片引用的版本已失效；请刷新后重新生成结果卡。'
            : card.status == ResultCardStatus.unavailable
                ? '资源已被删除或当前不可访问；刷新后仍不可用请回到关联任务重新生成。'
                : item?.message.isNotEmpty == true
                    ? item!.message
                    : '资源状态未知；请刷新后重试。';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: semantic.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MobileTheme.controlRadius(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: semantic.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: semantic.textPrimary),
            ),
          ),
          if (onRefresh != null)
            TextButton(
              onPressed: onRefresh,
              child: const Text('刷新状态'),
            ),
        ],
      ),
    );
  }

  Widget _feedbackPanel(
    BuildContext context,
    ThemeData theme,
    AppSemanticColors semantic,
    ResultCardActionFeedback item,
  ) {
    final (color, icon) = switch (item.phase) {
      ResultCardFeedbackPhase.succeeded => (
          semantic.success,
          Icons.check_circle_outline
        ),
      ResultCardFeedbackPhase.failed => (semantic.danger, Icons.error_outline),
      ResultCardFeedbackPhase.pendingConfirm => (
          semantic.warning,
          Icons.approval_outlined
        ),
      _ => (semantic.brand, Icons.hourglass_top),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(MobileTheme.controlRadius(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.busy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.message,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: semantic.textPrimary),
                ),
                if (item.errorCode != null)
                  Text(
                    item.errorCode!.message,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: semantic.textFaint),
                  ),
              ],
            ),
          ),
          if (item.needsRefresh && onRefresh != null)
            TextButton(
              onPressed: onRefresh,
              child: const Text('刷新'),
            ),
        ],
      ),
    );
  }

  IconData _semanticActionIcon(ResultActionSpec spec) {
    return switch (spec.actionType) {
      'file.preview' => Icons.visibility_outlined,
      'file.share' => Icons.ios_share_rounded,
      'reminder.reschedule' => Icons.schedule_rounded,
      'reminder.cancel' => Icons.notifications_off_outlined,
      'calendar.adjust' => Icons.edit_calendar_outlined,
      'route.open' => Icons.map_outlined,
      'workflow.trial_run' => Icons.play_arrow_rounded,
      'diff.review' => Icons.difference_outlined,
      'diff.apply' => Icons.check_circle_outline_rounded,
      _ => Icons.arrow_outward_rounded,
    };
  }

  Widget _actionButton(
    BuildContext context,
    ThemeData theme,
    AppSemanticColors semantic,
    ResultActionSpec spec, {
    bool isPrimary = false,
  }) {
    final item = feedback[spec.actionType];
    final disabled = readOnly || onAction == null || (item?.busy ?? false);
    final waitingConfirmation =
        item?.phase == ResultCardFeedbackPhase.pendingConfirm;
    if (waitingConfirmation) {
      return FilledButton.icon(
        onPressed:
            disabled || onConfirm == null ? null : () => onConfirm!(spec),
        icon: const Icon(Icons.verified_outlined, size: 18),
        label: const Text('确认执行'),
      );
    }
    final done = item?.phase == ResultCardFeedbackPhase.succeeded;
    final failed = item?.phase == ResultCardFeedbackPhase.failed;
    final radius = BorderRadius.circular(MobileTheme.controlRadius(context));
    final style = spec.isDangerous
        ? OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: semantic.danger,
            side: BorderSide(color: semantic.danger.withValues(alpha: 0.45)),
            shape: RoundedRectangleBorder(borderRadius: radius),
          )
        : isPrimary
            ? OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                backgroundColor: semantic.brandSoft,
                foregroundColor: semantic.brand,
                side: BorderSide(color: semantic.brand.withValues(alpha: 0.16)),
                shape: RoundedRectangleBorder(borderRadius: radius),
              )
            : OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                backgroundColor: semantic.surface,
                foregroundColor: semantic.textPrimary,
                side: BorderSide(color: semantic.border),
                shape: RoundedRectangleBorder(borderRadius: radius),
              );
    return OutlinedButton.icon(
      onPressed: disabled ? null : () => onAction!(spec),
      style: style,
      icon: Icon(
        done
            ? Icons.check_rounded
            : spec.isDangerous
                ? Icons.warning_amber_rounded
                : _semanticActionIcon(spec),
        size: 17,
      ),
      label: Text(
        done
            ? '${spec.label}已完成'
            : failed
                ? '重试${spec.label}'
                : spec.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _BadgeState {
  const _BadgeState(this.label, this.tone);

  final String label;
  final NexusBadgeTone tone;
}
