import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/environment_service.dart';
import 'package:mobile_agent/application/project_environment_policy.dart';
import 'package:mobile_agent/application/project_kind.dart';
import 'package:mobile_agent/application/project_settings.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';

void main() {
  test('inspects each runtime independently and labels Alpine-only', () async {
    final alpine = _FakeRuntime(
      kind: LinuxRuntimeKind.builtinProot,
      label: '内置 Alpine',
      available: true,
    );
    final termux = _FakeRuntime(
      kind: LinuxRuntimeKind.termux,
      label: 'Termux',
      available: false,
    );
    final shell = _FakeRuntime(
      kind: LinuxRuntimeKind.androidShell,
      label: 'Android Shell',
      available: false,
    );
    final service = EnvironmentService(
      runtime: alpine,
      candidates: [alpine, termux, shell],
      commandProbe: (_) async =>
          const CommandProbeResult(available: false, detail: 'skipped'),
    );

    final snapshot = await service.inspect(force: true);
    expect(snapshot.scenarioLabel, '仅有内置 Alpine');
    expect(snapshot.alpineAvailable, isTrue);
    expect(snapshot.termuxAvailable, isFalse);
    expect(snapshot.selected.label, '内置 Alpine');
  });

  test('global required tools are missing only when every runtime probe fails',
      () async {
    final alpine = _FakeRuntime(
      kind: LinuxRuntimeKind.builtinProot,
      label: 'Alpine',
      available: true,
    );
    final androidShell = _FakeRuntime(
      kind: LinuxRuntimeKind.androidShell,
      label: 'Android Shell',
      available: true,
    );
    final calls = <String>[];
    final service = EnvironmentService(
      runtime: alpine,
      candidates: [alpine, androidShell],
      runtimeCommandProbe: (runtime, command) async {
        calls.add('${runtime.kind.name}:$command');
        final hasJavac = runtime.kind == LinuxRuntimeKind.androidShell &&
            command == 'javac -version';
        return CommandProbeResult(
          available: hasJavac || command == 'sh -c echo',
          detail: hasJavac ? 'javac 17' : 'ok',
        );
      },
    );

    final snapshot = await service.inspect(force: true);
    final selectedJavac =
        snapshot.tools.singleWhere((tool) => tool.id == 'javac');
    final shellJavac = snapshot.inspectedCandidates
        .singleWhere((candidate) =>
            candidate.runtime.kind == LinuxRuntimeKind.androidShell)
        .tool('javac');

    expect(selectedJavac.available, isFalse);
    expect(shellJavac?.available, isTrue);
    expect(snapshot.missingCapabilities, isNot(contains('JDK / javac')));
    expect(calls, contains('builtinProot:javac -version'));
    expect(calls, contains('androidShell:javac -version'));
  });

  test('legacy single-runtime probe does not claim an unprobed candidate',
      () async {
    final alpine = _FakeRuntime(
      kind: LinuxRuntimeKind.builtinProot,
      label: 'Alpine',
      available: true,
    );
    final androidShell = _FakeRuntime(
      kind: LinuxRuntimeKind.androidShell,
      label: 'Android Shell',
      available: true,
    );
    final service = EnvironmentService(
      runtime: alpine,
      candidates: [alpine, androidShell],
      commandProbe: (_) async =>
          const CommandProbeResult(available: false, detail: 'missing'),
    );

    final snapshot = await service.inspect(force: true);
    final alternate = snapshot.inspectedCandidates.singleWhere(
        (candidate) => candidate.runtime.kind == LinuxRuntimeKind.androidShell);

    expect(alternate.tool('javac'), isNull);
    expect(snapshot.missingCapabilities, isNot(contains('JDK / javac')));
  });

  test('shell interactive and live output aggregate across candidates',
      () async {
    final alpine = _FakeRuntime(
      kind: LinuxRuntimeKind.builtinProot,
      label: 'Alpine',
      available: true,
      supportsInteractive: false,
      supportsLiveOutput: false,
    );
    final termux = _FakeRuntime(
      kind: LinuxRuntimeKind.termux,
      label: 'Termux',
      available: true,
      supportsInteractive: true,
      supportsLiveOutput: true,
    );
    final service = EnvironmentService(
      runtime: alpine,
      candidates: [alpine, termux],
      runtimeCommandProbe: (_, __) async =>
          const CommandProbeResult(available: true, detail: 'ok'),
    );

    final snapshot = await service.inspect(force: true);

    expect(snapshot.shellAvailable, isTrue);
    expect(snapshot.interactiveAvailable, isTrue);
    expect(snapshot.liveOutputAvailable, isTrue);
    expect(snapshot.missingCapabilities, isNot(contains('交互式终端')));
    expect(snapshot.missingCapabilities, isNot(contains('实时日志')));
  });

  test('java apk is blocked without javac and never uses flutter commands', () {
    const policy = ProjectEnvironmentPolicy();
    expect(
      policy.blockedReason(
        kind: ProjectKind.javaApk,
        settings: const ProjectSettings(buildCommand: 'sh build.sh'),
        toolAvailability: {'sh': true, 'javac': false},
      ),
      '缺少 JDK / javac',
    );
    expect(
      policy.blockedReason(
        kind: ProjectKind.javaApk,
        settings: const ProjectSettings(buildCommand: 'flutter build apk'),
        toolAvailability: {'sh': true, 'javac': true},
      ),
      'Java APK 模板不能使用 Flutter/Gradle 默认命令',
    );
  });

  test('cached snapshots expire only after invalidate or force', () async {
    final runtime = _FakeRuntime(
      kind: LinuxRuntimeKind.hostProcess,
      label: '本机',
      available: true,
    );
    var probes = 0;
    final service = EnvironmentService(
      runtime: runtime,
      candidates: [runtime],
      commandProbe: (_) async {
        probes++;
        return const CommandProbeResult(available: true, detail: 'ok');
      },
    );
    await service.inspect(force: true);
    final firstProbes = probes;
    expect(firstProbes, greaterThan(0));
    final cached = await service.inspect();
    expect(cached.cached, isTrue);
    expect(probes, firstProbes);
    service.invalidate();
    await service.inspect(force: true);
    expect(probes, greaterThan(firstProbes));
  });

  test('provider wires a real probe so missing tools are not hardcoded', () {
    // 回归：provider 曾经构造不带 commandProbe 的服务，导致所有工具恒被判为
    // 缺失（连 rootfs 里确实存在的 /bin/sh 也报红），且「重新检查」永远不变。
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(environmentServiceProvider);
    expect(service.probeIsConfigured, isTrue);
  });

  test('returns a degraded snapshot when a runtime probe never completes',
      () async {
    final hanging = _HangingRuntime(LinuxRuntimeKind.builtinProot);
    final fallback = _FakeRuntime(
      kind: LinuxRuntimeKind.androidShell,
      label: 'Android Shell',
      available: true,
    );
    final service = EnvironmentService(
      runtime: hanging,
      candidates: [hanging, fallback],
      runtimeInspectTimeout: const Duration(milliseconds: 20),
      commandProbeTimeout: const Duration(milliseconds: 20),
      storageReadTimeout: const Duration(milliseconds: 20),
    );

    final outcome = await Future.any<Object>([
      service.inspect(force: true),
      Future<Object>.delayed(
        const Duration(milliseconds: 100),
        () => const _InspectionTimedOut(),
      ),
    ]);

    expect(
      outcome,
      isA<EnvironmentSnapshot>(),
      reason: '环境检查不能因一个失联 runtime 永久 pending',
    );
    final snapshot = outcome as EnvironmentSnapshot;
    expect(snapshot.selected.available, isTrue);
    expect(
      snapshot.inspectedCandidates
          .singleWhere(
              (item) => item.runtime.kind == LinuxRuntimeKind.builtinProot)
          .runtime
          .detail,
      contains('超时'),
    );
    expect(snapshot.inspectedCandidates, hasLength(2));
    expect(
      snapshot.inspectedCandidates
          .singleWhere(
              (item) => item.runtime.kind == LinuxRuntimeKind.androidShell)
          .available,
      isTrue,
    );
  });

  test('marks a timed-out tool probe as unprobed instead of missing', () async {
    final runtime = _FakeRuntime(
      kind: LinuxRuntimeKind.hostProcess,
      label: '本机',
      available: true,
    );
    final service = EnvironmentService(
      runtime: runtime,
      candidates: [runtime],
      commandProbeTimeout: const Duration(milliseconds: 20),
      commandProbe: (_) => Completer<CommandProbeResult>().future,
    );

    final snapshot = await service.inspect(force: true);
    final shell = snapshot.tools.singleWhere((tool) => tool.id == 'sh');

    expect(shell.available, isFalse);
    expect(shell.probed, isFalse);
    expect(shell.detail, contains('超时'));
  });

  test('probes tools and alternate runtimes concurrently', () async {
    final alpine = _FakeRuntime(
      kind: LinuxRuntimeKind.builtinProot,
      label: 'Alpine',
      available: true,
    );
    final termux = _FakeRuntime(
      kind: LinuxRuntimeKind.termux,
      label: 'Termux',
      available: true,
    );
    final stopwatch = Stopwatch()..start();
    final service = EnvironmentService(
      runtime: alpine,
      candidates: [alpine, termux],
      runtimeCommandProbe: (_, __) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return const CommandProbeResult(available: true, detail: 'ok');
      },
    );

    final snapshot = await service.inspect(force: true);
    stopwatch.stop();

    expect(snapshot.inspectedCandidates, hasLength(2));
    expect(
      stopwatch.elapsed,
      lessThan(const Duration(milliseconds: 300)),
      reason: 'independent probes must not consume one timeout per tool',
    );
  });

  test('does not let free-space storage reads block an environment snapshot',
      () async {
    final runtime = _FakeRuntime(
      kind: LinuxRuntimeKind.hostProcess,
      label: '本机',
      available: false,
    );
    final service = EnvironmentService(
      runtime: runtime,
      candidates: [runtime],
      storageReadTimeout: const Duration(milliseconds: 20),
      freeSpaceReader: () => Completer<int?>().future,
    );

    final snapshot = await service.inspect(force: true);

    expect(snapshot.freeBytes, isNull);
  });
}

class _InspectionTimedOut {
  const _InspectionTimedOut();
}

class _HangingRuntime implements LinuxRuntimeAdapter {
  _HangingRuntime(this.kind);

  @override
  final LinuxRuntimeKind kind;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => false;

  @override
  Future<LinuxRuntimeInfo> inspect() => Completer<LinuxRuntimeInfo>().future;

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async =>
      const CommandResult(output: '', exitCode: 0);

  @override
  void stop() {}
}

class _FakeRuntime implements LinuxRuntimeAdapter {
  _FakeRuntime({
    required this.kind,
    required this.label,
    required this.available,
    this.supportsInteractive = false,
    this.supportsLiveOutput = false,
  });

  @override
  final LinuxRuntimeKind kind;
  final String label;
  final bool available;
  final bool supportsInteractive;
  final bool supportsLiveOutput;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => false;

  @override
  Future<LinuxRuntimeInfo> inspect() async => LinuxRuntimeInfo(
        kind: kind,
        label: label,
        available: available,
        detail: available ? '可用' : '不可用',
        supportsInteractive: supportsInteractive,
        supportsLiveOutput: supportsLiveOutput,
        supportsShellSyntax: true,
      );

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async =>
      const CommandResult(output: '', exitCode: 0);

  @override
  void stop() {}
}
