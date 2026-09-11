import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../infrastructure/database/app_database.dart';
import '../domain/sensitive_tool_policy.dart';

/// v0.9 各类开发任务共用的结构化结果载体。
class StructuredTaskResult {
  const StructuredTaskResult({
    this.summary = '',
    this.findings = const [],
    this.actions = const [],
    this.evidence = const [],
    this.nextSteps = const [],
    this.risks = const [],
  });

  final String summary;
  final List<Map<String, dynamic>> findings;
  final List<String> actions;
  final List<String> evidence;
  final List<String> nextSteps;
  final List<String> risks;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'findings': findings,
        'actions': actions,
        'evidence': evidence,
        'nextSteps': nextSteps,
        'risks': risks,
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
      risks: _stringList(json['risks']),
    );
  }
}

/// 后台任务服务：统一维护开发任务的请求快照、状态、恢复次数和结果摘要。
///
/// v0.8 复用现有 Tasks 表，把扩展字段放入 JSON，避免破坏 v0.7 数据库。
class TaskService {
  static const maxAppliedRunIds = 128;

  // id 若只用微秒时间戳，Windows 时钟粒度下连续两次 create 可能取到同值，
  // insertOnConflictUpdate 会静默覆盖上一条任务。这里用随机后缀保证唯一。
  static final Random _idRandom = Random();

  static String _newTaskId() =>
      'task-${DateTime.now().microsecondsSinceEpoch}-${_idRandom.nextInt(0x7fffffff)}';

  Future<List<Task>> runningTasks(AppDatabase db) => db.runningTasks();

  /// 恢复入口用：running（进程被杀遗留）与 paused（预算暂停）都可续跑。
  Future<List<Task>> resumableTasks(AppDatabase db) => db.resumableTasks();

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
      id: _newTaskId(),
      conversationId: conversationId,
      type: type,
      status: 'running',
      requestJson: _mergeRequest(requestJson, metadata),
      progressJson: jsonEncode(<String, dynamic>{
        'phase': 'running',
        'updatedAt': now.toIso8601String(),
        'appliedRunIds': <String>[],
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
    Map<String, dynamic>? checkpoint,
  }) async {
    final task = await db.findTask(id);
    if (task == null) return;
    final previous = _decodeJsonMap(task.progressJson);
    final progress = <String, dynamic>{
      ...previous,
      'phase': phase,
      'updatedAt': DateTime.now().toIso8601String(),
      if (summary != null && summary.trim().isNotEmpty)
        'summary': _truncate(summary.trim(), 4000),
      if (runId != null && runId.trim().isNotEmpty) 'runId': runId,
      if (structuredResult != null)
        'structuredResult': structuredResult.toJson(),
      if (checkpoint != null) 'checkpoint': checkpoint,
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
    Map<String, dynamic>? checkpoint,
  }) async {
    final task = await db.findTask(id);
    if (task == null) return;
    final previous = _decodeJsonMap(task.progressJson);
    final appliedRunIds = _readAppliedRunIds(previous['appliedRunIds']);
    // 终态 ACK 可能因进程重启重复到达；同一 runId 已落库时直接保持原结果，
    // 避免后来的重复回调覆盖首个摘要或再次触发会话投影。
    if (status != 'paused' &&
        runId != null &&
        appliedRunIds.contains(runId.trim())) {
      return;
    }
    final progress = <String, dynamic>{
      ...previous,
      'phase': status,
      'updatedAt': DateTime.now().toIso8601String(),
      'summary': _truncate(summary.trim(), 4000),
      if (runId != null && runId.trim().isNotEmpty) 'runId': runId,
    };
    // 只有可恢复暂停保留 checkpoint；完成、失败和取消必须清掉，避免
    // 下次误把旧工具结果当成当前运行的断点再次提交。
    if (status == 'paused' && checkpoint != null) {
      progress['checkpoint'] = checkpoint;
    } else if (status != 'paused') {
      progress.remove('checkpoint');
      if (runId != null && runId.trim().isNotEmpty) {
        _appendRunId(appliedRunIds, runId);
      }
    }
    progress['appliedRunIds'] = appliedRunIds;
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

  /// 读取任务进度快照。恢复逻辑只从这里取得 checkpoint，不重新解析原始
  /// prompt 推断“哪些工具可能已经执行”。
  Future<Map<String, dynamic>> progress(AppDatabase db, String id) async {
    final task = await db.findTask(id);
    return task == null ? const {} : _decodeJsonMap(task.progressJson);
  }

  Future<void> clearCheckpoint(AppDatabase db, String id) async {
    final task = await db.findTask(id);
    if (task == null) return;
    final progress = _decodeJsonMap(task.progressJson)..remove('checkpoint');
    await db.saveTask(task.copyWith(
      progressJson: jsonEncode(progress),
      updatedAt: DateTime.now(),
    ));
  }

  /// 将一次已经写回会话/任务结果的 run 显式登记，避免进程重启或重复 ACK
  /// 时再次把同一终态结果追加到会话。列表有界，避免长期运行任务无限增长。
  Future<bool> markRunApplied(
    AppDatabase db,
    String id,
    String runId,
  ) async {
    final normalized = runId.trim();
    if (normalized.isEmpty) return false;
    return db.transaction(() async {
      final task = await db.findTask(id);
      if (task == null) return false;
      final progress = _decodeJsonMap(task.progressJson);
      final appliedRunIds = _readAppliedRunIds(progress['appliedRunIds']);
      if (appliedRunIds.contains(normalized)) return false;
      _appendRunId(appliedRunIds, normalized);
      progress['appliedRunIds'] = appliedRunIds;
      await db.saveTask(task.copyWith(
        progressJson: jsonEncode(progress),
        updatedAt: DateTime.now(),
      ));
      return true;
    });
  }

  bool isRunApplied(Map<String, dynamic> progress, String runId) =>
      _readAppliedRunIds(progress['appliedRunIds']).contains(runId.trim());

  List<String> appliedRunIds(Map<String, dynamic> progress) =>
      _readAppliedRunIds(progress['appliedRunIds']);

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

  List<String> _readAppliedRunIds(dynamic value) => value is List
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: true)
      : <String>[];

  void _appendRunId(List<String> ids, String runId) {
    final normalized = runId.trim();
    if (normalized.isEmpty) return;
    ids.remove(normalized);
    ids.add(normalized);
    if (ids.length > maxAppliedRunIds) {
      ids.removeRange(0, ids.length - maxAppliedRunIds);
    }
  }
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

Map<String, dynamic> _decodeJsonMap(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is Map<String, dynamic>
        ? Map<String, dynamic>.from(decoded)
        : {};
  } catch (_) {
    return {};
  }
}

Map<String, dynamic> chatMessageToJson(ChatMessage message) => {
      'role': message.role.name,
      'parts': message.parts
          .map((part) => {
                'type': part.type,
                'value': part.value,
                if (part.mimeType != null) 'mimeType': part.mimeType,
              })
          .toList(growable: false),
      if (message.toolCallId != null) 'toolCallId': message.toolCallId,
      if (message.toolCalls.isNotEmpty)
        'toolCalls': message.toolCalls
            .map((call) => {
                  'id': call.id,
                  'name': call.name,
                  'arguments': call.arguments,
                })
            .toList(growable: false),
      if (message.modelName != null) 'modelName': message.modelName,
      if (message.reasoning != null) 'reasoning': message.reasoning,
      if (message.usage != null)
        'usage': {
          'promptTokens': message.usage!.promptTokens,
          'completionTokens': message.usage!.completionTokens,
          'cachedTokens': message.usage!.cachedTokens,
        },
    };

ChatMessage? chatMessageFromJson(dynamic value) {
  if (value is! Map) return null;
  final map = Map<String, dynamic>.from(value);
  final role = MessageRole.values.firstWhere(
    (item) => item.name == map['role'],
    orElse: () => MessageRole.assistant,
  );
  final rawParts = map['parts'];
  final parts = rawParts is List
      ? rawParts.whereType<Map>().map((raw) {
          final item = Map<String, dynamic>.from(raw);
          final type = item['type']?.toString() ?? 'text';
          final content = item['value']?.toString() ?? '';
          final mime = item['mimeType']?.toString();
          return switch (type) {
            'image' => MessagePart.image(content, mimeType: mime),
            'file' => MessagePart.file(content, mimeType: mime),
            'audio' => MessagePart.audio(content, mimeType: mime),
            'video' => MessagePart.video(content, mimeType: mime),
            _ => MessagePart.text(content),
          };
        }).toList(growable: false)
      : const <MessagePart>[];
  final rawCalls = map['toolCalls'];
  final calls = rawCalls is List
      ? rawCalls.whereType<Map>().map((raw) {
          final item = Map<String, dynamic>.from(raw);
          return ToolCall(
            id: item['id']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            arguments: item['arguments'] is Map
                ? Map<String, dynamic>.from(item['arguments'] as Map)
                : const {},
          );
        }).toList(growable: false)
      : const <ToolCall>[];
  final usageMap = map['usage'];
  final usage = usageMap is Map
      ? Usage(
          promptTokens: (usageMap['promptTokens'] as num?)?.toInt() ?? 0,
          completionTokens:
              (usageMap['completionTokens'] as num?)?.toInt() ?? 0,
          cachedTokens: (usageMap['cachedTokens'] as num?)?.toInt() ?? 0,
        )
      : null;
  return ChatMessage(
    role: role,
    parts: parts.isEmpty ? [const MessagePart.text('')] : parts,
    toolCallId: map['toolCallId']?.toString(),
    toolCalls: calls,
    modelName: map['modelName']?.toString(),
    reasoning: map['reasoning']?.toString(),
    usage: usage,
  );
}

List<Map<String, dynamic>> encodeChatContext(Iterable<ChatMessage> context) =>
    context.map(chatMessageToJson).toList(growable: false);

/// 将暂停 checkpoint 写入任务 JSON 前做一次与会话/保险箱相同的脱敏。
///
/// 内存中的当前回合仍保留原文，只有跨进程恢复所需的持久化快照使用占位符；
/// 这样既不改变本轮模型上下文，也不会让剪贴板、图片或记忆内容进入任务表。
List<Map<String, dynamic>> encodeChatContextForPersistence(
    Iterable<ChatMessage> context) {
  final messages = context.toList(growable: false);
  final toolNames = <String, String>{};
  for (final message in messages) {
    for (final call in message.toolCalls) {
      toolNames[call.id] = call.name;
    }
  }
  return messages.map((message) {
    final raw = chatMessageToJson(message);
    if (message.role == MessageRole.assistant && message.toolCalls.isNotEmpty) {
      raw['toolCalls'] = message.toolCalls.map((call) {
        return <String, dynamic>{
          'id': call.id,
          'name': call.name,
          'arguments':
              SensitiveToolPolicy.redactArguments(call.name, call.arguments),
        };
      }).toList(growable: false);
    }
    if (message.role == MessageRole.tool) {
      final toolName = toolNames[message.toolCallId];
      if (toolName != null && SensitiveToolPolicy.isResultSensitive(toolName)) {
        raw['parts'] = [
          <String, dynamic>{
            'type': 'text',
            'value': '[敏感工具结果已脱敏]',
          }
        ];
      }
    }
    return raw;
  }).toList(growable: false);
}

List<ChatMessage> decodeChatContext(dynamic value) {
  if (value is! List) return const [];
  return value.map(chatMessageFromJson).whereType<ChatMessage>().toList();
}

final taskServiceProvider = Provider<TaskService>((ref) => TaskService());
