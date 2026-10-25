enum WorkflowStepKind {
  validateInput('validate_input', '输入校验'),
  transformText('transform_text', '结构化转换'),
  queryKnowledge('query_knowledge', '检索本地知识'),
  createReminder('create_reminder', '创建提醒事项'),
  emitSummary('emit_summary', '生成归档摘要');

  const WorkflowStepKind(this.wireName, this.label);
  final String wireName;
  final String label;

  static WorkflowStepKind tryParse(String? raw) {
    for (final value in WorkflowStepKind.values) {
      if (value.wireName == raw) return value;
    }
    throw FormatException('不支持的工作流步骤类型：$raw');
  }
}

class WorkflowStepSpec {
  const WorkflowStepSpec({
    required this.id,
    required this.title,
    required this.kind,
    this.config = const <String, dynamic>{},
    this.requiresConfirmation = false,
  });

  final String id;
  final String title;
  final WorkflowStepKind kind;
  final Map<String, dynamic> config;
  final bool requiresConfirmation;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'kind': kind.wireName,
        'config': config,
        'requiresConfirmation': requiresConfirmation,
      };

  factory WorkflowStepSpec.fromJson(Map<String, dynamic> json) =>
      WorkflowStepSpec(
        id: json['id']?.toString() ?? 'step',
        title: json['title']?.toString() ?? '步骤',
        kind: WorkflowStepKind.tryParse(json['kind']?.toString()),
        config: json['config'] is Map
            ? Map<String, dynamic>.from(json['config'] as Map)
            : const <String, dynamic>{},
        requiresConfirmation: json['requiresConfirmation'] == true,
      );
}

class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.inputSchema,
    required this.steps,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final int version;
  final List<String> inputSchema;
  final List<WorkflowStepSpec> steps;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class WorkflowStepTrace {
  const WorkflowStepTrace({
    required this.stepId,
    required this.title,
    required this.status,
    required this.outputSummary,
  });

  final String stepId;
  final String title;
  final String status;
  final String outputSummary;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'stepId': stepId,
        'title': title,
        'status': status,
        'outputSummary': outputSummary,
      };

  factory WorkflowStepTrace.fromJson(Map<String, dynamic> json) =>
      WorkflowStepTrace(
        stepId: json['stepId']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        status: json['status']?.toString() ?? 'succeeded',
        outputSummary: json['outputSummary']?.toString() ?? '',
      );
}

class WorkflowRunRecord {
  const WorkflowRunRecord({
    required this.id,
    required this.workflowId,
    required this.workflowVersion,
    required this.dryRun,
    required this.status,
    required this.inputs,
    required this.stepTraces,
    required this.createdAt,
  });

  final String id;
  final String workflowId;
  final int workflowVersion;
  final bool dryRun;
  final String status;
  final Map<String, String> inputs;
  final List<WorkflowStepTrace> stepTraces;
  final DateTime createdAt;
}
