import 'dart:async';

import '../domain/unique_id.dart';
import '../infrastructure/tools/command_tool.dart';
import 'environment_service.dart';
import 'project_environment_policy.dart';
import 'project_kind.dart';
import 'project_settings.dart';

class InstallJobStep {
  const InstallJobStep({
    required this.id,
    required this.label,
    required this.command,
    required this.estimatedBytes,
    this.status = 'pending',
    this.log = '',
    this.exitCode,
    this.sideEffectStarted = false,
  });

  final String id;
  final String label;
  final String command;
  final int estimatedBytes;
  final String status;
  final String log;
  final int? exitCode;
  final bool sideEffectStarted;

  bool get failed => status == 'failed';
  bool get completed => status == 'completed';

  InstallJobStep copyWith({
    String? status,
    String? log,
    int? exitCode,
    bool? sideEffectStarted,
  }) {
    return InstallJobStep(
      id: id,
      label: label,
      command: command,
      estimatedBytes: estimatedBytes,
      status: status ?? this.status,
      log: log ?? this.log,
      exitCode: exitCode ?? this.exitCode,
      sideEffectStarted: sideEffectStarted ?? this.sideEffectStarted,
    );
  }
}

class InstallJob {
  const InstallJob({
    required this.id,
    required this.kind,
    required this.runtimeId,
    required this.steps,
    this.workspacePath,
    this.status = 'pending',
    this.failedStepId,
  });

  final String id;
  final ProjectKind kind;
  final String runtimeId;
  final String? workspacePath;
  final List<InstallJobStep> steps;
  final String status;
  final String? failedStepId;

  int get estimatedBytes =>
      steps.fold(0, (sum, step) => sum + step.estimatedBytes);

  InstallJob copyWith({
    List<InstallJobStep>? steps,
    String? status,
    String? failedStepId,
    bool clearFailedStep = false,
  }) {
    return InstallJob(
      id: id,
      kind: kind,
      runtimeId: runtimeId,
      workspacePath: workspacePath,
      steps: steps ?? this.steps,
      status: status ?? this.status,
      failedStepId:
          clearFailedStep ? null : (failedStepId ?? this.failedStepId),
    );
  }
}

class InstallJobService {
  InstallJobService({
    required this.terminal,
    ProjectEnvironmentPolicy? policy,
    EnvironmentService? environment,
  })  : _policy = policy ?? const ProjectEnvironmentPolicy(),
        _environment = environment;

  final TerminalCommandService terminal;
  final ProjectEnvironmentPolicy _policy;
  final EnvironmentService? _environment;
  final Map<String, InstallJob> _jobs = {};

  InstallJob plan({
    required ProjectKind kind,
    required EnvironmentSnapshot snapshot,
    ProjectSettings settings = const ProjectSettings(),
    String? workspacePath,
    String? extraCommand,
  }) {
    final availability = {
      for (final tool in snapshot.tools) tool.id: tool.available,
    };
    final steps = <InstallJobStep>[];
    for (final requirement in _policy.requirementsFor(kind)) {
      if (!requirement.required) continue;
      if (availability[requirement.id] == true) continue;
      // 安装命令必须按当前运行时生成。以前这里把中文 installHint 当命令执行，
      // 必然失败；没有包管理器的运行时直接跳过，由界面如实说明。
      final command =
          _policy.installCommandFor(requirement, snapshot.selected.kind);
      if (command == null) continue;
      steps.add(InstallJobStep(
        id: requirement.id,
        label: '安装 ${requirement.label}',
        command: command,
        estimatedBytes: _estimate(requirement.id),
      ));
    }
    if (extraCommand != null && extraCommand.trim().isNotEmpty) {
      if (!steps.any((step) => step.command == extraCommand)) {
        steps.add(InstallJobStep(
          id: 'lockfile',
          label: '按锁文件安装依赖',
          command: extraCommand,
          estimatedBytes: 8 * 1024 * 1024,
        ));
      }
    }
    final job = InstallJob(
      id: UniqueId.generate('install'),
      kind: kind,
      runtimeId: snapshot.selected.kind.name,
      workspacePath: workspacePath,
      steps: steps,
      status: steps.isEmpty ? 'completed' : 'pending',
    );
    _jobs[job.id] = job;
    return job;
  }

  InstallJob? find(String id) => _jobs[id];

  Future<InstallJob> run(
    String jobId, {
    required Future<TerminalJobHandle> Function(String command) startJob,
  }) async {
    final existing = _jobs[jobId];
    if (existing == null) {
      throw StateError('安装作业不存在');
    }
    var job = existing.copyWith(status: 'running');
    _jobs[jobId] = job;
    final updated = <InstallJobStep>[];
    for (final step in job.steps) {
      if (step.completed) {
        updated.add(step);
        continue;
      }
      if (step.sideEffectStarted) {
        updated.add(step.copyWith(
          status: 'failed',
          log: '该步骤已产生副作用，不能因切换 runtime 自动重跑',
        ));
        job = job.copyWith(
          steps: [...updated, ...job.steps.skip(updated.length)],
          status: 'failed',
          failedStepId: step.id,
        );
        _jobs[jobId] = job;
        _environment?.invalidate();
        return job;
      }
      var current = step.copyWith(status: 'running', sideEffectStarted: true);
      updated.add(current);
      job =
          job.copyWith(steps: [...updated, ...job.steps.skip(updated.length)]);
      _jobs[jobId] = job;
      final handle = await startJob(step.command);
      final events = await terminal.watchJob(handle.jobId).toList();
      final completed = events.lastWhere(
        (event) => event.type == 'completed' || event.type == 'timeout',
        orElse: () => events.isEmpty
            ? TerminalJobEvent(
                jobId: handle.jobId,
                sequence: 0,
                timestamp: DateTime.now(),
                type: 'completed',
                payload: '',
                exitCode: 1,
              )
            : events.last,
      );
      final ok = completed.exitCode == 0;
      current = current.copyWith(
        status: ok ? 'completed' : 'failed',
        log: completed.payload,
        exitCode: completed.exitCode,
      );
      updated[updated.length - 1] = current;
      job = job.copyWith(
        steps: [...updated, ...job.steps.skip(updated.length)],
        status: ok ? 'running' : 'failed',
        failedStepId: ok ? null : step.id,
      );
      _jobs[jobId] = job;
      if (!ok) {
        _environment?.invalidate();
        return job;
      }
    }
    job = job.copyWith(
      status: 'completed',
      steps: updated,
      clearFailedStep: true,
    );
    _jobs[jobId] = job;
    _environment?.invalidate();
    return job;
  }

  /// 运行时回退后：已产生副作用的步骤不会自动重跑。
  InstallJob refuseRerunAfterRuntimeSwitch(String jobId) {
    final existing = _jobs[jobId];
    if (existing == null) {
      throw StateError('安装作业不存在');
    }
    final steps = [
      for (final step in existing.steps)
        if (step.sideEffectStarted && !step.completed)
          step.copyWith(
            status: 'failed',
            log: '该步骤已产生副作用，不能因切换 runtime 自动重跑',
          )
        else
          step,
    ];
    InstallJobStep? failed;
    for (final step in steps) {
      if (step.failed) {
        failed = step;
        break;
      }
    }
    final job = existing.copyWith(
      steps: steps,
      status: failed == null ? existing.status : 'failed',
      failedStepId: failed?.id,
    );
    _jobs[jobId] = job;
    return job;
  }

  int _estimate(String id) => switch (id) {
        'node' || 'npm' => 40 * 1024 * 1024,
        'python' => 25 * 1024 * 1024,
        'javac' => 80 * 1024 * 1024,
        'go' => 60 * 1024 * 1024,
        _ => 8 * 1024 * 1024,
      };
}
