import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../infrastructure/database/app_database.dart';
import '../infrastructure/observability/unified_diff.dart';
import '../infrastructure/tools/workspace_tools.dart';

/// 从运行事件生成稳定的副作用审计视图。
///
/// 审计层只消费已经脱敏的 RunEvent，不重新读取工具参数或工作区文件，
/// 这样导出不会绕过敏感数据策略，也不会因为当前文件状态变化而改写历史事实。
class RunAuditReport {
  const RunAuditReport({required this.entries, required this.metrics});

  final List<RunAuditEntry> entries;
  final RunAuditMetrics metrics;

  factory RunAuditReport.fromEvents(Iterable<RunEvent> events) {
    final entries = <RunAuditEntry>[];
    var retries = 0;
    var promptTokens = 0;
    var completionTokens = 0;
    var cachedTokens = 0;
    var estimatedCostCents = 0;
    var hasEstimatedCost = false;
    for (final event in events) {
      final metadata = _decode(event.metadataJson);
      if (event.type == 'network' && event.name.contains('重试')) retries++;
      if (event.type == 'model_request' && event.name.contains('重试')) {
        retries++;
      }
      final prompt = _intValue(metadata['promptTokens']);
      final completion = _intValue(metadata['completionTokens']);
      final cached = _intValue(metadata['cachedTokens']);
      if (prompt != null) promptTokens = prompt;
      if (completion != null) completionTokens = completion;
      if (cached != null) cachedTokens = cached;
      final cost = _intValue(metadata['estimatedCostCents']);
      if (cost != null) {
        estimatedCostCents = cost;
        hasEstimatedCost = true;
      }
      if (event.type != 'tool_call' && event.type != 'file_operation') continue;
      final effect = _effect(metadata['effect']);
      if (effect == null && metadata['fileOperation'] != true) continue;
      entries.add(RunAuditEntry(
        eventId: event.eventId,
        sequenceNo: event.sequenceNo,
        tool: event.name,
        status: event.status,
        effect: effect ?? 'none',
        code: metadata['toolCode']?.toString() ?? '',
        path: metadata['path']?.toString(),
        operation: metadata['operation']?.toString() ?? event.name,
        evidence: event.outputSummary,
        metadata: metadata,
      ));
    }
    return RunAuditReport(
      entries: List.unmodifiable(entries),
      metrics: RunAuditMetrics(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        cachedTokens: cachedTokens,
        retryCount: retries,
        estimatedCostCents: hasEstimatedCost ? estimatedCostCents : null,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'metrics': metrics.toJson(),
        'entries': entries.map((entry) => entry.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  static Map<String, dynamic> _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  static int? _intValue(dynamic value) => value is num ? value.toInt() : null;

  static String? _effect(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'none' => 'none',
      'applied' => 'applied',
      'unknown' => 'unknown',
      _ => null,
    };
  }
}

class RunAuditEntry {
  const RunAuditEntry({
    required this.eventId,
    required this.sequenceNo,
    required this.tool,
    required this.status,
    required this.effect,
    required this.code,
    required this.operation,
    this.path,
    this.evidence,
    this.metadata = const {},
  });

  final String eventId;
  final int sequenceNo;
  final String tool;
  final String status;
  final String effect;
  final String code;
  final String operation;
  final String? path;
  final String? evidence;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'sequence': sequenceNo,
        'tool': tool,
        'status': status,
        'effect': effect,
        'code': code,
        'operation': operation,
        if (path != null) 'path': path,
        if (evidence != null) 'evidence': evidence,
      };
}

class RunAuditMetrics {
  const RunAuditMetrics({
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedTokens,
    required this.retryCount,
    this.estimatedCostCents,
  });

  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;
  final int retryCount;
  final int? estimatedCostCents;

  Map<String, dynamic> toJson() => {
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'cachedTokens': cachedTokens,
        'retryCount': retryCount,
        if (estimatedCostCents != null)
          'estimatedCostCents': estimatedCostCents,
      };
}

class AuditRollbackResult {
  const AuditRollbackResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

/// Performs a guarded reverse patch for an audited `edit_file` event.
///
/// The content hash check is deliberately done immediately before writing. A
/// later manual edit therefore turns into an explicit conflict instead of an
/// implicit overwrite.
class AuditRollbackService {
  Future<AuditRollbackResult> rollbackEditFile({
    required String workspacePath,
    required RunAuditEntry entry,
  }) async {
    if (entry.tool != 'edit_file' || entry.operation != 'edit') {
      return const AuditRollbackResult(
          ok: false, message: '只有 edit_file 的编辑事件支持回滚');
    }
    if (entry.effect != 'applied') {
      return const AuditRollbackResult(
          ok: false, message: '该步骤没有确认的 applied 副作用，不能自动回滚');
    }
    final path = entry.path?.trim();
    final diff = entry.metadata['diff']?.toString();
    if (path == null || path.isEmpty || diff == null || diff.isEmpty) {
      return const AuditRollbackResult(
          ok: false, message: '审计记录缺少可逆 diff，需手动检查文件');
    }
    if (diff.contains('[REDACTED]')) {
      return const AuditRollbackResult(
          ok: false, message: 'diff 含脱敏内容，无法安全自动回滚');
    }

    final String fullPath;
    try {
      fullPath = WorkspaceSandbox(workspacePath).resolvePath(path);
    } on ArgumentError {
      return const AuditRollbackResult(ok: false, message: '文件路径超出当前工作区，拒绝回滚');
    }
    final file = File(fullPath);
    try {
      if (!await file.exists()) {
        return const AuditRollbackResult(ok: false, message: '目标文件不存在');
      }
      final current = await file.readAsString();
      final expectedAfter = entry.metadata['contentHashAfter']?.toString();
      if (expectedAfter != null && expectedAfter.isNotEmpty) {
        final currentHash = sha256.convert(utf8.encode(current)).toString();
        if (currentHash != expectedAfter) {
          return const AuditRollbackResult(
              ok: false, message: '文件已被后续修改，回滚前请重新读取并确认');
        }
      }
      final restored = applyUnifiedDiff(current, diff, reverse: true);
      if (restored == null) {
        return const AuditRollbackResult(
            ok: false, message: 'diff 与当前文件不匹配，拒绝覆盖');
      }
      final expectedBefore = entry.metadata['contentHashBefore']?.toString();
      if (expectedBefore != null && expectedBefore.isNotEmpty) {
        final restoredHash = sha256.convert(utf8.encode(restored)).toString();
        if (restoredHash != expectedBefore) {
          return const AuditRollbackResult(
              ok: false, message: '反向 diff 校验失败，未写入文件');
        }
      }
      await file.writeAsString(restored, flush: true);
      return AuditRollbackResult(ok: true, message: '已回滚 $path');
    } catch (error) {
      return AuditRollbackResult(ok: false, message: '回滚失败：$error');
    }
  }
}
