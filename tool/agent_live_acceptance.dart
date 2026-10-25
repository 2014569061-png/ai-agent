// Native entry point: reads the existing provider through platform plugins.
// All edits, processes and run records belong to a temporary fixture/database.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_agent/application/agent_executor.dart';
import 'package:mobile_agent/application/background_execution_gateway.dart';
import 'package:mobile_agent/application/development_loop_finalizer.dart';
import 'package:mobile_agent/application/development_run_completion.dart';
import 'package:mobile_agent/application/development_verification.dart';
import 'package:mobile_agent/application/execution_lease_service.dart';
import 'package:mobile_agent/application/headless_executor.dart';
import 'package:mobile_agent/application/project_kind.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/application/workspace_snapshot.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/model_route.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';
import 'package:path/path.dart' as p;

class FixtureVerification extends DevelopmentVerificationService {
  @override
  Future<DevelopmentVerificationPlan> planFor(String workspacePath,
          {bool includeBuild = true}) async =>
      const DevelopmentVerificationPlan(
          project: ProjectKindDetection(
              kind: ProjectKind.node, confidence: 1, signals: []),
          steps: [
            VerificationStep(
                id: 'test',
                title: '真实 Node 断言',
                command: 'node verify.js',
                timeout: Duration(seconds: 15))
          ]);
}

Future<Map<String, dynamic>> runAgentAcceptance(
    {required ProviderConfig config, ModelRouter? router}) async {
  final fixture =
      await Directory.systemTemp.createTemp('nexus-agent-acceptance-');
  final db = AppDatabase(NativeDatabase.memory());
  final cancellation = AgentCancellationToken();
  final deadline = Timer(const Duration(minutes: 4), cancellation.cancel);
  WorkspaceLeaseGuard? guard;
  DevelopmentRunCompletion? completion;
  final tasks = TaskService();
  try {
    await File(p.join(fixture.path, 'value.js'))
        .writeAsString('exports.value = () => 2;\n');
    await File(p.join(fixture.path, 'verify.js'))
        .writeAsString("const assert = require('node:assert/strict');\n"
            "const {value} = require('./value');\n"
            "assert.equal(value(), 4, 'value() must equal 4');\n"
            "console.log('ACCEPTANCE PASSED');\n");
    await File(p.join(fixture.path, 'NEXUS.md'))
        .writeAsString('验收规则：只允许修改 value.js。verify.js 是验收标准，不得修改。');
    final snapshot =
        await const WorkspaceSnapshotService().capture(fixture.path);
    final task = await tasks.create(
        db: db,
        conversationId: 'acceptance',
        type: 'development:bug_fix',
        requestJson: '{}',
        metadata: {
          'prompt': '故障恢复验收：最终 value() 必须返回 4，禁止修改 verify.js。',
          'taskType': 'bug_fix',
          'workspacePath': fixture.path,
        });
    await tasks.updateProgress(db, task.id,
        phase: 'running', extra: {'workspaceSnapshot': snapshot.toJson()});
    guard = await WorkspaceLeaseGuard.open(
        db: db,
        workspacePath: fixture.path,
        taskId: task.id,
        runId: 'acceptance',
        onLost: cancellation.cancel);
    final gateway = BackgroundExecutionGateway();
    const allow = [
      'read_file',
      'list_directory',
      'search_files',
      'repo_map',
      'edit_file',
      'apply_patch'
    ];
    final terminal = TerminalCommandService(
        workspacePath: fixture.path,
        jobLogDirectory: Directory(p.join(fixture.path, '.nexus', 'logs')));
    var repairs = 0;
    var faultInjected = false;
    completion = DevelopmentRunCompletion(
      db: db,
      taskId: task.id,
      runId: 'acceptance',
      workspacePath: fixture.path,
      terminalFactory: () async => terminal,
      repairEnabled: () async => true,
      canContinue: () => !cancellation.isCancelled && guard!.active,
      finalizer: DevelopmentLoopFinalizer(verification: FixtureVerification()),
    );
    const prompt = '这是故障注入阶段。先读取 value.js，然后把返回值 2 改成 3。'
        '这一阶段完成后立即结束，不要修到最终值 4，不要运行验证。';
    final run = await gateway.run(
        db: db,
        config: config,
        prompt: prompt,
        taskId: task.id,
        runId: 'acceptance',
        workspacePath: fixture.path,
        leaseGuard: guard,
        cancellationToken: cancellation,
        execute: () => HeadlessExecutor.runDetailed(
            db: db,
            config: config,
            prompt: prompt,
            systemPrompt: '你执行一个临时工作区中的故障恢复验收。'
                '只允许修改 value.js，其他文件只读。必须先 read_file 后修改。'
                '只执行当前阶段的要求，验证由宿主运行。',
            workspacePath: fixture.path,
            allowedToolNames: allow,
            taskId: task.id,
            runId: 'acceptance',
            modelRouter: router,
            maxSteps: 8,
            maxTokens: 1024,
            totalTokenBudget: 48000,
            cancellationToken: cancellation,
            approveTool: (_, __, ___) async => ToolApproval.allowOnce,
            beforeFinish: (context) async {
              if (!faultInjected) {
                if (!(await File(p.join(fixture.path, 'value.js'))
                        .readAsString())
                    .contains('=> 3')) {
                  throw StateError(
                      'Fault injection did not produce the expected value');
                }
                faultInjected = true;
              }
              final continuation = await completion!(context);
              if (continuation != null) repairs++;
              return continuation;
            }));
    final result = completion.latest;
    if (!run.succeeded || !faultInjected || result == null) {
      return {
        'status': 'failed',
        'stage': 'execution',
        'runStatus': run.status.name,
        'failureKind': run.failureKind ?? 'verification_incomplete',
        'model': config.model,
      };
    }
    final progress = await tasks.progress(db, task.id);
    final attempts = progress['verificationRepairAttempts'] as List? ?? [];
    final unchangedTest = await const WorkspaceSnapshotService()
            .currentHash(fixture.path, 'verify.js') ==
        snapshot.files['verify.js']!.hash;
    return {
      'status': result.verified && repairs == 1 && unchangedTest
          ? 'passed'
          : 'failed',
      'model': config.model,
      'repairs': repairs,
      'verified': result.verified,
      'testUnchanged': unchangedTest,
      'attemptStatuses': [for (final a in attempts) a['status']],
      'checks': [
        for (final s in result.verification?.plan.steps ?? <VerificationStep>[])
          {'id': s.id, 'status': s.status.name, 'exitCode': s.exitCode}
      ],
      'leaseHeldThroughFinalization':
          (await db.findExecutionLease(guard.lease.resourceKey))?.ownerToken ==
              guard.lease.ownerToken
    };
  } finally {
    deadline.cancel();
    cancellation.cancel();
    await completion?.drain();
    await guard?.close();
    await db.close();
    await fixture.delete(recursive: true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> report;
  try {
    final config = await ProviderConfigStore().load();
    report = config.isConfigured
        ? await runAgentAcceptance(config: config)
        : {'status': 'blocked', 'reason': '未配置可用的真实模型，未退回演示模型'};
  } catch (error) {
    // Exception strings may contain URLs or credentials; retain only the type.
    report = {'status': 'failed', 'errorType': error.runtimeType.toString()};
  }
  final target = Platform.environment['NEXUS_ACCEPTANCE_REPORT'] ??
      p.join(Directory.current.path, 'build', 'agent-live-acceptance.json');
  final file = File(target);
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  exit(report['status'] == 'passed'
      ? 0
      : report['status'] == 'blocked'
          ? 2
          : 1);
}
