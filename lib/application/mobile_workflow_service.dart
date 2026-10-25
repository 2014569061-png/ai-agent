import 'dart:convert';
import 'package:drift/drift.dart';

import '../domain/mobile_workflow.dart';
import '../domain/reminder.dart';
import '../infrastructure/notifications/notification_service.dart';
import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import 'reminder_service.dart';
import 'knowledge_service.dart';

class MobileWorkflowService {
  MobileWorkflowService(this._db,
      {this.reminderDelivery = const NotificationReminderDelivery()});

  final AppDatabase _db;
  final ReminderDelivery? reminderDelivery;
  bool _ready = false;

  Future<void> ensureReady() async {
    if (_ready) return;
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS nexus_mobile_workflows (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        input_schema_json TEXT NOT NULL DEFAULT '[]',
        steps_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS nexus_mobile_workflow_runs (
        id TEXT PRIMARY KEY NOT NULL,
        workflow_id TEXT NOT NULL,
        workflow_version INTEGER NOT NULL,
        dry_run INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        inputs_json TEXT NOT NULL DEFAULT '{}',
        traces_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL
      )
    ''');
    _ready = true;
    await _seedDefaultsIfEmpty();
  }

  Future<void> _seedDefaultsIfEmpty() async {
    final existing = await _db
        .customSelect('SELECT COUNT(*) AS c FROM nexus_mobile_workflows')
        .getSingle();
    if ((existing.read<int>('c')) > 0) return;
    final now = DateTime.now().toUtc();
    await saveDefinition(
      WorkflowDefinition(
        id: 'wf-daily-brief',
        name: '每日事项与提醒归档流',
        description: '校验输入事项 -> 结构化提炼 -> 创建本地提醒 -> 输出归档摘要',
        version: 1,
        inputSchema: const <String>['topic'],
        steps: const <WorkflowStepSpec>[
          WorkflowStepSpec(
            id: 's1',
            title: '校验输入主题',
            kind: WorkflowStepKind.validateInput,
          ),
          WorkflowStepSpec(
            id: 's2',
            title: '结构化要点提炼',
            kind: WorkflowStepKind.transformText,
          ),
          WorkflowStepSpec(
            id: 's3',
            title: '写入提醒事项（需确认）',
            kind: WorkflowStepKind.createReminder,
            requiresConfirmation: true,
          ),
          WorkflowStepSpec(
            id: 's4',
            title: '生成执行摘要',
            kind: WorkflowStepKind.emitSummary,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> saveDefinition(WorkflowDefinition definition) async {
    if (definition.id.trim().isEmpty ||
        definition.name.trim().isEmpty ||
        definition.version < 1 ||
        definition.steps.isEmpty ||
        definition.steps.map((s) => s.id).toSet().length !=
            definition.steps.length ||
        definition.steps.any((s) => s.id.trim().isEmpty) ||
        definition.inputSchema.any((s) => s.trim().isEmpty)) {
      throw const FormatException('工作流名称、版本、步骤与输入定义不合法');
    }
    await ensureReady();
    final previous = await findDefinition(definition.id);
    if (previous != null && definition.version <= previous.version) {
      throw const FormatException('修改工作流必须递增版本');
    }
    await _db.customStatement(
      '''
      INSERT OR REPLACE INTO nexus_mobile_workflows (
        id, name, description, version, input_schema_json, steps_json,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        definition.id,
        definition.name.trim(),
        definition.description.trim(),
        definition.version,
        jsonEncode(definition.inputSchema),
        jsonEncode(definition.steps.map((s) => s.toJson()).toList()),
        definition.createdAt.toUtc().millisecondsSinceEpoch,
        definition.updatedAt.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  Future<List<WorkflowDefinition>> listDefinitions() async {
    await ensureReady();
    final rows = await _db
        .customSelect(
            'SELECT * FROM nexus_mobile_workflows ORDER BY updated_at DESC')
        .get();
    return rows.map(_definitionFromRow).toList(growable: false);
  }

  Future<WorkflowDefinition?> findDefinition(String id) async {
    await ensureReady();
    final rows = await _db.customSelect(
      'SELECT * FROM nexus_mobile_workflows WHERE id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).get();
    if (rows.isEmpty) return null;
    return _definitionFromRow(rows.first);
  }

  Future<WorkflowRunRecord> runWorkflow({
    required String workflowId,
    required Map<String, String> inputs,
    bool dryRun = false,
    bool highRiskConfirmed = false,
    int? expectedVersion,
    DateTime? now,
  }) async {
    await ensureReady();
    final definition = await findDefinition(workflowId);
    if (definition == null) {
      throw StateError('工作流不存在：$workflowId');
    }
    if (expectedVersion != null && definition.version != expectedVersion) {
      throw StateError('工作流已更新，请重新核对步骤并确认');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final traces = <WorkflowStepTrace>[];
    var overallStatus = 'succeeded';

    for (final requiredKey in definition.inputSchema) {
      final val = inputs[requiredKey]?.trim() ?? '';
      if (val.isEmpty) {
        overallStatus = 'failed';
        traces.add(
          WorkflowStepTrace(
            stepId: 'input:$requiredKey',
            title: '输入参数检查 ($requiredKey)',
            status: 'failed',
            outputSummary: '缺少必填输入参数：$requiredKey',
          ),
        );
        break;
      }
    }

    if (overallStatus == 'succeeded') {
      final topic = inputs['topic']?.trim() ??
          inputs.values
              .firstWhere((v) => v.trim().isNotEmpty, orElse: () => '默认主题');
      for (final step in definition.steps) {
        // Side-effecting kinds require consent even if an imported definition
        // omits its presentation-only confirmation flag.
        if ((step.requiresConfirmation ||
                step.kind == WorkflowStepKind.createReminder) &&
            !dryRun &&
            !highRiskConfirmed) {
          overallStatus = 'blocked_confirmation';
          traces.add(
            WorkflowStepTrace(
              stepId: step.id,
              title: step.title,
              status: 'blocked_confirmation',
              outputSummary: '步骤含外部或写入副作用，未获得用户明确确认，已中止执行。',
            ),
          );
          break;
        }
        try {
          switch (step.kind) {
            case WorkflowStepKind.validateInput:
              traces.add(
                WorkflowStepTrace(
                  stepId: step.id,
                  title: step.title,
                  status: 'succeeded',
                  outputSummary: '输入校验通过（${inputs.length} 项参数）',
                ),
              );
            case WorkflowStepKind.transformText:
              traces.add(
                WorkflowStepTrace(
                  stepId: step.id,
                  title: step.title,
                  status: 'succeeded',
                  outputSummary: '已提炼结构化主题：「$topic」',
                ),
              );
            case WorkflowStepKind.queryKnowledge:
              final evidence = await KnowledgeService().buildInjectionBlock(
                _db,
                topic,
                projectId: step.config['projectId'] as String?,
              );
              traces.add(
                WorkflowStepTrace(
                  stepId: step.id,
                  title: step.title,
                  status: 'succeeded',
                  outputSummary: evidence.isEmpty
                      ? '未找到可用知识片段（「$topic」）；请检查知识库开关与资料范围'
                      : evidence,
                ),
              );
            case WorkflowStepKind.createReminder:
              if (dryRun) {
                traces.add(
                  WorkflowStepTrace(
                    stepId: step.id,
                    title: step.title,
                    status: 'simulated',
                    outputSummary: '试跑模式：模拟创建提醒「$topic」，未写入真实提醒表',
                  ),
                );
              } else {
                final rem =
                    await ReminderService(_db, delivery: reminderDelivery)
                        .create(
                  title: '工作流提醒：$topic',
                  scheduledAtUtc: clock.add(const Duration(hours: 2)),
                  now: clock,
                );
                traces.add(
                  WorkflowStepTrace(
                    stepId: step.id,
                    title: step.title,
                    status: 'succeeded',
                    outputSummary: '已写入提醒事项（ID: ${rem.id}）',
                  ),
                );
              }
            case WorkflowStepKind.emitSummary:
              traces.add(
                WorkflowStepTrace(
                  stepId: step.id,
                  title: step.title,
                  status: 'succeeded',
                  outputSummary:
                      '${dryRun ? "[试跑]" : "[正式]"} 工作流「${definition.name}」执行完毕',
                ),
              );
          }
        } catch (error) {
          overallStatus = 'failed';
          traces.add(WorkflowStepTrace(
              stepId: step.id,
              title: step.title,
              status: 'failed',
              outputSummary: '步骤执行失败（${error.runtimeType}），已停止后续步骤'));
          break;
        }
      }
    }

    final record = WorkflowRunRecord(
      id: UniqueId.generate('wfr', now: clock),
      workflowId: definition.id,
      workflowVersion: definition.version,
      dryRun: dryRun,
      status: overallStatus,
      inputs: Map<String, String>.from(inputs),
      stepTraces: traces,
      createdAt: clock,
    );
    await _db.customStatement(
      '''
      INSERT INTO nexus_mobile_workflow_runs (
        id, workflow_id, workflow_version, dry_run, status,
        inputs_json, traces_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        record.id,
        record.workflowId,
        record.workflowVersion,
        record.dryRun ? 1 : 0,
        record.status,
        jsonEncode(record.inputs),
        jsonEncode(record.stepTraces.map((t) => t.toJson()).toList()),
        record.createdAt.millisecondsSinceEpoch,
      ],
    );
    return record;
  }

  Future<List<WorkflowRunRecord>> listRuns({String? workflowId}) async {
    await ensureReady();
    final rows = workflowId == null
        ? await _db
            .customSelect(
                'SELECT * FROM nexus_mobile_workflow_runs ORDER BY created_at DESC LIMIT 30')
            .get()
        : await _db.customSelect(
            'SELECT * FROM nexus_mobile_workflow_runs WHERE workflow_id = ? ORDER BY created_at DESC LIMIT 30',
            variables: <Variable<Object>>[Variable<String>(workflowId)],
          ).get();
    return rows.map((row) {
      final rawInputs = jsonDecode(row.read<String>('inputs_json'));
      final rawTraces = jsonDecode(row.read<String>('traces_json'));
      return WorkflowRunRecord(
        id: row.read<String>('id'),
        workflowId: row.read<String>('workflow_id'),
        workflowVersion: row.read<int>('workflow_version'),
        dryRun: row.read<int>('dry_run') != 0,
        status: row.read<String>('status'),
        inputs: rawInputs is Map
            ? rawInputs.map((k, v) => MapEntry(k.toString(), v.toString()))
            : const <String, String>{},
        stepTraces: rawTraces is List
            ? rawTraces
                .whereType<Map>()
                .map((m) =>
                    WorkflowStepTrace.fromJson(Map<String, dynamic>.from(m)))
                .toList(growable: false)
            : const <WorkflowStepTrace>[],
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('created_at'),
          isUtc: true,
        ),
      );
    }).toList(growable: false);
  }

  WorkflowDefinition _definitionFromRow(QueryRow row) {
    final rawSchema = jsonDecode(row.read<String>('input_schema_json'));
    final rawSteps = jsonDecode(row.read<String>('steps_json'));
    return WorkflowDefinition(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      description: row.read<String>('description'),
      version: row.read<int>('version'),
      inputSchema: rawSchema is List
          ? rawSchema.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      steps: rawSteps is List
          ? rawSteps
              .whereType<Map>()
              .map((m) =>
                  WorkflowStepSpec.fromJson(Map<String, dynamic>.from(m)))
              .toList(growable: false)
          : const <WorkflowStepSpec>[],
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
    );
  }
}
