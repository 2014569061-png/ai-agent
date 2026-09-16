import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import 'execution_lease_service.dart';
import 'project_service.dart';
import 'task_service.dart';

enum TaskControlKind { followUp, pause, resume, cancel }

class DevelopmentTaskRequest {
  const DevelopmentTaskRequest({
    required this.prompt,
    required this.conversationId,
    this.projectId,
    this.workspacePath,
    this.taskType = 'general',
    this.sourceType = 'manual',
    this.requestId,
    this.attachments = const [],
  });

  final String prompt;
  final String conversationId;
  final String? projectId;
  final String? workspacePath;
  final String taskType;
  final String sourceType;
  final String? requestId;
  final List<String> attachments;
}

class TaskHandle {
  const TaskHandle({
    required this.taskId,
    required this.requestId,
    required this.status,
  });

  final String taskId;
  final String requestId;
  final String status;
}

class TaskControlRequest {
  const TaskControlRequest({
    required this.taskId,
    required this.kind,
    required this.clientControlId,
    this.runId,
    this.payload = const {},
  });

  final String taskId;
  final TaskControlKind kind;
  final String clientControlId;
  final String? runId;
  final Map<String, dynamic> payload;
}

class ControlReceipt {
  const ControlReceipt({
    required this.id,
    required this.status,
    required this.duplicate,
    this.message,
  });

  final String id;
  final String status;
  final bool duplicate;
  final String? message;
}

class DevelopmentExecutionService {
  DevelopmentExecutionService({
    required this.db,
    TaskService? tasks,
    ExecutionLeaseService? leases,
  })  : _tasks = tasks ?? TaskService(),
        _leases = leases ?? const ExecutionLeaseService();

  final AppDatabase db;
  final TaskService _tasks;
  final ExecutionLeaseService _leases;

  Future<TaskHandle> enqueue(DevelopmentTaskRequest request) async {
    final requestId = (request.requestId == null || request.requestId!.isEmpty)
        ? UniqueId.generate('req')
        : request.requestId!;
    final existing = await _tasks.findByRequestId(db, requestId);
    if (existing != null) {
      return TaskHandle(
        taskId: existing.id,
        requestId: requestId,
        status: existing.status,
      );
    }
    final task = await _tasks.create(
      db: db,
      conversationId: request.conversationId,
      type: 'development:${request.taskType}',
      requestJson: '{}',
      metadata: {
        'prompt': request.prompt,
        'taskType': request.taskType,
        'sourceType': request.sourceType,
        'workspacePath': request.workspacePath,
        if (request.projectId != null) 'projectId': request.projectId,
        'requestId': requestId,
        'attachments': request.attachments,
      },
    );
    var status = task.status;
    if (request.workspacePath != null &&
        request.workspacePath!.trim().isNotEmpty) {
      try {
        await _leases.acquire(
          db: db,
          resourceKey: ExecutionLeaseService.workspaceKey(
              ProjectService.canonicalizePath(request.workspacePath!)),
          taskId: task.id,
          runId: requestId,
        );
      } on ExecutionLeaseConflict {
        await _tasks.updateStatus(db, task.id, 'queued');
        status = 'queued';
      }
    }
    return TaskHandle(
      taskId: task.id,
      requestId: requestId,
      status: status,
    );
  }

  Future<ControlReceipt> submitControl(TaskControlRequest request) async {
    final existing = await db.findRunControlByClientId(request.clientControlId);
    if (existing != null) {
      return ControlReceipt(
        id: existing.id,
        status: existing.status,
        duplicate: true,
        message: '已接收，将在下一检查点生效',
      );
    }
    final task = await db.findTask(request.taskId);
    if (task == null) {
      return const ControlReceipt(
        id: '',
        status: 'rejected',
        duplicate: false,
        message: '任务不存在',
      );
    }
    final terminal = const {
      'completed',
      'failed',
      'cancelled',
    };
    if (terminal.contains(task.status) &&
        request.kind == TaskControlKind.followUp) {
      return const ControlReceipt(
        id: '',
        status: 'rejected',
        duplicate: false,
        message: '任务已结束',
      );
    }
    final sequence = await db.nextRunControlSequence(request.taskId);
    final row = RunControl(
      id: UniqueId.generate('ctrl'),
      clientControlId: request.clientControlId,
      taskId: request.taskId,
      runId: request.runId,
      kind: request.kind.name,
      payloadJson: _encode(request.payload),
      status: 'pending',
      sequenceNo: sequence,
      createdAt: DateTime.now(),
    );
    await db.saveRunControl(row);
    if (request.kind == TaskControlKind.pause) {
      await _tasks.updateStatus(db, request.taskId, 'pause_requested');
    } else if (request.kind == TaskControlKind.cancel) {
      await _tasks.updateStatus(db, request.taskId, 'cancel_requested');
    }
    return ControlReceipt(
      id: row.id,
      status: row.status,
      duplicate: false,
      message:
          request.kind == TaskControlKind.followUp ? '已接收，将在下一检查点生效' : null,
    );
  }

  Future<List<RunControl>> drainPending({
    required String taskId,
    String? runId,
  }) async {
    final pending = await db.pendingRunControls(taskId: taskId, runId: runId);
    final now = DateTime.now();
    for (final row in pending) {
      await db.saveRunControl(row.copyWith(
        status: 'consumed',
        consumedAt: Value(now),
      ));
    }
    return pending;
  }

  String _encode(Map<String, dynamic> payload) => jsonEncode(payload);
}
