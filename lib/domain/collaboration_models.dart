import 'dart:convert';

enum CollaborationMode { parallel, debate, sequential }

enum CollaborationStatus {
  draft,
  awaitingApproval,
  queued,
  discussing,
  synthesizing,
  awaitingExecutionApproval,
  completed,
  failed,
  cancelled,
}

enum CollaborationAgentRole { planner, analyzer, tester, reviewer }

extension CollaborationModeX on CollaborationMode {
  String get wireName => switch (this) {
        CollaborationMode.parallel => 'parallel',
        CollaborationMode.debate => 'debate',
        CollaborationMode.sequential => 'sequential',
      };

  String get label => switch (this) {
        CollaborationMode.parallel => '并行调研',
        CollaborationMode.debate => '辩论收敛',
        CollaborationMode.sequential => '顺序接力',
      };

  static CollaborationMode parse(String value) => switch (value) {
        'debate' => CollaborationMode.debate,
        'sequential' => CollaborationMode.sequential,
        _ => CollaborationMode.parallel,
      };
}

extension CollaborationStatusX on CollaborationStatus {
  String get wireName => switch (this) {
        CollaborationStatus.draft => 'draft',
        CollaborationStatus.awaitingApproval => 'awaiting_approval',
        CollaborationStatus.queued => 'queued',
        CollaborationStatus.discussing => 'discussing',
        CollaborationStatus.synthesizing => 'synthesizing',
        CollaborationStatus.awaitingExecutionApproval =>
          'awaiting_execution_approval',
        CollaborationStatus.completed => 'completed',
        CollaborationStatus.failed => 'failed',
        CollaborationStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        CollaborationStatus.draft => '草稿',
        CollaborationStatus.awaitingApproval => '等待协作审批',
        CollaborationStatus.queued => '排队中',
        CollaborationStatus.discussing => '子 Agent 讨论中',
        CollaborationStatus.synthesizing => '主 Agent 汇总中',
        CollaborationStatus.awaitingExecutionApproval => '等待执行审批',
        CollaborationStatus.completed => '已完成',
        CollaborationStatus.failed => '失败',
        CollaborationStatus.cancelled => '已取消',
      };

  static CollaborationStatus parse(String value) {
    return CollaborationStatus.values.firstWhere(
      (status) => status.wireName == value,
      orElse: () => CollaborationStatus.draft,
    );
  }
}

extension CollaborationAgentRoleX on CollaborationAgentRole {
  String get wireName => switch (this) {
        CollaborationAgentRole.planner => 'planner',
        CollaborationAgentRole.analyzer => 'analyzer',
        CollaborationAgentRole.tester => 'tester',
        CollaborationAgentRole.reviewer => 'reviewer',
      };

  String get label => switch (this) {
        CollaborationAgentRole.planner => '任务规划 Agent',
        CollaborationAgentRole.analyzer => '代码分析 Agent',
        CollaborationAgentRole.tester => '测试验证 Agent',
        CollaborationAgentRole.reviewer => '审查 Agent',
      };

  String get responsibility => switch (this) {
        CollaborationAgentRole.planner => '澄清目标、拆分子任务并定义验收条件',
        CollaborationAgentRole.analyzer => '阅读授权工作区并定位模块、依赖和风险',
        CollaborationAgentRole.tester => '设计验证方案并分析测试、构建和复现路径',
        CollaborationAgentRole.reviewer => '质疑候选方案，寻找遗漏和安全、回归风险',
      };

  List<String> get allowedTools => switch (this) {
        CollaborationAgentRole.planner => const ['json_query'],
        CollaborationAgentRole.analyzer => const [
            'read_file',
            'list_directory',
            'search_files'
          ],
        CollaborationAgentRole.tester => const [
            'read_file',
            'list_directory',
            'search_files'
          ],
        CollaborationAgentRole.reviewer => const ['json_query'],
      };

  static CollaborationAgentRole parse(String value) {
    return CollaborationAgentRole.values.firstWhere(
      (role) => role.wireName == value,
      orElse: () => CollaborationAgentRole.reviewer,
    );
  }
}

class DevelopmentTaskInput {
  const DevelopmentTaskInput({
    required this.taskId,
    required this.prompt,
    this.taskType = 'general',
    this.workspacePath,
    this.model,
  });

  final String taskId;
  final String prompt;
  final String taskType;
  final String? workspacePath;
  final String? model;
}

class CollaborationAgentSpec {
  const CollaborationAgentSpec({
    required this.id,
    required this.role,
    required this.maxRounds,
    this.contextManifest = const [],
    this.allowedTools = const [],
  });

  final String id;
  final CollaborationAgentRole role;
  final int maxRounds;
  final List<String> contextManifest;
  final List<String> allowedTools;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.wireName,
        'maxRounds': maxRounds,
        'contextManifest': contextManifest,
        'allowedTools': allowedTools,
      };

  factory CollaborationAgentSpec.fromJson(Map<String, dynamic> json) {
    final role = CollaborationAgentRoleX.parse(json['role']?.toString() ?? '');
    return CollaborationAgentSpec(
      id: json['id']?.toString() ?? role.wireName,
      role: role,
      maxRounds: (json['maxRounds'] as num?)?.toInt() ?? 1,
      contextManifest: _stringList(json['contextManifest']),
      allowedTools: _stringList(json['allowedTools']).isEmpty
          ? role.allowedTools
          : _stringList(json['allowedTools']),
    );
  }
}

class CollaborationPlan {
  const CollaborationPlan({
    required this.runId,
    required this.taskId,
    required this.mode,
    required this.agents,
    required this.budgetTokens,
    required this.maxAgents,
    required this.maxRounds,
    required this.estimatedTokens,
    required this.estimatedDurationSeconds,
    required this.contextManifest,
    required this.riskLevel,
  });

  final String runId;
  final String taskId;
  final CollaborationMode mode;
  final List<CollaborationAgentSpec> agents;
  final int budgetTokens;
  final int maxAgents;
  final int maxRounds;
  final int estimatedTokens;
  final int estimatedDurationSeconds;
  final List<String> contextManifest;
  final String riskLevel;

  Map<String, dynamic> toJson() => {
        'runId': runId,
        'taskId': taskId,
        'mode': mode.wireName,
        'agents': agents.map((agent) => agent.toJson()).toList(),
        'budgetTokens': budgetTokens,
        'maxAgents': maxAgents,
        'maxRounds': maxRounds,
        'estimatedTokens': estimatedTokens,
        'estimatedDurationSeconds': estimatedDurationSeconds,
        'contextManifest': contextManifest,
        'riskLevel': riskLevel,
      };

  String encode() => jsonEncode(toJson());

  factory CollaborationPlan.fromJson(Map<String, dynamic> json) {
    final rawAgents = json['agents'] as List? ?? const [];
    return CollaborationPlan(
      runId: json['runId']?.toString() ?? '',
      taskId: json['taskId']?.toString() ?? '',
      mode: CollaborationModeX.parse(json['mode']?.toString() ?? ''),
      agents: rawAgents
          .whereType<Map>()
          .map((item) =>
              CollaborationAgentSpec.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      budgetTokens: (json['budgetTokens'] as num?)?.toInt() ?? 4000,
      maxAgents: (json['maxAgents'] as num?)?.toInt() ?? 3,
      maxRounds: (json['maxRounds'] as num?)?.toInt() ?? 1,
      estimatedTokens: (json['estimatedTokens'] as num?)?.toInt() ?? 0,
      estimatedDurationSeconds:
          (json['estimatedDurationSeconds'] as num?)?.toInt() ?? 0,
      contextManifest: _stringList(json['contextManifest']),
      riskLevel: json['riskLevel']?.toString() ?? 'read_only',
    );
  }

  static CollaborationPlan decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return CollaborationPlan.fromJson(
          decoded is Map ? Map<String, dynamic>.from(decoded) : const {});
    } catch (_) {
      return const CollaborationPlan(
        runId: '',
        taskId: '',
        mode: CollaborationMode.parallel,
        agents: [],
        budgetTokens: 4000,
        maxAgents: 3,
        maxRounds: 1,
        estimatedTokens: 0,
        estimatedDurationSeconds: 0,
        contextManifest: [],
        riskLevel: 'read_only',
      );
    }
  }
}

class CollaborationApproval {
  const CollaborationApproval({
    required this.budgetTokens,
    required this.maxAgents,
    required this.maxRounds,
    required this.mode,
  });

  final int budgetTokens;
  final int maxAgents;
  final int maxRounds;
  final CollaborationMode mode;

  Map<String, dynamic> toJson() => {
        'budgetTokens': budgetTokens,
        'maxAgents': maxAgents,
        'maxRounds': maxRounds,
        'mode': mode.wireName,
      };
}

class CollaborationRunSnapshot {
  const CollaborationRunSnapshot({
    required this.id,
    required this.taskId,
    required this.mode,
    required this.status,
    required this.budgetTokens,
    required this.consumedTokens,
    required this.maxAgents,
    required this.maxRounds,
    required this.currentRound,
    required this.createdAt,
    required this.updatedAt,
    this.plan,
    this.result,
    this.error,
  });

  final String id;
  final String taskId;
  final CollaborationMode mode;
  final CollaborationStatus status;
  final int budgetTokens;
  final int consumedTokens;
  final int maxAgents;
  final int maxRounds;
  final int currentRound;
  final DateTime createdAt;
  final DateTime updatedAt;
  final CollaborationPlan? plan;
  final CollaborationResult? result;
  final String? error;
}

class CollaborationAgentOutput {
  const CollaborationAgentOutput({
    required this.role,
    required this.text,
    required this.inputTokens,
    required this.outputTokens,
    required this.cachedTokens,
    this.failed = false,
    this.error,
  });

  final CollaborationAgentRole role;
  final String text;
  final int inputTokens;
  final int outputTokens;
  final int cachedTokens;
  final bool failed;
  final String? error;

  int get totalTokens => inputTokens + outputTokens;
}

class CollaborationFinding {
  const CollaborationFinding({
    required this.title,
    required this.detail,
    this.severity = 'info',
    this.evidence = const [],
    this.recommendation,
  });

  final String title;
  final String detail;
  final String severity;
  final List<String> evidence;
  final String? recommendation;

  Map<String, dynamic> toJson() => {
        'title': title,
        'detail': detail,
        'severity': severity,
        'evidence': evidence,
        if (recommendation != null) 'recommendation': recommendation,
      };

  factory CollaborationFinding.fromJson(Map<String, dynamic> json) =>
      CollaborationFinding(
        title: json['title']?.toString() ?? '未命名发现',
        detail: json['detail']?.toString() ?? '',
        severity: json['severity']?.toString() ?? 'info',
        evidence: _stringList(json['evidence']),
        recommendation: json['recommendation']?.toString(),
      );
}

class CollaborationResult {
  const CollaborationResult({
    required this.summary,
    required this.findings,
    required this.actions,
    required this.evidence,
    required this.nextSteps,
    required this.disagreements,
    this.risks = const [],
    required this.confidence,
    this.rawSynthesis,
    this.votes = const {},
    this.decision,
  });

  final String summary;
  final List<CollaborationFinding> findings;
  final List<String> actions;
  final List<String> evidence;
  final List<String> nextSteps;
  final List<String> disagreements;

  /// 子 Agent 明确标记的风险与证据缺口，和 findings 分开显示。
  final List<String> risks;
  final double confidence;
  final String? rawSynthesis;
  final Map<String, int> votes;
  final String? decision;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'findings': findings.map((item) => item.toJson()).toList(),
        'actions': actions,
        'evidence': evidence,
        'nextSteps': nextSteps,
        'disagreements': disagreements,
        'risks': risks,
        'confidence': confidence,
        if (rawSynthesis != null) 'rawSynthesis': rawSynthesis,
        'votes': votes,
        if (decision != null) 'decision': decision,
      };

  String encode() => jsonEncode(toJson());

  factory CollaborationResult.fromJson(Map<String, dynamic> json) {
    final rawFindings = json['findings'] as List? ?? const [];
    return CollaborationResult(
      summary: json['summary']?.toString() ?? '',
      findings: rawFindings
          .whereType<Map>()
          .map((item) =>
              CollaborationFinding.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      actions: _stringList(json['actions']),
      evidence: _stringList(json['evidence']),
      nextSteps: _stringList(json['nextSteps']),
      disagreements: _stringList(json['disagreements']),
      risks: _stringList(json['risks']),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      rawSynthesis: json['rawSynthesis']?.toString(),
      votes: _intMap(json['votes']),
      decision: json['decision']?.toString(),
    );
  }

  static CollaborationResult decode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const CollaborationResult(
        summary: '',
        findings: [],
        actions: [],
        evidence: [],
        nextSteps: [],
        disagreements: [],
        risks: [],
        confidence: 0,
      );
    }
    try {
      final decoded = jsonDecode(value);
      return CollaborationResult.fromJson(
          decoded is Map ? Map<String, dynamic>.from(decoded) : const {});
    } catch (_) {
      return CollaborationResult(
        summary: value,
        findings: const [],
        actions: const [],
        evidence: const [],
        nextSteps: const [],
        disagreements: const [],
        risks: const [],
        confidence: 0,
        rawSynthesis: value,
      );
    }
  }
}

sealed class CollaborationEvent {
  const CollaborationEvent(this.runId);
  final String runId;
}

class CollaborationRunEvent extends CollaborationEvent {
  const CollaborationRunEvent(super.runId, this.run);
  final CollaborationRunSnapshot run;
}

class CollaborationAgentEvent extends CollaborationEvent {
  const CollaborationAgentEvent(
      super.runId, this.agentRunId, this.role, this.status, this.summary);
  final String agentRunId;
  final CollaborationAgentRole role;
  final String status;
  final String? summary;
}

class CollaborationArtifactEvent extends CollaborationEvent {
  const CollaborationArtifactEvent(super.runId, this.artifactId,
      this.agentRunId, this.type, this.payloadJson);
  final String artifactId;
  final String agentRunId;
  final String type;
  final String payloadJson;
}

class CollaborationMessageEvent extends CollaborationEvent {
  const CollaborationMessageEvent(super.runId, this.round, this.content);
  final int round;
  final String content;
}

class CollaborationErrorEvent extends CollaborationEvent {
  const CollaborationErrorEvent(super.runId, this.message);
  final String message;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}

Map<String, int> _intMap(dynamic value) {
  if (value is! Map) return const {};
  return Map<String, int>.fromEntries(value.entries
      .where((entry) => entry.key != null && entry.value is num)
      .map((entry) =>
          MapEntry(entry.key.toString(), (entry.value as num).toInt())));
}
