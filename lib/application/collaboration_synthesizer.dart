import 'dart:convert';

import '../domain/collaboration_models.dart';

class CollaborationSynthesizer {
  CollaborationResult synthesize({
    required CollaborationAgentRole reviewerRole,
    required List<CollaborationAgentOutput> outputs,
  }) {
    final parsed = <Map<String, dynamic>>[];
    final rawTexts = <String>[];
    final disagreements = <String>[];
    final findings = <CollaborationFinding>[];
    final actions = <String>[];
    final evidence = <String>[];
    final nextSteps = <String>[];
    final risks = <String>[];
    final findingsByTitle =
        <String, List<(CollaborationAgentRole, CollaborationFinding)>>{};
    var confidenceTotal = 0.0;
    var confidenceCount = 0;

    for (final output in outputs) {
      rawTexts.add('${output.role.label}: ${output.text}'.trim());
      if (output.failed) {
        disagreements.add('${output.role.label} 未完成：${output.error ?? '执行失败'}');
        continue;
      }
      final decoded = _decode(output.text);
      if (decoded == null) {
        disagreements.add('${output.role.label} 未返回可解析的结构化结果');
        continue;
      }
      parsed.add(decoded);
      final rawFindings = decoded['findings'];
      if (rawFindings is List) {
        for (final item in rawFindings.whereType<Map>()) {
          final finding =
              CollaborationFinding.fromJson(Map<String, dynamic>.from(item));
          findings.add(finding);
          final key = finding.title.trim().toLowerCase();
          if (key.isNotEmpty) {
            findingsByTitle
                .putIfAbsent(key, () => [])
                .add((output.role, finding));
          }
        }
      }
      actions.addAll(_stringList(decoded['actions']));
      evidence.addAll(_stringList(decoded['evidence']));
      nextSteps.addAll(_stringList(decoded['nextSteps']));
      risks.addAll(_stringList(decoded['risks']));
      final confidence = (decoded['confidence'] as num?)?.toDouble();
      if (confidence != null) {
        confidenceTotal += confidence.clamp(0.0, 1.0);
        confidenceCount++;
      }
    }

    final uniqueFindings = <String, CollaborationFinding>{};
    for (final finding in findings) {
      uniqueFindings['${finding.title}|${finding.detail}'] = finding;
    }
    for (final entry in findingsByTitle.entries) {
      final details = entry.value
          .map((item) => item.$2.detail.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      if (details.length > 1) {
        final roles =
            entry.value.map((item) => item.$1.label).toSet().join('、');
        disagreements
            .add('发现不一致：${entry.value.first.$2.title}（$roles 给出了不同证据或结论）');
      }
    }
    final summary = parsed.isEmpty
        ? '协作分析未形成可解析的结构化结论，请查看各角色原始输出。'
        : '已汇总 ${parsed.length} 个子 Agent 的分析结果，共 ${uniqueFindings.length} 个发现。';
    final hasReviewer = outputs.any((output) => output.role == reviewerRole);
    if (!hasReviewer) {
      disagreements.add('未执行审查 Agent，结论缺少独立质疑环节。');
    }
    return CollaborationResult(
      summary: summary,
      findings: uniqueFindings.values.toList(growable: false),
      actions: _unique(actions),
      evidence: _unique(evidence),
      nextSteps: _unique(nextSteps),
      disagreements: _unique(disagreements),
      risks: _unique(risks),
      confidence: confidenceCount == 0
          ? 0.0
          : (confidenceTotal / confidenceCount).clamp(0.0, 1.0),
      rawSynthesis: rawTexts.join('\n\n'),
    );
  }

  Map<String, dynamic>? _decode(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      try {
        final decoded = jsonDecode(trimmed.substring(start, end + 1));
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {
        return null;
      }
    }
  }

  List<String> _stringList(dynamic value) => value is List
      ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];

  List<String> _unique(List<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
