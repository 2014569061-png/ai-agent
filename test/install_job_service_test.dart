import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/dependency_lockfile.dart';
import 'package:mobile_agent/application/environment_service.dart';
import 'package:mobile_agent/application/install_job_service.dart';
import 'package:mobile_agent/application/project_environment_policy.dart';
import 'package:mobile_agent/application/project_kind.dart';
import 'package:mobile_agent/application/project_settings.dart';
import 'package:mobile_agent/application/project_template_service.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('nexus-install-');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('plans java apk install steps without flutter or gradle', () {
    final terminal = TerminalCommandService(
      workspacePath: temp.path,
      runtime: _ScriptedRuntime(),
    );
    final job = InstallJobService(terminal: terminal).plan(
      kind: ProjectKind.javaApk,
      snapshot: _snapshot(
        tools: const [
          EnvironmentToolStatus(
            id: 'sh',
            label: 'POSIX shell',
            available: true,
            detail: 'ok',
          ),
          EnvironmentToolStatus(
            id: 'javac',
            label: 'JDK / javac',
            available: false,
            detail: 'missing',
            installHint: 'apk add openjdk17',
          ),
        ],
      ),
      settings: const ProjectSettings(buildCommand: 'sh build.sh'),
    );
    expect(job.steps.map((step) => step.id), ['javac']);
    // 安装命令按运行时生成，而不是中文说明文本。
    expect(job.steps.single.command, 'apk add --no-cache openjdk17');
    expect(job.estimatedBytes, greaterThan(0));
    expect(job.steps.single.command.contains('flutter'), isFalse);
    expect(job.steps.single.command.contains('gradle'), isFalse);
  });

  test(
      'failed install step keeps log and does not auto-rerun after runtime switch',
      () async {
    final runtime = _ScriptedRuntime(exitCode: 1, output: 'javac missing');
    final terminal = TerminalCommandService(
      workspacePath: temp.path,
      runtime: runtime,
    );
    final installer = InstallJobService(terminal: terminal);
    final job = installer.plan(
      kind: ProjectKind.javaApk,
      snapshot: _snapshot(
        tools: const [
          EnvironmentToolStatus(
            id: 'sh',
            label: 'POSIX shell',
            available: true,
            detail: 'ok',
          ),
          EnvironmentToolStatus(
            id: 'javac',
            label: 'JDK / javac',
            available: false,
            detail: 'missing',
            installHint: 'apk add openjdk17',
          ),
        ],
      ),
    );
    final finished = await installer.run(
      job.id,
      startJob: (command) => terminal.startJob(command: command),
    );
    expect(finished.status, 'failed');
    expect(finished.failedStepId, 'javac');
    expect(finished.steps.single.log, contains('javac missing'));
    expect(finished.steps.single.sideEffectStarted, isTrue);

    final refused = installer.refuseRerunAfterRuntimeSwitch(job.id);
    expect(refused.status, 'failed');
    expect(refused.steps.single.log, contains('不能因切换 runtime 自动重跑'));
  });

  test('multiple lockfiles require an explicit choice', () async {
    await File(p.join(temp.path, 'package-lock.json')).writeAsString('{}');
    await File(p.join(temp.path, 'pnpm-lock.yaml'))
        .writeAsString('lockfileVersion: 9');
    expect(
      () => const DependencyLockfile().resolve(
        workspacePath: temp.path,
        kind: ProjectKind.node,
      ),
      throwsA(isA<LockfileConflict>()),
    );
    final chosen = const DependencyLockfile().resolve(
      workspacePath: temp.path,
      kind: ProjectKind.node,
      selectedId: 'pnpm',
    );
    expect(chosen?.installCommand, contains('pnpm'));
  });

  test('java apk template keeps sh build.sh and writes package path', () {
    final template = const ProjectTemplateService().findById('java-apk')!;
    expect(template.settings.buildCommand, 'sh build.sh');
    expect(template.settings.buildCommand!.contains('flutter'), isFalse);
    expect(
      template.files.any((file) =>
          file.relativePath == 'src/com/nexus/starter/MainActivity.java'),
      isTrue,
    );
    expect(
        template.files
            .singleWhere((file) => file.relativePath == 'build.sh')
            .contents,
        contains('Do not use flutter or gradle'));
  });

  test('install commands are generated per runtime, never the hint text', () {
    const policy = ProjectEnvironmentPolicy();
    final node =
        policy.requirementsFor(ProjectKind.node).firstWhere((r) => r.id == 'node');
    final python = policy
        .requirementsFor(ProjectKind.python)
        .firstWhere((r) => r.id == 'python');

    // Alpine：apk add；Termux：pkg install。两者都是可直接执行的命令。
    expect(
      policy.installCommandFor(node, LinuxRuntimeKind.builtinProot),
      'apk add --no-cache nodejs npm',
    );
    expect(
      policy.installCommandFor(node, LinuxRuntimeKind.termux),
      'pkg install -y nodejs',
    );
    expect(
      policy.installCommandFor(python, LinuxRuntimeKind.builtinProot),
      'apk add --no-cache python3',
    );

    // hint 是给用户看的说明，绝不能等于命令本身（否则 apk 会把中文当包名）。
    expect(node.installHint, isNot(contains('apk add')));
    expect(python.installHint, isNot(contains('apk add')));
  });

  test('runtimes without a package manager plan no install steps', () {
    // Android Shell 没有包管理器：必须如实不生成步骤，而不是伪造一步假安装。
    const policy = ProjectEnvironmentPolicy();
    final javac = policy
        .requirementsFor(ProjectKind.javaApk)
        .firstWhere((r) => r.id == 'javac');
    expect(
      policy.installCommandFor(javac, LinuxRuntimeKind.androidShell),
      isNull,
    );
    expect(
      policy.installCommandFor(javac, LinuxRuntimeKind.hostProcess),
      isNull,
    );

    final terminal = TerminalCommandService(
      workspacePath: temp.path,
      runtime: _ScriptedRuntime(),
    );
    final job = InstallJobService(terminal: terminal).plan(
      kind: ProjectKind.javaApk,
      snapshot: _snapshotWithRuntime(
        kind: LinuxRuntimeKind.androidShell,
        tools: const [
          EnvironmentToolStatus(
            id: 'sh',
            label: 'POSIX shell',
            available: true,
            detail: 'ok',
          ),
          EnvironmentToolStatus(
            id: 'javac',
            label: 'JDK / javac',
            available: false,
            detail: 'missing',
          ),
        ],
      ),
    );
    expect(job.steps, isEmpty);
    expect(job.status, 'completed');
  });
}

EnvironmentSnapshot _snapshot({
  required List<EnvironmentToolStatus> tools,
}) {
  return _snapshotWithRuntime(
    kind: LinuxRuntimeKind.builtinProot,
    tools: tools,
  );
}

EnvironmentSnapshot _snapshotWithRuntime({
  required LinuxRuntimeKind kind,
  required List<EnvironmentToolStatus> tools,
}) {
  final runtime = LinuxRuntimeInfo(
    kind: kind,
    label: kind.name,
    available: true,
    detail: 'ok',
  );
  return EnvironmentSnapshot(
    selected: runtime,
    candidates: [runtime],
    architecture: 'arm64',
    freeBytes: 1024 * 1024 * 1024,
    checkedAt: DateTime(2026, 1, 1),
    tools: tools,
    templates: const [],
  );
}

class _ScriptedRuntime implements LinuxRuntimeAdapter {
  _ScriptedRuntime({this.exitCode = 0, this.output = 'ok'});

  final int exitCode;
  final String output;
  int stopCount = 0;

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.builtinProot;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => false;

  @override
  Future<LinuxRuntimeInfo> inspect() async => const LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.builtinProot,
        label: 'Alpine',
        available: true,
        detail: 'ok',
        supportsShellSyntax: true,
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async =>
      CommandResult(output: output, exitCode: exitCode);

  @override
  void stop() {
    stopCount++;
  }
}
