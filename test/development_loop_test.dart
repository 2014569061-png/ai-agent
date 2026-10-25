import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:mobile_agent/application/change_review.dart';
import 'package:mobile_agent/application/development_loop_finalizer.dart';
import 'package:mobile_agent/application/development_verification.dart';
import 'package:mobile_agent/application/development_workflow.dart';
import 'package:mobile_agent/application/network_access_policy.dart';
import 'package:mobile_agent/application/run_event_tracker.dart';
import 'package:mobile_agent/application/project_kind.dart';
import 'package:mobile_agent/application/project_kind_detector.dart';
import 'package:mobile_agent/application/task_service.dart';
import 'package:mobile_agent/application/task_template_service.dart';
import 'package:mobile_agent/application/workspace_snapshot.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/domain/collaboration_models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/plugins/plugin_store.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';

class _ScriptedRuntime implements LinuxRuntimeAdapter {
  _ScriptedRuntime(this.results);

  final List<CommandResult> results;
  final commands = <String>[];

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => false;

  @override
  bool get isRunning => false;

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.hostProcess;

  @override
  Future<LinuxRuntimeInfo> inspect() async => const LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.hostProcess,
        label: 'fake',
        available: true,
        detail: '',
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    commands.add(request.commandLine);
    if (results.isEmpty) {
      return const CommandResult(
          output: 'missing scripted result', exitCode: 1);
    }
    return results.removeAt(0);
  }

  @override
  void stop() {}
}

void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('nexus-dev-loop-');
  });

  tearDown(() async {
    if (workspace.existsSync()) {
      await workspace.delete(recursive: true);
    }
  });

  test('detects Flutter projects and plans analyze/test/build', () async {
    await File('${workspace.path}/pubspec.yaml').writeAsString('''
name: demo
environment:
  sdk: ^3.5.0
flutter:
  uses-material-design: true
''');
    final detection = await const ProjectKindDetector().detect(workspace.path);
    expect(detection.kind, ProjectKind.flutter);
    expect(detection.packageName, 'demo');

    final plan = DevelopmentVerificationService().planFromDetection(detection);
    expect(plan.steps.map((step) => step.id),
        ['analyze', 'test', 'build', 'artifact']);
    final fastPlan = DevelopmentVerificationService()
        .planFromDetection(detection, includeBuild: false);
    expect(fastPlan.steps.map((step) => step.id), ['analyze', 'test']);
    expect(plan.primaryArtifactPath,
        'build/app/outputs/flutter-apk/app-release.apk');
  });

  test('detects Node scripts from package.json', () async {
    await File('${workspace.path}/package.json').writeAsString('''
{
  "name": "web-app",
  "scripts": {"test": "vitest", "build": "vite build"}
}
''');
    final detection = await const ProjectKindDetector().detect(workspace.path);
    expect(detection.kind, ProjectKind.node);
    expect(detection.testCommand, 'npm run test');
    expect(detection.buildCommand, 'npm run build');
  });

  test(
      'artifact inspector accepts ZIP-headed APKs but keeps the package unknown',
      () async {
    const inspector = ArtifactInspector();
    final missing = await inspector.inspect(
      workspacePath: workspace.path,
      relativePath: 'build/app/outputs/flutter-apk/app-release.apk',
    );
    expect(missing.exists, isFalse);

    final apk =
        File('${workspace.path}/build/app/outputs/flutter-apk/app-release.apk');
    await apk.create(recursive: true);
    await apk.writeAsBytes([0x50, 0x4B, 0x03, 0x04, ...List.filled(2048, 1)]);
    final found = await inspector.inspect(
      workspacePath: workspace.path,
      relativePath: 'build/app/outputs/flutter-apk/app-release.apk',
      expectedPackageName: 'com.example.demo',
    );
    expect(found.exists, isTrue);
    expect(found.sha256, isNotEmpty);
    // 只校验了 ZIP 文件头，没有解析 AndroidManifest：包名必须保持未知，
    // 期望值只能出现在 notes 里，否则下游会把一个未验证的猜测当成事实。
    expect(found.packageName, isNull);
    expect(
        found.notes.any((note) => note.contains('com.example.demo')), isTrue);
  });

  test('verification runner stops on failure and retries a single step',
      () async {
    await File('${workspace.path}/pubspec.yaml').writeAsString('''
name: demo
flutter:
  uses-material-design: true
''');
    final runtime = _ScriptedRuntime([
      const CommandResult(output: 'analyze ok', exitCode: 0),
      const CommandResult(output: 'test failed', exitCode: 1),
      const CommandResult(output: 'test ok', exitCode: 0),
      const CommandResult(output: 'build ok', exitCode: 0),
    ]);
    final service = TerminalCommandService(
      workspacePath: workspace.path,
      runtime: runtime,
    );
    final verification = DevelopmentVerificationService();
    final first = await verification.run(
      service: service,
      workspacePath: workspace.path,
    );
    expect(first.success, isFalse);
    expect(first.plan.steps[1].status, VerificationStepStatus.failed);
    expect(runtime.commands, ['flutter analyze', 'flutter test']);

    await File(
            '${workspace.path}/build/app/outputs/flutter-apk/app-release.apk')
        .create(recursive: true)
        .then((file) => file
            .writeAsBytes([0x50, 0x4B, 0x03, 0x04, ...List.filled(2048, 1)]));

    final retried = await verification.run(
      service: service,
      workspacePath: workspace.path,
      plan: first.plan,
      retryStepId: 'test',
    );
    expect(retried.plan.steps[1].status, VerificationStepStatus.passed);
    expect(runtime.commands.last, 'flutter build apk --release');
  });

  test('task templates support implement-and-verify instead of advice only',
      () {
    final service = TaskTemplateService();
    final template = service.forTask(const DevelopmentTaskInput(
      taskId: 't1',
      prompt: '加一个按钮',
      taskType: 'implement_and_verify',
    ));
    expect(template.implementsChanges, isTrue);
    expect(template.allowedTools, contains('terminal'));
    expect(template.allowedTools, contains('edit_file'));
    final prompt = service.promptBlock(
      taskType: 'bug_fix',
      project: const ProjectKindDetection(
        kind: ProjectKind.flutter,
        confidence: 1,
        signals: [],
        testCommand: 'flutter test',
        buildCommand: 'flutter build apk --release',
      ),
    );
    expect(prompt, contains('修复后必须运行'));
    expect(prompt, contains('Flutter'));
  });

  test('change review marks files after verification', () {
    const service = ChangeReviewService();
    final review = service.fromMetadata([
      {
        'path': 'lib/main.dart',
        'operation': 'edit',
        'linesAdded': 3,
        'linesRemoved': 1,
        'diff': '--- a/lib/main.dart\n+++ b/lib/main.dart',
      },
      {
        'path': 'README.md',
        'operation': 'read',
      },
    ]);
    expect(review.files, hasLength(1));
    expect(review.linesAdded, 3);
    final marked = service.withVerification(
      review,
      const DevelopmentVerificationResult(
        plan: DevelopmentVerificationPlan(
          project: ProjectKindDetection(
              kind: ProjectKind.flutter, confidence: 1, signals: []),
          steps: [
            VerificationStep(
              id: 'test',
              title: '测试',
              command: 'flutter test',
              status: VerificationStepStatus.passed,
            ),
          ],
        ),
        success: true,
      ),
    );
    expect(marked.mark, ChangeVerificationMark.passed);
    expect(marked.files.single.mark, ChangeVerificationMark.passed);
  });

  test('network policy blocks loopback and plugin import requires valid URL',
      () {
    const policy = NetworkAccessPolicy();
    expect(policy.inspect('https://example.com/v1').allowed, isTrue);
    expect(policy.inspect('http://127.0.0.1/secret').allowed, isFalse);
    expect(policy.inspect('http://192.168.1.8/x').allowed, isFalse);

    final store = PluginStore();
    expect(
      store.manifestError(
          '{"name":"bad","kind":"tool","tools":[{"name":"x","request":{"url":"http://localhost/x"}}]}'),
      contains('本机'),
    );
    expect(
      store.validateManifest(
          '{"name":"ok","kind":"tool","version":"1.0.0","tools":[{"name":"search","request":{"url":"https://example.com/search"}}]}'),
      isTrue,
    );
  });

  test('workbench templates cover Flutter and other project kinds', () {
    expect(DevelopmentWorkflowTemplates.forKind(ProjectKind.flutter).id,
        'flutter-verify-apk');
    for (final workflow in DevelopmentWorkflowTemplates.all) {
      expect(workflow.steps, isNotEmpty);
      expect(workflow.steps.every((step) => step.title?.isNotEmpty == true),
          isTrue);
    }
  });

  test('static web verification reports a readable artifact result', () async {
    await File('${workspace.path}/index.html')
        .writeAsString('<!doctype html><title>ok</title>');
    final result = await DevelopmentWorkflowRunner(
      TerminalCommandService(
        workspacePath: workspace.path,
        runtime: _ScriptedRuntime(const []),
      ),
    ).run(DevelopmentWorkflowTemplates.staticWeb, workspace.path);

    expect(result.success, isTrue);
    expect(result.plan?.steps.single.title, '检查网页入口');
    expect(result.steps.single.message, '产物检查通过：index.html');
    expect(result.steps.single.message, isNot(startsWith('{')));
  });

  test('plugin HTTP tool rejects private destinations at execution time',
      () async {
    final tool = DeclarativeTool.fromManifest({
      'name': 'private_call',
      'request': {'url': 'http://10.0.0.8/internal', 'method': 'GET'},
    });
    final result = await tool.execute(const {});
    expect(result.ok, isFalse);
    expect(result.code, ToolCodes.notConfigured);
  });

  test('workspace snapshot review only includes files changed this task',
      () async {
    await File('${workspace.path}/keep.dart').writeAsString('unchanged\n');
    await File('${workspace.path}/old.dart').writeAsString('before\n');
    final snapshot =
        await const WorkspaceSnapshotService().capture(workspace.path);
    await File('${workspace.path}/old.dart').writeAsString('after\n');
    await File('${workspace.path}/new.dart').writeAsString('created\n');
    await File('${workspace.path}/keep.dart').writeAsString('unchanged\n');

    final review = await const WorkspaceSnapshotService().reviewFromSnapshot(
      workspacePath: workspace.path,
      snapshot: snapshot,
    );
    expect(review.files.map((file) => file.path),
        containsAll(['old.dart', 'new.dart']));
    expect(review.files.map((file) => file.path), isNot(contains('keep.dart')));
    final edited = review.files.firstWhere((file) => file.path == 'old.dart');
    expect(edited.diff, isEmpty);
    expect(edited.linesAdded, 0);
    expect(edited.linesRemoved, 0);
  });

  test('invalid APK is not treated as a signed passing artifact', () async {
    final apk =
        File('${workspace.path}/build/app/outputs/flutter-apk/app-release.apk');
    await apk.create(recursive: true);
    await apk.writeAsString('not an apk' * 200);
    final found = await const ArtifactInspector().inspect(
      workspacePath: workspace.path,
      relativePath: 'build/app/outputs/flutter-apk/app-release.apk',
      expectedPackageName: 'com.example.demo',
    );
    expect(found.exists, isTrue);
    expect(found.isValid, isFalse);
    expect(found.signed, isNull);
    expect(found.packageName, isNull);
  });

  test('empty inspect-only plans are not reported as passed', () async {
    final result = await DevelopmentVerificationService().run(
      service: TerminalCommandService(
        workspacePath: workspace.path,
        runtime: _ScriptedRuntime(const []),
      ),
      workspacePath: workspace.path,
    );
    expect(result.success, isFalse);
    expect(
        result.plan.steps
            .any((step) => step.status == VerificationStepStatus.passed),
        isFalse);
  });

  test('selected Python workflow is executed instead of detected Node commands',
      () async {
    await File('${workspace.path}/package.json')
        .writeAsString('{"name":"web","scripts":{"test":"vitest"}}');
    final runtime = _ScriptedRuntime([
      const CommandResult(output: 'pytest ok', exitCode: 0),
    ]);
    final result = await DevelopmentWorkflowRunner(
      TerminalCommandService(
        workspacePath: workspace.path,
        runtime: runtime,
      ),
    ).run(DevelopmentWorkflowTemplates.pythonTest, workspace.path);
    expect(runtime.commands, ['python -m pytest']);
    expect(result.success, isTrue);
  });

  test('IPv6 unique-local addresses are blocked', () {
    const policy = NetworkAccessPolicy();
    expect(policy.inspect('http://[fd00::1234]/private').allowed, isFalse);
    expect(policy.inspect('http://[::ffff:192.168.1.8]/x').allowed, isFalse);
  });

  test('finalizer persists snapshot-scoped review onto the task', () async {
    await File('${workspace.path}/lib/main.dart').create(recursive: true);
    await File('${workspace.path}/lib/main.dart').writeAsString('old\n');
    final snapshot =
        await const WorkspaceSnapshotService().capture(workspace.path);
    await File('${workspace.path}/lib/main.dart').writeAsString('new\n');

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final task = await TaskService().create(
      db: db,
      conversationId: 'c1',
      type: 'development:implement_and_verify',
      requestJson: '{"prompt":"改主函数"}',
      metadata: {
        'taskType': 'implement_and_verify',
        'workspacePath': workspace.path,
      },
    );
    await TaskService().updateProgress(
      db,
      task.id,
      phase: 'completed',
      extra: {'workspaceSnapshot': snapshot.toJson()},
    );
    await TaskService().complete(
      db,
      task.id,
      status: 'completed',
      summary: 'done',
      runId: 'run-1',
    );

    final result = await DevelopmentLoopFinalizer().finalize(
      db: db,
      taskId: task.id,
      runId: 'run-1',
      workspacePath: workspace.path,
      runVerification: false,
    );
    expect(result.review.files.map((file) => file.path),
        contains('lib/main.dart'));
    final info = TaskService().describe((await db.findTask(task.id))!);
    expect(info.changeReview?.files, isNotEmpty);
    expect(info.status, 'completed');
  });

  test('unresolved patch rollback blocks automation and survives mixed audit',
      () async {
    await File('${workspace.path}/a.txt').writeAsString('old');
    await File('${workspace.path}/b.txt').writeAsString('old');
    final snapshot =
        await const WorkspaceSnapshotService().capture(workspace.path);
    await File('${workspace.path}/a.txt').writeAsString('external');
    await File('${workspace.path}/b.txt').writeAsString('new');
    final backup = 'a.txt.nexus-patch-${'a' * 32}.bak';
    await File('${workspace.path}/$backup').writeAsString('old');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final task = await TaskService().create(
        db: db,
        conversationId: 'c1',
        type: 'development:implement_and_verify',
        requestJson: '{"prompt":"fix"}',
        metadata: {
          'taskType': 'implement_and_verify',
          'workspacePath': workspace.path
        });
    await TaskService().updateProgress(db, task.id,
        phase: 'running', extra: {'workspaceSnapshot': snapshot.toJson()});
    final tracker = RunEventTracker(database: db, runId: 'patch-run');
    await tracker.record(type: 'file_operation', name: 'edit_file', metadata: {
      'fileOperation': true,
      'effect': 'applied',
      'path': 'b.txt',
      'operation': 'edit',
    });
    await tracker.record(
        type: 'file_operation',
        name: 'apply_patch',
        status: 'failed',
        metadata: {
          'fileOperation': true,
          'effect': 'unknown',
          'operation': 'apply_patch',
          'transactionStatus': 'needs_recovery',
          'unresolvedFiles': ['a.txt'],
          'recoveryFiles': [backup],
          'fileChanges': <Map<String, dynamic>>[],
        });
    await tracker.flush();
    final runtime = _ScriptedRuntime([]);
    final result = await DevelopmentLoopFinalizer().finalize(
        db: db,
        taskId: task.id,
        runId: 'patch-run',
        workspacePath: workspace.path,
        runVerification: true,
        terminal: TerminalCommandService(
            runtime: runtime, workspacePath: workspace.path));
    expect(runtime.commands, isEmpty);
    expect(result.verified, isFalse);
    expect(result.verificationSkipReason, contains('回滚存在冲突'));
    expect(result.review.files.map((f) => f.path),
        unorderedEquals(['a.txt', 'b.txt']));
    final progress = await TaskService().progress(db, task.id);
    expect((progress['taskSummary'] as Map)['openIssues'].toString(),
        contains('需要恢复'));
  });

  test('finalizer records why automated verification was skipped', () async {
    await File('${workspace.path}/lib/main.dart').create(recursive: true);
    await File('${workspace.path}/lib/main.dart').writeAsString('old\n');
    final snapshot =
        await const WorkspaceSnapshotService().capture(workspace.path);
    await File('${workspace.path}/lib/main.dart').writeAsString('new\n');

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final task = await TaskService().create(
      db: db,
      conversationId: 'c1',
      type: 'development:implement_and_verify',
      requestJson: '{"prompt":"改主函数"}',
      metadata: {
        'taskType': 'implement_and_verify',
        'workspacePath': workspace.path,
      },
    );
    await TaskService().updateProgress(
      db,
      task.id,
      phase: 'completed',
      extra: {'workspaceSnapshot': snapshot.toJson()},
    );

    // 调用方要求验证但没有传入已授权的终端：此时不得执行任何命令，
    // 且必须把「未验证」及其原因写进任务摘要。
    final skipped = await DevelopmentLoopFinalizer().finalize(
      db: db,
      taskId: task.id,
      runId: 'run-1',
      workspacePath: workspace.path,
      runVerification: true,
    );
    expect(skipped.verification, isNull);
    expect(skipped.verified, isFalse);
    expect(skipped.verificationSkipReason, contains('未获得授权'));

    final progress = await TaskService().progress(db, task.id);
    final summary = progress['taskSummary'] as Map<String, dynamic>;
    final openIssues = (summary['openIssues'] as List).cast<String>();
    expect(
      openIssues.any((issue) => issue.startsWith('未验证：')),
      isTrue,
      reason: '跳过的自动验证必须在任务摘要里显式标记为未验证：$openIssues',
    );
  });

  test('automatic verification runs checks only and stops before next command',
      () async {
    await File('${workspace.path}/pubspec.yaml')
        .writeAsString('name: demo\nflutter:\n  uses-material-design: true\n');
    final verification = DevelopmentVerificationService();
    final runtime = _ScriptedRuntime([
      const CommandResult(output: 'analyze ok', exitCode: 0),
    ]);
    final service =
        TerminalCommandService(workspacePath: workspace.path, runtime: runtime);
    final result = await verification.run(
      service: service,
      workspacePath: workspace.path,
      plan: await verification.planFor(workspace.path, includeBuild: false),
      canContinue: () => runtime.commands.isEmpty,
    );
    expect(runtime.commands, ['flutter analyze']);
    expect(result.success, isFalse);
    expect(result.plan.steps.first.error, contains('已取消'));
    expect(result.plan.steps.last.status, VerificationStepStatus.pending);
  });

  for (final scenario in [
    'pass',
    'still-failing',
    'repair-failed',
    'cancelled',
    'environment',
    'permission',
    'disabled'
  ]) {
    test('verification repair loop: $scenario', () async {
      await File('${workspace.path}/pubspec.yaml').writeAsString(
          'name: demo\nflutter:\n  uses-material-design: true\n');
      final source = File('${workspace.path}/main.dart');
      await source.writeAsString('baseline');
      final snapshot =
          await const WorkspaceSnapshotService().capture(workspace.path);
      await source.writeAsString('broken');
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final tasks = TaskService();
      final task = await tasks.create(
          db: db,
          conversationId: 'repair-test',
          type: 'development:implement_and_verify',
          requestJson: '{}',
          metadata: {
            'taskType': 'implement_and_verify',
            'prompt': 'fix feature'
          });
      await tasks.updateProgress(db, task.id, phase: 'running', extra: {
        'workspaceSnapshot': snapshot.toJson(),
        'verificationPlan': {'stale': true},
      });
      final runtime = _ScriptedRuntime([
        if (scenario == 'pass')
          const CommandResult(output: 'first analyze passes', exitCode: 0),
        CommandResult(
            output: scenario == 'environment'
                ? 'command not found'
                : scenario == 'permission'
                    ? 'EACCES permission denied'
                    : 'Assertion failed: missing value',
            exitCode: 1),
        CommandResult(
            output: 'second analyze',
            exitCode: scenario == 'still-failing' ? 1 : 0),
        const CommandResult(output: 'tests pass', exitCode: 0),
      ]);
      var repairs = 0;
      var active = true;
      final result = await DevelopmentLoopFinalizer().finalize(
        db: db,
        taskId: task.id,
        runId: 'repair-run',
        workspacePath: workspace.path,
        terminal: TerminalCommandService(
            workspacePath: workspace.path, runtime: runtime),
        runVerification: true,
        canContinue: () => active,
        repair: scenario == 'disabled'
            ? null
            : (request) async {
                repairs++;
                expect(request.attempt, 1);
                expect(request.relatedFiles, contains('main.dart'));
                expect(request.logExcerpt, contains('Assertion failed'));
                await source.writeAsString('repaired');
                await File('${workspace.path}/helper.dart')
                    .writeAsString('new helper');
                if (scenario == 'cancelled') active = false;
                return scenario != 'repair-failed';
              },
      );
      final expectedRepair =
          !['environment', 'permission', 'disabled'].contains(scenario);
      expect(repairs, expectedRepair ? 1 : 0);
      expect(result.verified, scenario == 'pass');
      if (scenario == 'pass') {
        expect(runtime.commands, [
          'flutter analyze',
          'flutter test',
          'flutter analyze',
          'flutter test'
        ]);
      }
      if (scenario == 'still-failing') expect(runtime.commands, hasLength(2));
      if (expectedRepair) {
        expect(result.review.files.map((f) => f.path), contains('helper.dart'));
      }
      final progress = await tasks.progress(db, task.id);
      final summary = progress['taskSummary'] as Map;
      if (scenario == 'repair-failed' || scenario == 'cancelled') {
        expect(progress['verificationPlan'], isNull);
        expect(summary['passedChecks'], isEmpty);
        expect(result.review.mark, ChangeVerificationMark.unverified);
        expect(summary['openIssues'], isNotEmpty);
        expect(runtime.commands, hasLength(1));
      }
      expect((progress['verificationRepairAttempts'] as List).length, repairs);
      if (scenario == 'still-failing') {
        runtime.results
          ..clear()
          ..add(const CommandResult(output: 'still broken', exitCode: 1));
        await DevelopmentLoopFinalizer().finalize(
          db: db,
          taskId: task.id,
          runId: 'repair-run',
          workspacePath: workspace.path,
          terminal: TerminalCommandService(
              workspacePath: workspace.path, runtime: runtime),
          runVerification: true,
          repair: (_) async =>
              fail('same run must not receive a new repair budget'),
        );
        final repeated = await tasks.progress(db, task.id);
        expect(repeated['verificationRepairAttempts'], hasLength(1));
      }
    });
  }

  test('task templates match development: prefixed types', () {
    expect(
      TaskTemplateService()
          .findByType('development:implement_and_verify')
          ?.implementsChanges,
      isTrue,
    );
    expect(
      TaskTemplateService().findByType('code_review')?.implementsChanges,
      isFalse,
    );
  });
}
