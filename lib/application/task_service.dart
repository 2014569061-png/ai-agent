import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/database/app_database.dart';

/// v0.9 各类开发任务共用的结构化结果载体。
class StructuredTaskResult {
  const StructuredTaskResult({
    this.summary = '',
    this.findings = const [],
    this.actions = const [],
    this.evidence = const [],
    this.nextSteps = const [],
  });

  final String summary;
  final List<Map<String, dynamic>> findings;
  final List<String> actions;
  final List<String> evidence;
  final List<String> nextSteps;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'findings': findings,
        'actions': actions,
        'evidence': evidence,
        'nextSteps': nextSteps,
      };

  factory StructuredTaskResult.fromJson(Map<String, dynamic> json) {
    final rawFindings = json['findings'] as List? ?? const [];
    return StructuredTaskResult(
      summary: json['summary']?.toString() ?? '',
      findings: rawFindings
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
      actions: _stringList(json['actions']),
      evidence: _stringList(json['evidence']),
      nextSteps: _stringList(json['nextSteps']),
    );
  }
}

/// 后台任务服务：统一维护开发任务的请求快照、状态、恢复次数和结果摘要。
///
/// v0.8 复用现有 Tasks 表，把扩展字段放入 JSON，避免破坏 v0.7 数据库。
class TaskService {
  Future<List<Task>> runningTasks(AppDatabase db) => db.runningTasks();

  Future<List<Task>> allTasks(AppDatabase db, {int limit = 100}) =>
      db.allTasks(limit: limit);

  Future<Task> create({
    required AppDatabase db,
    required String conversationId,
    required String requestJson,
    String type = 'agent',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    final now = DateTime.now();
    final task = Task(
      id: 'task-${now.microsecondsSinceEpoch}',
      conversationId: conversationId,
      type: type,
      status: 'running',
      requestJson: _mergeRequest(requestJson, metadata),
      progressJson: jsonEncode(<String, dynamic>{
        'phase': 'running',
        'updatedAt': now.toIso8601String(),
      }),
      resumeCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveTask(task);
    return task;
  }

  Future<void> updateStatus(AppDatabase db, String id, String status) =>
      db.updateTaskStatus(id, status);

  Future<void> updateProgress(
    AppDatabase db,
    String id, {
    required String phase,
    String? summary,
    String? runId,
    Map<String, dynamic>? extra,
    StructuredTaskResult? structuredResult,
  }) async {
    final task = await db.findTask(id);
    if (task == null) return;
    final progress = <String, dynamic>{
      'phase': phase,
      'updatedAt': DateTime.now().toIso8601String(),
      if (summary != null && summary.trim().isNotEmpty)
        'summary': _truncate(summary.trim(), 4000),
      if (runId != null && runId.trim().isNotEmpty) 'runId': runId,
      if (structuredResult != null) 'structuredResult': structuredResult.toJson(),
      ...?extra,
    };
    await db.saveTask(task.copyWith(
      progressJson: jsonEncode(progress),
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> complete(
    AppDatabase db,
    String id, {
    required String status,
    required String summary,
    String? runId,
  }) async {
    final task = await db.findTask(id);
    if (task == null) return;
    final progress = <String, dynamic>{
      'phase': status,
      'updatedAt': DateTime.now().toIso8601String(),
      'summary': _truncate(summary.trim(), 4000),
      if (runId != null && runId.trim().isNotEmpty) 'runId': runId,
    };
    await db.saveTask(task.copyWith(
      status: status,
      progressJson: jsonEncode(progress),
      updatedAt: DateTime.now(),
    ));
  }

  DevelopmentTaskInfo describe(Task task) => DevelopmentTaskInfo.fromTask(task);

  Future<void> markResumed(AppDatabase db, String id) async {
    final task = await db.findTask(id);
    if (task == null) return;
    await db.saveTask(task.copyWith(
      resumeCount: task.resumeCount + 1,
      updatedAt: DateTime.now(),
    ));
  }

  String _mergeRequest(String requestJson, Map<String, dynamic> metadata) {
    if (metadata.isEmpty) return requestJson;
    try {
      final decoded = jsonDecode(requestJson);
      if (decoded is Map<String, dynamic>) {
        return jsonEncode(<String, dynamic>{...decoded, ...metadata});
      }
    } catch (_) {
      // 旧调用方若传入非 JSON 文本，继续保留原始请求。
    }
    return jsonEncode(<String, dynamic>{'prompt': requestJson, ...metadata});
  }

  String _truncate(String value, int maxLength) =>
      value.length <= maxLength ? value : '${value.substring(0, maxLength)}…';
}

/// 页面层使用的稳定任务快照，集中处理旧任务和 v0.8 JSON 的兼容读取。
class DevelopmentTaskInfo {
  const DevelopmentTaskInfo({
    required this.id,
    required this.conversationId,
    required this.type,
    required this.status,
    required this.prompt,
    required this.title,
    required this.sourceType,
    required this.workspacePath,
    required this.model,
    required this.summary,
    required this.runId,
    required this.createdAt,
    required this.updatedAt,
    required this.resumeCount,
    this.structuredResult,
  });

  final String id;
  final String conversationId;
  final String type;
  final String status;
  final String prompt;
  final String title;
  final String sourceType;
  final String? workspacePath;
  final String? model;
  final String? summary;
  final String? runId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int resumeCount;
  final StructuredTaskResult? structuredResult;

  factory DevelopmentTaskInfo.fromTask(Task task) {
    final request = _decode(task.requestJson);
    final progress = _decode(task.progressJson);
    final prompt = (request['prompt'] ?? request['query'] ?? '').toString();
    final taskType = (request['taskType'] ?? task.type).toString();
    final title = (request['title'] ?? _titleFor(taskType, prompt)).toString();
    final workspace = request['workspacePath']?.toString();
    return DevelopmentTaskInfo(
      id: task.id,
      conversationId: task.conversationId,
      type: taskType,
      status: task.status,
      prompt: prompt,
      title: title,
      sourceType: (request['sourceType'] ?? 'manual').toString(),
      workspacePath: workspace == null || workspace.isEmpty ? null : workspace,
      model: request['model']?.toString(),
      summary: progress['summary']?.toString(),
      runId: progress['runId']?.toString(),
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
      resumeCount: task.resumeCount,
      structuredResult: progress['structuredResult'] is Map
          ? StructuredTaskResult.fromJson(
              Map<String, dynamic>.from(progress['structuredResult'] as Map))
          : null,
    );
  }

  static Map<String, dynamic> _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  static String _titleFor(String type, String prompt) {
    const labels = <String, String>{
      'project_analysis': '项目解读',
      'bug_fix': '问题修复',
      'code_review': '代码审查',
      'release_check': '发布检查',
    };
    final label = labels[type] ?? '开发任务';
    final shortPrompt = prompt.trim();
    if (shortPrompt.isEmpty) return label;
    return '$label：${shortPrompt.length > 28 ? '${shortPrompt.substring(0, 28)}…' : shortPrompt}';
  }
}

List<String> _stringList(dynamic value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];

final taskServiceProvider = Provider<TaskService>((ref) => TaskService());
