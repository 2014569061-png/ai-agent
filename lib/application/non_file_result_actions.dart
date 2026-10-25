import '../domain/result_card.dart';
import '../domain/system_connector_request.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/result_action_store.dart';
import 'artifact_result_actions.dart';
import 'change_set_service.dart';
import 'result_action_service.dart';
import 'reminder_service.dart';
import 'mobile_workflow_service.dart';

/// Resolves and validates a structured map search request from a [ResultCard].
///
/// Never trusts raw intent URIs or shell strings stored in `snapshot`; only
/// validated plain-text place queries accepted by [SystemConnectorRequest]
/// (`maps` / `search_place`) are permitted.
SystemConnectorRequest? resolveRouteConnectorRequest(ResultCard card) {
  if (card.kind != ResultCardKind.route || card.resourceType != 'route') {
    return null;
  }
  final snap = card.snapshot;
  final rawQuery = [
    snap['query'],
    snap['destination'],
    snap['place'],
    snap['address'],
    card.title,
    card.summary,
  ].whereType<String>().map((s) => s.trim()).firstWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
  if (rawQuery.isEmpty) return null;
  try {
    return SystemConnectorRequest.fromJson({
      'connectorId': 'maps',
      'operation': 'search_place',
      'arguments': {'query': rawQuery},
    });
  } on FormatException {
    return null;
  }
}

/// Resolves and validates a structured calendar editor request from a [ResultCard].
SystemConnectorRequest? resolveCalendarConnectorRequest(ResultCard card) {
  if (card.kind != ResultCardKind.calendar ||
      card.resourceType != 'calendar_event') {
    return null;
  }
  final snap = card.snapshot;
  final title =
      (snap['title'] is String && (snap['title'] as String).trim().isNotEmpty)
          ? (snap['title'] as String).trim()
          : card.title.trim();
  // The editor must preview a time the user actually supplied.
  if (snap['startEpochMs'] is! int || snap['endEpochMs'] is! int) return null;
  final startEpochMs = snap['startEpochMs'] as int;
  final endEpochMs = snap['endEpochMs'] as int;
  try {
    return SystemConnectorRequest.fromJson({
      'connectorId': 'calendar',
      'operation': 'prepare_event',
      'arguments': {
        'title': title,
        'start': DateTime.fromMillisecondsSinceEpoch(startEpochMs, isUtc: true)
            .toIso8601String(),
        'end': DateTime.fromMillisecondsSinceEpoch(endEpochMs, isUtc: true)
            .toIso8601String(),
        if (snap['location'] is String &&
            (snap['location'] as String).trim().isNotEmpty)
          'location': (snap['location'] as String).trim(),
        if (snap['description'] is String &&
            (snap['description'] as String).trim().isNotEmpty)
          'description': (snap['description'] as String).trim(),
      },
    });
  } on FormatException {
    return null;
  }
}

/// Composite resource reader that delegates `artifact` resources to
/// [ArtifactResultResourceReader] and validates persisted non-file result card
/// resources (`route`, `change_set`/`workspace_file`, `reminder`/`scheduled_task`,
/// `calendar_event`, `workflow`).
class CompositeResultResourceReader implements ResultResourceReader {
  CompositeResultResourceReader({
    required this.db,
    required this.repository,
    required this.artifactReader,
  });

  final AppDatabase db;
  final ResultActionRepository repository;
  final ArtifactResultResourceReader artifactReader;

  static ResultCardKind? _expectedKindForResourceType(String resourceType) =>
      switch (resourceType) {
        'route' => ResultCardKind.route,
        'change_set' || 'workspace_file' => ResultCardKind.codeDiff,
        'reminder' || 'scheduled_task' => ResultCardKind.reminder,
        'calendar_event' => ResultCardKind.calendar,
        'workflow' => ResultCardKind.workflowTrial,
        _ => null,
      };

  Future<ResultCard?> _findCardForResource(
    ResultCardKind kind,
    String resourceType,
    String resourceId,
  ) async {
    final cards = await repository.listCards(kind: kind, limit: 200);
    for (final card in cards) {
      if (card.resourceType == resourceType && card.resourceId == resourceId) {
        return card;
      }
    }
    return null;
  }

  @override
  Future<ResultResourceSnapshot?> read({
    required String resourceType,
    required String resourceId,
  }) async {
    if (resourceType == 'artifact') {
      return artifactReader.read(
        resourceType: resourceType,
        resourceId: resourceId,
      );
    }
    final expectedKind = _expectedKindForResourceType(resourceType);
    if (expectedKind == null || resourceId.trim().isEmpty) return null;
    final card = await _findCardForResource(
      expectedKind,
      resourceType,
      resourceId,
    );
    if (card == null) {
      return ResultResourceSnapshot(
        resourceType: resourceType,
        resourceId: resourceId,
        version: 0,
        exists: false,
        status: ResultCardStatus.unavailable,
      );
    }
    switch (expectedKind) {
      case ResultCardKind.route:
        final req = resolveRouteConnectorRequest(card);
        if (req == null) {
          return ResultResourceSnapshot(
            resourceType: resourceType,
            resourceId: resourceId,
            version: card.resourceVersion,
            exists: false,
            status: ResultCardStatus.unavailable,
          );
        }
        return ResultResourceSnapshot(
          resourceType: resourceType,
          resourceId: resourceId,
          version: card.resourceVersion,
          exists: card.status != ResultCardStatus.unavailable,
          status: card.status,
        );
      case ResultCardKind.codeDiff:
        final taskId =
            card.taskId.trim().isNotEmpty ? card.taskId.trim() : resourceId;
        final task = await db.findTask(taskId);
        if (task != null && card.snapshot['requireChangeSet'] == true) {
          final cs = await const ChangeSetService().load(taskId: task.id);
          final hasChanges = cs != null && cs.files.isNotEmpty;
          if (!hasChanges) {
            return ResultResourceSnapshot(
              resourceType: resourceType,
              resourceId: resourceId,
              version: card.resourceVersion,
              exists: false,
              status: ResultCardStatus.unavailable,
            );
          }
        }
        return ResultResourceSnapshot(
          resourceType: resourceType,
          resourceId: resourceId,
          version: card.resourceVersion,
          exists: card.status != ResultCardStatus.unavailable,
          status: card.status,
        );
      case ResultCardKind.reminder:
        if (resourceType == 'reminder') {
          final item = await ReminderService(db).findById(resourceId);
          return ResultResourceSnapshot(
            resourceType: resourceType,
            resourceId: resourceId,
            version: item?.version ?? 0,
            exists: item != null,
            status: item == null ? ResultCardStatus.unavailable : card.status,
          );
        }
        final scheduled = await db.findScheduledTask(resourceId);
        if (scheduled != null) {
          final version = card.resourceVersion > 1000000
              ? scheduled.updatedAt.millisecondsSinceEpoch
              : card.resourceVersion;
          return ResultResourceSnapshot(
            resourceType: resourceType,
            resourceId: resourceId,
            version: version,
            exists: true,
            status: card.status,
          );
        }
        return ResultResourceSnapshot(
          resourceType: resourceType,
          resourceId: resourceId,
          version: card.resourceVersion,
          exists: false,
          status: card.status,
        );
      case ResultCardKind.calendar:
        final req = resolveCalendarConnectorRequest(card);
        if (req == null) {
          return ResultResourceSnapshot(
            resourceType: resourceType,
            resourceId: resourceId,
            version: card.resourceVersion,
            exists: false,
            status: ResultCardStatus.unavailable,
          );
        }
        return ResultResourceSnapshot(
          resourceType: resourceType,
          resourceId: resourceId,
          version: card.resourceVersion,
          exists: card.status != ResultCardStatus.unavailable,
          status: card.status,
        );
      case ResultCardKind.workflowTrial:
        final workflow =
            await MobileWorkflowService(db).findDefinition(resourceId);
        return ResultResourceSnapshot(
          resourceType: resourceType,
          resourceId: resourceId,
          version: workflow?.version ?? 0,
          exists: workflow != null,
          status: card.status,
        );
      case ResultCardKind.file:
        return null;
    }
  }
}

/// Composite executor that delegates `file.preview` and `file.share` to
/// [ArtifactResultActionExecutor] and executes non-file result card actions
/// (`route.open`, `diff.review`, `diff.restore`, `reminder.reschedule`,
/// `reminder.cancel`, `calendar.adjust`, `workflow.trial_run`) against
/// verified persisted cards and real application/platform adapters.
class CompositeResultActionExecutor implements ResultActionExecutor {
  CompositeResultActionExecutor({
    required this.db,
    required this.repository,
    required this.artifactExecutor,
    required this.openRoute,
    this.reviewDiff,
    this.restoreDiff,
    this.rescheduleReminder,
    this.cancelReminder,
    this.adjustCalendar,
    this.trialRunWorkflow,
    this.canInteract,
  });

  final AppDatabase db;
  final ResultActionRepository repository;
  final ArtifactResultActionExecutor artifactExecutor;
  final Future<bool> Function(String query, ResultCard card) openRoute;
  final Future<bool> Function(ResultCard card, Task? task, Project? project)?
      reviewDiff;
  final Future<ResultActionExecutionResult> Function(
      ResultCard card, Task? task, Project? project)? restoreDiff;
  final Future<bool> Function(ResultCard card, ScheduledTask? scheduled)?
      rescheduleReminder;
  final Future<bool> Function(ResultCard card, ScheduledTask? scheduled)?
      cancelReminder;
  final Future<bool> Function(SystemConnectorRequest request, ResultCard card)?
      adjustCalendar;
  final Future<bool> Function(ResultCard card)? trialRunWorkflow;
  final bool Function()? canInteract;

  @override
  Future<ResultActionExecutionResult> execute(
    ResultActionExecutionRequest request,
  ) async {
    if (request.actionType == 'file.preview' ||
        request.actionType == 'file.share' ||
        request.executorKey == 'device.file') {
      return artifactExecutor.execute(request);
    }

    if (!(canInteract?.call() ?? true)) {
      return const ResultActionExecutionResult.failed(
        message: '当前页面已关闭，未执行操作',
      );
    }
    if (request.canContinue != null && !await request.canContinue!()) {
      return const ResultActionExecutionResult.failed(
        message: '资源状态已变化，已取消执行操作',
      );
    }

    final persisted = await repository.findCard(request.card.id);
    if (persisted == null ||
        persisted.kind != request.card.kind ||
        persisted.resourceType != request.card.resourceType ||
        persisted.resourceId != request.card.resourceId ||
        persisted.resourceVersion != request.card.resourceVersion ||
        persisted.revision != request.card.revision ||
        persisted.status != ResultCardStatus.active) {
      return const ResultActionExecutionResult.failed(
        message: '结果卡状态已变化或不属于当前会话，已拒绝执行',
      );
    }

    switch ((request.actionType, request.executorKey)) {
      case ('route.open', 'route.open'):
        final connectorReq = resolveRouteConnectorRequest(persisted);
        if (connectorReq == null) {
          return const ResultActionExecutionResult.failed(
            message: '路线参数缺失或格式不合法，无法打开地图',
          );
        }
        final query = connectorReq.arguments['query']!;
        if (!(canInteract?.call() ?? true) ||
            (request.canContinue != null && !await request.canContinue!())) {
          return const ResultActionExecutionResult.failed(
            message: '页面或资源状态已变化，未打开外部地图',
          );
        }
        final launched = await openRoute(query, persisted);
        if (!launched) {
          return const ResultActionExecutionResult.failed(
            message: '路线打开未完成（地图应用不可用或已取消）',
          );
        }
        return ResultActionExecutionResult.succeeded(
          message: '已请求系统打开路线；请在地图应用中确认导航，不代表外部导航已完成',
          result: {
            'delivery': 'system_map_handoff_only',
            'connectorId': connectorReq.connector.name,
            'operation': connectorReq.operation,
            'query': query,
            'resourceId': persisted.resourceId,
          },
        );

      case ('diff.review', 'diff.review'):
        if (persisted.kind != ResultCardKind.codeDiff) {
          return const ResultActionExecutionResult.failed(
            message: '卡片类型与差异查看操作不匹配',
          );
        }
        final taskId = persisted.taskId.trim().isNotEmpty
            ? persisted.taskId.trim()
            : persisted.resourceId;
        final task = await db.findTask(taskId);
        final taskProjectId = (task?.projectId ?? '').trim();
        final projectId = taskProjectId.isNotEmpty
            ? taskProjectId
            : (persisted.snapshot['projectId'] as String? ?? '').trim();
        final project =
            projectId.isNotEmpty ? await db.findProject(projectId) : null;
        if (!(canInteract?.call() ?? true) ||
            (request.canContinue != null && !await request.canContinue!())) {
          return const ResultActionExecutionResult.failed(
            message: '页面或资源状态已变化，未打开差异视图',
          );
        }
        final opened = reviewDiff != null
            ? await reviewDiff!(persisted, task, project)
            : false;
        if (!opened) {
          return const ResultActionExecutionResult.failed(
            message: '未找到可查看的代码变更集或关联项目',
          );
        }
        return ResultActionExecutionResult.succeeded(
          message: '已打开差异视图，请核对修改内容',
          result: {
            'resourceId': persisted.resourceId,
            'taskId': taskId,
            if (project != null) 'projectId': project.id,
          },
        );

      case ('diff.restore', 'diff.restore'):
        if (persisted.kind != ResultCardKind.codeDiff) {
          return const ResultActionExecutionResult.failed(
            message: '卡片类型与差异恢复操作不匹配',
          );
        }
        final taskId = persisted.taskId.trim().isNotEmpty
            ? persisted.taskId.trim()
            : persisted.resourceId;
        final task = await db.findTask(taskId);
        final taskProjectId = (task?.projectId ?? '').trim();
        final projectId = taskProjectId.isNotEmpty
            ? taskProjectId
            : (persisted.snapshot['projectId'] as String? ?? '').trim();
        final project =
            projectId.isNotEmpty ? await db.findProject(projectId) : null;
        if (!(canInteract?.call() ?? true) ||
            (request.canContinue != null && !await request.canContinue!())) {
          return const ResultActionExecutionResult.failed(
            message: '页面或资源状态已变化，未执行文件恢复',
          );
        }
        if (restoreDiff != null) {
          return restoreDiff!(persisted, task, project);
        }
        if (task != null && project != null) {
          final changeSet =
              await const ChangeSetService().load(taskId: task.id);
          if (changeSet != null && changeSet.files.isNotEmpty) {
            final conflicts = await const ChangeSetService().rollback(
              workspacePath: project.canonicalRootPath,
              changeSet: changeSet,
            );
            if (conflicts.isNotEmpty) {
              return ResultActionExecutionResult.failed(
                message:
                    '恢复文件遇到冲突：${conflicts.first.path}（${conflicts.first.reason}）',
              );
            }
            return ResultActionExecutionResult.succeeded(
              message: '文件已按变更集恢复（共恢复 ${changeSet.files.length} 个文件）',
              result: {
                'restoredFiles': changeSet.files.length,
                'taskId': task.id,
                'projectId': project.id,
              },
            );
          }
        }
        return const ResultActionExecutionResult.failed(
          message: '未找到可回滚的任务变更集或工作区路径，未修改任何文件',
        );

      case ('reminder.cancel', 'reminder.cancel'):
        if (persisted.kind != ResultCardKind.reminder) {
          return const ResultActionExecutionResult.failed(
            message: '卡片类型与取消提醒操作不匹配',
          );
        }
        final scheduled = await db.findScheduledTask(persisted.resourceId);
        if (!(canInteract?.call() ?? true) ||
            (request.canContinue != null && !await request.canContinue!())) {
          return const ResultActionExecutionResult.failed(
            message: '页面或资源状态已变化，未取消提醒',
          );
        }
        if (cancelReminder != null) {
          final ok = await cancelReminder!(persisted, scheduled);
          if (!ok) {
            return const ResultActionExecutionResult.failed(
              message: '取消提醒未完成',
            );
          }
        } else if (persisted.resourceType == 'reminder') {
          await ReminderService(db).cancel(persisted.resourceId);
        } else if (scheduled != null) {
          await db.saveScheduledTask(
            scheduled.copyWith(
              enabled: false,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
        } else {
          return const ResultActionExecutionResult.failed(
              message: '提醒资源不存在，未取消任何提醒');
        }
        return ResultActionExecutionResult.succeeded(
          message: '提醒计划已取消',
          result: {
            'resourceId': persisted.resourceId,
            'cancelled': true,
          },
        );

      case ('reminder.reschedule', 'reminder.reschedule'):
        if (persisted.kind != ResultCardKind.reminder) {
          return const ResultActionExecutionResult.failed(
            message: '卡片类型与改期提醒操作不匹配',
          );
        }
        final scheduled = await db.findScheduledTask(persisted.resourceId);
        if (!(canInteract?.call() ?? true) ||
            (request.canContinue != null && !await request.canContinue!())) {
          return const ResultActionExecutionResult.failed(
            message: '页面或资源状态已变化，未修改提醒时间',
          );
        }
        if (rescheduleReminder != null) {
          final ok = await rescheduleReminder!(persisted, scheduled);
          if (!ok) {
            return const ResultActionExecutionResult.failed(
              message: '改期提醒未完成',
            );
          }
        } else if (persisted.resourceType == 'reminder') {
          final raw = persisted.snapshot['scheduledAtUtc'];
          final when = raw is String ? DateTime.tryParse(raw) : null;
          if (when == null || !when.isAfter(DateTime.now().toUtc())) {
            return const ResultActionExecutionResult.failed(
                message: '缺少有效的新提醒时间，请先选择时间');
          }
          await ReminderService(db)
              .reschedule(persisted.resourceId, scheduledAtUtc: when);
        } else if (scheduled != null) {
          final nextCron = (persisted.snapshot['cron'] is String &&
                  (persisted.snapshot['cron'] as String).trim().isNotEmpty)
              ? (persisted.snapshot['cron'] as String).trim()
              : scheduled.cron;
          await db.saveScheduledTask(
            scheduled.copyWith(
              cron: nextCron,
              enabled: true,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
        } else {
          return const ResultActionExecutionResult.failed(
              message: '提醒资源不存在，未修改提醒时间');
        }
        return ResultActionExecutionResult.succeeded(
          message: '提醒时间已更新',
          result: {
            'resourceId': persisted.resourceId,
            'rescheduled': true,
          },
        );

      case ('calendar.adjust', 'calendar.adjust'):
        final calReq = resolveCalendarConnectorRequest(persisted);
        if (calReq == null) {
          return const ResultActionExecutionResult.failed(
            message: '日程参数缺失或格式不合法，无法打开日历编辑页',
          );
        }
        if (!(canInteract?.call() ?? true) ||
            (request.canContinue != null && !await request.canContinue!())) {
          return const ResultActionExecutionResult.failed(
            message: '页面或资源状态已变化，未打开日历编辑页',
          );
        }
        final launched = adjustCalendar != null
            ? await adjustCalendar!(calReq, persisted)
            : false;
        if (!launched) {
          return const ResultActionExecutionResult.failed(
            message: '日程调整未完成（系统日历不可用或已取消）',
          );
        }
        return ResultActionExecutionResult.succeeded(
          message: '已打开系统日历编辑器，仍需在日历中确认保存',
          result: {
            'delivery': 'system_editor_handoff_only',
            'connectorId': calReq.connector.name,
            'operation': calReq.operation,
            'resourceId': persisted.resourceId,
          },
        );

      case ('workflow.trial_run', 'workflow.trial_run'):
        if (persisted.kind != ResultCardKind.workflowTrial ||
            persisted.resourceType != 'workflow') {
          return const ResultActionExecutionResult.failed(
            message: '卡片类型与工作流试运行操作不匹配',
          );
        }
        if (!(canInteract?.call() ?? true) ||
            (request.canContinue != null && !await request.canContinue!())) {
          return const ResultActionExecutionResult.failed(
            message: '页面或资源状态已变化，未启动试运行',
          );
        }
        final bool started;
        if (trialRunWorkflow != null) {
          started = await trialRunWorkflow!(persisted);
        } else {
          final rawInputs = persisted.snapshot['inputs'];
          if (rawInputs is! Map || rawInputs.values.any((v) => v is! String)) {
            return const ResultActionExecutionResult.failed(
                message: '缺少工作流输入，未启动试运行');
          }
          final run = await MobileWorkflowService(db).runWorkflow(
            workflowId: persisted.resourceId,
            inputs: Map<String, String>.from(rawInputs),
            dryRun: true,
          );
          started = run.status == 'succeeded';
        }
        if (!started) {
          return const ResultActionExecutionResult.failed(
            message: '工作流试运行未完成，请查看运行输出后重试',
          );
        }
        return ResultActionExecutionResult.succeeded(
          message: '试运行已完成，结果未写入正式环境',
          result: {
            'mode': 'trial_run',
            'resourceId': persisted.resourceId,
          },
        );

      default:
        return const ResultActionExecutionResult.failed(
          message: '该结果卡操作未绑定可用执行器，未执行操作',
        );
    }
  }
}
