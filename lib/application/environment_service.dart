import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../infrastructure/terminal/linux_runtime_factory.dart';
import '../infrastructure/tools/command_tool.dart';
import 'project_environment_policy.dart';
import 'project_kind.dart';
import 'project_settings.dart';
import 'project_template_service.dart';

class EnvironmentToolStatus {
  const EnvironmentToolStatus({
    required this.id,
    required this.label,
    required this.available,
    required this.detail,
    this.required = true,
    this.installHint,
    this.probed = true,
  });

  final String id;
  final String label;
  final bool available;
  final String detail;
  final bool required;
  final String? installHint;

  /// False means no real command was run for this status. In particular, a
  /// skipped legacy probe must not be treated as proof that a tool is absent.
  final bool probed;
}

/// The result of inspecting and (when possible) probing one runtime candidate.
///
/// [EnvironmentSnapshot.tools] remains the selected-runtime view for backwards
/// compatibility. This candidate view is what the service uses for global
/// capability aggregation.
class EnvironmentCandidateStatus {
  const EnvironmentCandidateStatus({
    required this.runtime,
    this.tools = const [],
    this.probeCompleted = false,
  });

  final LinuxRuntimeInfo runtime;
  final List<EnvironmentToolStatus> tools;
  final bool probeCompleted;

  bool get available => runtime.available;

  EnvironmentToolStatus? tool(String id) {
    for (final item in tools) {
      if (item.id == id) return item;
    }
    return null;
  }
}

class TemplateEnvironmentMatch {
  const TemplateEnvironmentMatch({
    required this.templateId,
    required this.label,
    required this.kind,
    this.blockedReason,
  });

  final String templateId;
  final String label;
  final ProjectKind kind;
  final String? blockedReason;

  bool get ready => blockedReason == null;
}

class EnvironmentSnapshot {
  const EnvironmentSnapshot({
    required this.selected,
    required this.candidates,
    required this.architecture,
    required this.freeBytes,
    required this.checkedAt,
    required this.tools,
    required this.templates,
    this.cached = false,
    this.missingCapabilities = const [],
    this.candidateStatuses = const [],
  });

  final LinuxRuntimeInfo selected;
  final List<LinuxRuntimeInfo> candidates;
  final String architecture;
  final int? freeBytes;
  final DateTime checkedAt;
  final List<EnvironmentToolStatus> tools;
  final List<TemplateEnvironmentMatch> templates;
  final bool cached;
  final List<String> missingCapabilities;

  /// Per-candidate probe results. This is optional so older callers that build
  /// snapshots directly keep compiling; service-created snapshots always fill
  /// it in for every candidate.
  final List<EnvironmentCandidateStatus> candidateStatuses;

  /// A display-safe view for snapshots created by older callers without the
  /// new candidate result field.
  List<EnvironmentCandidateStatus> get inspectedCandidates {
    if (candidateStatuses.isNotEmpty) return candidateStatuses;
    var selectedToolsUsed = false;
    return candidates.map((runtime) {
      final useSelected = !selectedToolsUsed &&
          selected.available &&
          runtime.kind == selected.kind &&
          runtime.available;
      if (useSelected) selectedToolsUsed = true;
      return EnvironmentCandidateStatus(
        runtime: runtime,
        tools: useSelected ? tools : const [],
        probeCompleted: useSelected,
      );
    }).toList(growable: false);
  }

  bool get alpineAvailable => inspectedCandidates.any((item) =>
      item.runtime.kind == LinuxRuntimeKind.builtinProot && item.available);
  bool get termuxAvailable => inspectedCandidates.any(
      (item) => item.runtime.kind == LinuxRuntimeKind.termux && item.available);
  bool get androidShellAvailable => inspectedCandidates.any((item) =>
      item.runtime.kind == LinuxRuntimeKind.androidShell && item.available);

  bool get shellAvailable => inspectedCandidates
      .any((item) => item.available && item.runtime.supportsShellSyntax);
  bool get interactiveAvailable => inspectedCandidates
      .any((item) => item.available && item.runtime.supportsInteractive);
  bool get liveOutputAvailable => inspectedCandidates
      .any((item) => item.available && item.runtime.supportsLiveOutput);

  String get summary {
    if (!selected.available) return '当前没有可用的 Linux 运行时';
    return '${selected.label} · ${selected.detail}';
  }

  String get scenarioLabel {
    if (kIsWeb) return 'Web 预览，不执行本机命令';
    if (alpineAvailable && termuxAvailable) return 'Alpine 与 Termux 均可用';
    if (alpineAvailable) return '仅有内置 Alpine';
    if (termuxAvailable) return '仅有 Termux';
    if (selected.kind == LinuxRuntimeKind.hostProcess && selected.available) {
      return '本机进程可用';
    }
    if (androidShellAvailable) return '仅有 Android Shell，工具链可能缺失';
    return '运行时不可用';
  }
}

class EnvironmentService {
  EnvironmentService({
    LinuxRuntimeAdapter? runtime,
    List<LinuxRuntimeAdapter>? candidates,
    ProjectEnvironmentPolicy? policy,
    ProjectTemplateService? templates,
    Future<int?> Function()? freeSpaceReader,
    Future<CommandProbeResult> Function(String command)? commandProbe,
    Future<CommandProbeResult> Function(
            LinuxRuntimeInfo runtime, String command)?
        runtimeCommandProbe,
    Future<CommandProbeResult> Function(String command, Duration timeout)?
        timedCommandProbe,
    Future<CommandProbeResult> Function(
            LinuxRuntimeInfo runtime, String command, Duration timeout)?
        timedRuntimeCommandProbe,
    this.runtimeInspectTimeout = const Duration(seconds: 3),
    this.commandProbeTimeout = const Duration(seconds: 3),
    this.storageReadTimeout = const Duration(seconds: 2),
  })  : _runtime = runtime ?? createDefaultLinuxRuntime(),
        _candidates = candidates ?? defaultLinuxRuntimeCandidates(),
        _policy = policy ?? const ProjectEnvironmentPolicy(),
        _templates = templates ?? const ProjectTemplateService(),
        _freeSpaceReader = freeSpaceReader,
        _commandProbe = commandProbe,
        _runtimeCommandProbe = runtimeCommandProbe,
        _timedCommandProbe = timedCommandProbe,
        _timedRuntimeCommandProbe = timedRuntimeCommandProbe;

  static const cacheTtl = Duration(minutes: 2);

  final LinuxRuntimeAdapter _runtime;
  final List<LinuxRuntimeAdapter> _candidates;
  final ProjectEnvironmentPolicy _policy;
  final ProjectTemplateService _templates;
  final Future<int?> Function()? _freeSpaceReader;
  final Future<CommandProbeResult> Function(String command)? _commandProbe;
  final Future<CommandProbeResult> Function(
      LinuxRuntimeInfo runtime, String command)? _runtimeCommandProbe;
  final Future<CommandProbeResult> Function(String command, Duration timeout)?
      _timedCommandProbe;
  final Future<CommandProbeResult> Function(
          LinuxRuntimeInfo runtime, String command, Duration timeout)?
      _timedRuntimeCommandProbe;
  final Duration runtimeInspectTimeout;
  final Duration commandProbeTimeout;
  final Duration storageReadTimeout;
  EnvironmentSnapshot? _cache;

  /// 是否配置了真实探针。面板在探针缺失时会把所有工具判为不可用，因此这个
  /// 状态本身需要可断言：接线漏掉时应当是测试失败，而不是安静的假「缺失」。
  bool get probeIsConfigured =>
      _commandProbe != null ||
      _runtimeCommandProbe != null ||
      _timedCommandProbe != null ||
      _timedRuntimeCommandProbe != null;

  Future<EnvironmentSnapshot> inspect({bool force = false}) async {
    final cached = _cache;
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.checkedAt) < cacheTtl) {
      return EnvironmentSnapshot(
        selected: cached.selected,
        candidates: cached.candidates,
        architecture: cached.architecture,
        freeBytes: cached.freeBytes,
        checkedAt: cached.checkedAt,
        tools: cached.tools,
        templates: cached.templates,
        cached: true,
        missingCapabilities: cached.missingCapabilities,
        candidateStatuses: cached.candidateStatuses,
      );
    }
    // Each candidate owns its own timeout. A broken native bridge therefore
    // cannot prevent later fallback runtimes from being inspected.
    final candidates = await Future.wait(
      _candidates.map(_inspectRuntime),
      eagerError: false,
    );
    var selected = await _inspectRuntime(_runtime, selected: true);
    if (!selected.available) {
      // The default Android selected adapter is adaptive. If its internal
      // selection is blocked by a hung first candidate, use the independently
      // inspected fallback result for this snapshot as well.
      LinuxRuntimeInfo? fallback;
      for (final candidate in candidates) {
        if (candidate.available) {
          fallback = candidate;
          break;
        }
      }
      if (fallback != null) selected = fallback;
    }

    // Keep the selected-runtime view for existing callers and template
    // blocking decisions, but probe every available candidate when the
    // runtime-aware seam is supplied.
    final tools = await _probeTools(selected);
    final candidateStatuses = await _probeCandidates(
      candidates: candidates,
      selected: selected,
      selectedTools: tools,
    );
    final availability = {
      for (final tool in tools) tool.id: tool.available,
    };
    final templates = _templates.all().map((template) {
      return TemplateEnvironmentMatch(
        templateId: template.id,
        label: template.label,
        kind: template.kind,
        blockedReason: _policy.blockedReason(
          kind: template.kind,
          settings: template.settings,
          toolAvailability: availability,
        ),
      );
    }).toList(growable: false);
    final missing = _missingCapabilities(
      selected: selected,
      candidates: candidateStatuses,
    );
    final snapshot = EnvironmentSnapshot(
      selected: selected,
      candidates: candidates,
      architecture: _architecture(),
      freeBytes: await _readFreeBytes(),
      checkedAt: DateTime.now(),
      tools: tools,
      templates: templates,
      candidateStatuses: candidateStatuses,
      missingCapabilities: missing,
    );
    _cache = snapshot;
    return snapshot;
  }

  /// 使缓存失效。探针结果同样要清掉，否则用户装完工具后点「重新检查」
  /// 仍会看到旧的「缺失」，等于假装装了没用。
  void invalidate() {
    _cache = null;
    resetCommandProbeCache();
  }

  String? blockedReasonFor({
    required ProjectKind kind,
    ProjectSettings settings = const ProjectSettings(),
    required EnvironmentSnapshot snapshot,
  }) {
    return _policy.blockedReason(
      kind: kind,
      settings: settings,
      toolAvailability: {
        for (final tool in snapshot.tools) tool.id: tool.available,
      },
    );
  }

  Future<List<EnvironmentToolStatus>> _probeTools(
      LinuxRuntimeInfo selected) async {
    if (!selected.available) {
      return const [
        EnvironmentToolStatus(
          id: 'runtime',
          label: 'Linux Runtime',
          available: false,
          detail: '没有可用运行时，不能探测工具版本',
          probed: false,
        ),
      ];
    }
    return _probeToolsForRuntime(selected, useLegacyProbe: true);
  }

  Future<List<EnvironmentToolStatus>> _probeToolsForRuntime(
    LinuxRuntimeInfo runtime, {
    required bool useLegacyProbe,
  }) async {
    final requirements = _allRequirements();
    if (!runtime.available) return const [];
    // A legacy one-argument probe has no way to address another runtime. Keep
    // that candidate's tool list empty rather than manufacturing a failed
    // result (or copying the selected runtime's result).
    if (!useLegacyProbe &&
        _runtimeCommandProbe == null &&
        _timedRuntimeCommandProbe == null) {
      return const [];
    }

    // Tool checks are independent. Running them serially made a full Android
    // inspection consume one timeout per tool and often exceed the page's
    // overall deadline even when a runtime was healthy.
    return Future.wait(requirements.map((requirement) async {
      try {
        final runtimeProbe = _runtimeCommandProbe;
        final legacyProbe = _commandProbe;
        final probe = await _runCommandProbe(
          runtime: runtime,
          command: requirement.checkCommand,
          useLegacyProbe: useLegacyProbe,
          runtimeProbe: runtimeProbe,
          legacyProbe: legacyProbe,
        ).timeout(commandProbeTimeout);
        return EnvironmentToolStatus(
          id: requirement.id,
          label: requirement.label,
          // A callback may return a skipped result for a runtime it cannot
          // reach. Such a result is never permission to claim availability.
          available: probe.probed && probe.available,
          detail: probe.detail,
          required: requirement.required,
          installHint: requirement.installHint,
          probed: probe.probed,
        );
      } on TimeoutException {
        return EnvironmentToolStatus(
          id: requirement.id,
          label: requirement.label,
          available: false,
          detail: '工具探测超时（${_formatTimeout(commandProbeTimeout)}），未确认是否安装；'
              '请打开 Termux 后重试。',
          required: requirement.required,
          installHint: requirement.installHint,
          probed: false,
        );
      } catch (error) {
        // An exception means a probe was attempted but failed. It must not be
        // mistaken for an unprobed candidate, while it also must never make a
        // tool appear available.
        return EnvironmentToolStatus(
          id: requirement.id,
          label: requirement.label,
          available: false,
          detail: '$error',
          required: requirement.required,
          installHint: requirement.installHint,
        );
      }
    }));
  }

  Future<CommandProbeResult> _runCommandProbe({
    required LinuxRuntimeInfo runtime,
    required String command,
    required bool useLegacyProbe,
    required Future<CommandProbeResult> Function(
            LinuxRuntimeInfo runtime, String command)?
        runtimeProbe,
    required Future<CommandProbeResult> Function(String command)? legacyProbe,
  }) {
    final timedRuntimeProbe = _timedRuntimeCommandProbe;
    if (timedRuntimeProbe != null) {
      return timedRuntimeProbe(runtime, command, commandProbeTimeout);
    }
    if (runtimeProbe != null) return runtimeProbe(runtime, command);

    final timedLegacyProbe = _timedCommandProbe;
    if (useLegacyProbe && timedLegacyProbe != null) {
      return timedLegacyProbe(command, commandProbeTimeout);
    }
    if (useLegacyProbe && legacyProbe != null) return legacyProbe(command);
    return Future.value(CommandProbeResult.skipped(command));
  }

  Future<LinuxRuntimeInfo> _inspectRuntime(
    LinuxRuntimeAdapter adapter, {
    bool selected = false,
  }) async {
    try {
      return await adapter.inspect().timeout(runtimeInspectTimeout);
    } on TimeoutException {
      return _unavailableRuntime(
        adapter,
        '${selected ? '当前运行时' : _runtimeLabel(adapter.kind)}检测超时'
        '（${_formatTimeout(runtimeInspectTimeout)}）；'
        '请打开 Termux 或重试。',
      );
    } catch (error) {
      return _unavailableRuntime(
        adapter,
        '${selected ? '当前运行时' : _runtimeLabel(adapter.kind)}检测失败：$error',
      );
    }
  }

  LinuxRuntimeInfo _unavailableRuntime(
    LinuxRuntimeAdapter adapter,
    String detail,
  ) {
    return LinuxRuntimeInfo(
      kind: adapter.kind,
      label: _runtimeLabel(adapter.kind),
      available: false,
      detail: detail,
      requiresExternalApp: adapter.kind == LinuxRuntimeKind.termux,
    );
  }

  String _runtimeLabel(LinuxRuntimeKind kind) => switch (kind) {
        LinuxRuntimeKind.builtinProot => '内置 Alpine Linux',
        LinuxRuntimeKind.termux => 'Termux Linux',
        LinuxRuntimeKind.androidShell => 'Android Shell',
        LinuxRuntimeKind.hostProcess => '本机进程',
      };

  String _formatTimeout(Duration timeout) {
    if (timeout.inMilliseconds < 1000) return '${timeout.inMilliseconds}ms';
    return '${timeout.inSeconds}s';
  }

  List<ProjectToolRequirement> _allRequirements() {
    final requirements = <ProjectToolRequirement>[];
    final seen = <String>{};
    for (final kind in ProjectKind.values) {
      for (final requirement in _policy.requirementsFor(kind)) {
        if (seen.add(requirement.id)) requirements.add(requirement);
      }
    }
    return requirements;
  }

  Future<List<EnvironmentCandidateStatus>> _probeCandidates({
    required List<LinuxRuntimeInfo> candidates,
    required LinuxRuntimeInfo selected,
    required List<EnvironmentToolStatus> selectedTools,
  }) async {
    var reusedSelected = false;
    final pending = candidates.map((candidate) async {
      if (!candidate.available) {
        return EnvironmentCandidateStatus(runtime: candidate);
      }

      // With the legacy one-argument callback, only the selected runtime has
      // been probed. Do not copy that result to another candidate: doing so
      // would claim availability without a command having run there.
      final canReuseSelected = candidate.kind == selected.kind &&
          selected.available &&
          !reusedSelected;
      final tools = canReuseSelected
          ? selectedTools
          : await _probeToolsForRuntime(
              candidate,
              useLegacyProbe: false,
            );
      if (canReuseSelected) reusedSelected = true;
      return EnvironmentCandidateStatus(
        runtime: candidate,
        tools: tools,
        probeCompleted: _probeCompleted(tools),
      );
    }).toList(growable: false);
    final results = await Future.wait(pending);

    // Custom callers sometimes provide a selected adapter that is not present
    // in the candidate list. It is still an available runtime and must count
    // for global capability aggregation.
    if (selected.available &&
        !results.any((item) =>
            item.runtime.kind == selected.kind && item.runtime.available)) {
      results.add(EnvironmentCandidateStatus(
        runtime: selected,
        tools: selectedTools,
        probeCompleted: _probeCompleted(selectedTools),
      ));
    }
    return results;
  }

  bool _probeCompleted(List<EnvironmentToolStatus> tools) {
    final byId = {for (final tool in tools) tool.id: tool};
    return _allRequirements().every(
      (requirement) => byId[requirement.id]?.probed == true,
    );
  }

  List<String> _missingCapabilities({
    required LinuxRuntimeInfo selected,
    required List<EnvironmentCandidateStatus> candidates,
  }) {
    final available = candidates
        .where((candidate) => candidate.runtime.available)
        .toList(growable: false);
    if (available.isEmpty) return const ['Linux Runtime'];

    final missing = <String>[];
    if (!available.any((item) => item.runtime.supportsShellSyntax)) {
      missing.add('完整 Shell');
    }
    if (!available.any((item) => item.runtime.supportsInteractive)) {
      missing.add('交互式终端');
    }
    if (!available.any((item) => item.runtime.supportsLiveOutput)) {
      missing.add('实时日志');
    }

    for (final requirement
        in _allRequirements().where((item) => item.required)) {
      final statuses =
          available.map((candidate) => candidate.tool(requirement.id));
      // A missing result means this available runtime was not probed. Global
      // absence cannot be established until every available runtime has a
      // real result for the requirement.
      final statusList = statuses.toList(growable: false);
      if (statusList.length != available.length ||
          statusList.any((item) => item == null || item.probed != true)) {
        continue;
      }
      if (statusList.every((item) => item!.available == false)) {
        missing.add(requirement.label);
      }
    }
    return missing;
  }

  Future<int?> _readFreeBytes() async {
    final reader = _freeSpaceReader;
    if (reader != null) {
      try {
        return await reader().timeout(storageReadTimeout);
      } catch (_) {
        return null;
      }
    }
    if (kIsWeb) return null;
    try {
      await getApplicationDocumentsDirectory().timeout(storageReadTimeout);
    } catch (_) {}
    return null;
  }

  String _architecture() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystemVersion;
  }
}

class CommandProbeResult {
  const CommandProbeResult({
    required this.available,
    required this.detail,
    this.probed = true,
  });

  factory CommandProbeResult.skipped(String label) => CommandProbeResult(
        available: false,
        detail: '尚未对 $label 执行真实命令探测；请点重新检查',
        probed: false,
      );

  final bool available;
  final String detail;

  /// A normal result means a real command was attempted. Skipped results are
  /// explicitly marked so global aggregation cannot infer absence from them.
  final bool probed;
}

final environmentServiceProvider = Provider<EnvironmentService>((ref) {
  // Keep the old single-command callback for compatibility, while the
  // runtime-aware callback makes a real probe in each available candidate.
  return EnvironmentService(
    commandProbe: probeWithTerminal,
    runtimeCommandProbe: probeWithRuntime,
    timedCommandProbe: (command, timeout) =>
        probeWithTerminal(command, timeout: timeout),
    timedRuntimeCommandProbe: (runtime, command, timeout) =>
        probeWithRuntime(runtime, command, timeout: timeout),
  );
});

/// Runtime-aware command probe cache. The runtime kind is part of the key:
/// `sh` succeeding in Android Shell must not make `sh` appear probed in Alpine.
final Map<String, CommandProbeResult> _runtimeProbeCache = {};
final Map<LinuxRuntimeKind, LinuxRuntimeAdapter> _runtimeProbeAdapters = {};

Future<CommandProbeResult> probeWithRuntime(
  LinuxRuntimeInfo runtime,
  String command, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (!runtime.available) return CommandProbeResult.skipped(runtime.label);
  final key = '${runtime.kind.name}:${timeout.inMicroseconds}:$command';
  final cached = _runtimeProbeCache[key];
  if (cached != null) return cached;

  final measured = await _probeWithRuntime(runtime.kind, command, timeout);
  _runtimeProbeCache[key] = measured;
  return measured;
}

/// Run policy-owned check commands directly against the candidate adapter.
/// This deliberately does not use [TerminalCommandService], whose workspace
/// guard cannot see Termux's private home directory from the app process.
Future<CommandProbeResult> _probeWithRuntime(
  LinuxRuntimeKind kind,
  String command,
  Duration timeout,
) async {
  final adapter = _runtimeProbeAdapter(kind);
  if (adapter == null) {
    return const CommandProbeResult(
      available: false,
      detail: '没有配置该运行时的探测适配器。',
      probed: false,
    );
  }
  try {
    final workingDirectory =
        await _runtimeProbeWorkingDirectory(kind).timeout(timeout);
    if (workingDirectory == null) {
      return const CommandProbeResult(
        available: false,
        detail: '没有可用于探测该运行时的工作目录。',
        probed: false,
      );
    }
    final parsed = _parseProbeCommand(command);
    if (parsed.isEmpty) {
      return const CommandProbeResult(
        available: false,
        detail: '探测命令解析失败。',
        probed: false,
      );
    }
    final executable = parsed.first;
    final normalized =
        p.basename(executable.replaceAll('\\', '/')).toLowerCase();
    final request = LinuxCommandRequest(
      commandLine: command,
      executable: executable,
      normalizedCommand: normalized,
      arguments: List<String>.unmodifiable(parsed.skip(1)),
    );
    final result = await adapter.run(
      request,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
    final output = result.output.trim();
    if (result.notExecuted) {
      return CommandProbeResult(
        available: false,
        detail: output,
        probed: false,
      );
    }
    return CommandProbeResult(
      available: result.exitCode == 0 && !result.timedOut,
      detail: output.isEmpty ? '退出码 ${result.exitCode}' : output,
      probed: !result.timedOut,
    );
  } on TimeoutException {
    return CommandProbeResult(
      available: false,
      detail: '探测超时（${timeout.inSeconds}s），未确认工具是否安装。',
      probed: false,
    );
  } catch (error) {
    return CommandProbeResult(available: false, detail: '探测失败：$error');
  }
}

Future<String?> _runtimeProbeWorkingDirectory(LinuxRuntimeKind kind) async {
  // Termux resolves this path inside the external app. The Flutter process
  // must not require (or attempt to create) Termux's private directory.
  if (kind == LinuxRuntimeKind.termux) {
    return '/sdcard/pocketforge-bridge';
  }
  try {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'environment-probe', kind.name),
    );
    await directory.create(recursive: true);
    return directory.path;
  } catch (_) {
    return null;
  }
}

LinuxRuntimeAdapter? _runtimeProbeAdapter(LinuxRuntimeKind kind) {
  final existing = _runtimeProbeAdapters[kind];
  if (existing != null) return existing;
  for (final candidate in defaultLinuxRuntimeCandidates()) {
    if (candidate.kind != kind) continue;
    _runtimeProbeAdapters[kind] = candidate;
    return candidate;
  }
  return null;
}

List<String> _parseProbeCommand(String value) {
  final result = <String>[];
  final buffer = StringBuffer();
  String? quote;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if ((char == '"' || char == "'") && (quote == null || quote == char)) {
      quote = quote == null ? char : null;
    } else if (char.trim().isEmpty && quote == null) {
      if (buffer.isNotEmpty) {
        result.add(buffer.toString());
        buffer.clear();
      }
    } else {
      buffer.write(char);
    }
  }
  if (quote != null) return const [];
  if (buffer.isNotEmpty) result.add(buffer.toString());
  return result;
}

/// 用真实的终端运行时探测一条 `checkCommand`。
///
/// 面板此前从不传探针，`_probeTools` 于是把所有工具判为不可用（连 rootfs 里
/// 确实存在的 `/bin/sh` 都被报成缺失），且「重新检查」只是重跑同一段无探针
/// 逻辑，永远不变。这里把探针接到真正的 runtime 上，让面板反映真实状态。
///
/// 探测失败（无运行时、命令不存在、超时）一律按不可用处理，但保留原始输出来
/// 说明原因，避免把「探测不到」伪装成「已安装」。
///
/// 同一进程内按命令缓存：环境检测会被多个页面各触发一次，而启动 PRoot、
/// `javac -version` 这类命令并不便宜。
final Map<String, CommandProbeResult> _probeCache = {};

/// 复用一个探测终端：每个 `TerminalCommandService` 都会自建一套 runtime
/// 适配器，「重新检查」逐条探测时不该反复重建。串行执行也因此由同一个
/// 实例的序列化保证，避免并发 PRoot 进程互相干扰。
TerminalCommandService? _probeTerminal;
Future<TerminalCommandService?>? _probeTerminalPending;

/// 清空探测缓存（环境页的「重新初始化」应看到重新探测后的真实状态）。
void resetCommandProbeCache() {
  _probeCache.clear();
  _runtimeProbeCache.clear();
  _runtimeProbeAdapters.clear();
  _probeTerminal = null;
  _probeTerminalPending = null;
}

Future<CommandProbeResult> probeWithTerminal(
  String command, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final key = '${timeout.inMicroseconds}:$command';
  final cached = _probeCache[key];
  if (cached != null) return cached;

  final measured = await _probeWithTerminal(command, timeout);
  _probeCache[key] = measured;
  return measured;
}

Future<CommandProbeResult> _probeWithTerminal(
  String command,
  Duration timeout,
) async {
  try {
    final terminal = await _sharedProbeTerminal().timeout(timeout);
    if (terminal == null) {
      return const CommandProbeResult(
        available: false,
        detail: '找不到可用于探测的工作目录（应用私有目录不可写）。',
        probed: false,
      );
    }
    final result = await terminal.run(
      command,
      timeout: timeout,
    );
    final output = result.output.trim();
    if (result.notExecuted) {
      return CommandProbeResult(
        available: false,
        detail: output,
        probed: false,
      );
    }
    return CommandProbeResult(
      available: result.exitCode == 0 && !result.timedOut,
      detail: output.isEmpty ? '退出码 ${result.exitCode}' : output,
      probed: !result.timedOut,
    );
  } on TimeoutException {
    return CommandProbeResult(
      available: false,
      detail: '探测超时（${timeout.inSeconds}s），未确认工具是否安装。',
      probed: false,
    );
  } catch (error) {
    return CommandProbeResult(available: false, detail: '探测失败：$error');
  }
}

Future<TerminalCommandService?> _sharedProbeTerminal() {
  final existing = _probeTerminal;
  if (existing != null) return Future.value(existing);
  final pending = _probeTerminalPending;
  if (pending != null) return pending;

  final created = () async {
    // 探测需要一个位于可写目录内的 cwd：`TerminalCommandService` 会拒绝工作区
    // 之外的工作目录，而环境检测发生在任何项目工作区存在之前。
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'environment-probe'));
      await dir.create(recursive: true);
      final terminal = TerminalCommandService(
        workspacePath: dir.path,
        jobLogDirectory: Directory(p.join(dir.path, '.nexus', 'probe-jobs')),
      );
      _probeTerminal = terminal;
      return terminal;
    } catch (_) {
      return null;
    }
  }();

  _probeTerminalPending = created;
  return created;
}
