import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../infrastructure/terminal/linux_runtime.dart';
import '../infrastructure/terminal/linux_runtime_factory.dart';
import 'development_target.dart';

class DevelopmentToolInstallResult {
  const DevelopmentToolInstallResult({
    required this.succeeded,
    required this.message,
    this.runtime,
  });

  final bool succeeded;
  final String message;
  final LinuxRuntimeKind? runtime;
}

/// Installs the small, broadly useful toolchain into one real Linux runtime.
/// Large Android/Flutter SDKs stay opt-in because they consume substantial
/// storage and are not reliably supported inside an Android ARM64 PRoot.
class DevelopmentToolInstaller {
  DevelopmentToolInstaller({
    List<LinuxRuntimeAdapter>? candidates,
    Future<Directory> Function()? supportDirectory,
    this.inspectTimeout = const Duration(seconds: 5),
    this.installTimeout = const Duration(minutes: 15),
  })  : _candidates = candidates ?? defaultLinuxRuntimeCandidates(),
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static const alpineCommand = 'apk update && apk add --no-cache '
      'nodejs npm python3 py3-pip go git curl jq';
  static const termuxCommand = 'pkg update -y && pkg install -y '
      'nodejs npm python python-pip golang git curl jq';

  final List<LinuxRuntimeAdapter> _candidates;
  final Future<Directory> Function() _supportDirectory;
  final Duration inspectTimeout;
  final Duration installTimeout;

  Future<DevelopmentToolInstallResult> installCommonTools() async {
    return installForTarget(null);
  }

  /// Installs only packages that belong to [target]. A null target keeps the
  /// legacy broad common-toolchain behavior for the existing setup entry.
  Future<DevelopmentToolInstallResult> installForTarget(
    DevelopmentTarget? target,
  ) async {
    if (target != null && !target.canInstallHere) {
      return DevelopmentToolInstallResult(
        succeeded: true,
        message: '${target.label} 没有可在当前 Linux 环境自动安装的工具。',
      );
    }

    LinuxRuntimeAdapter? selected;
    for (final candidate in _candidates) {
      if (candidate.kind != LinuxRuntimeKind.builtinProot &&
          candidate.kind != LinuxRuntimeKind.termux) {
        continue;
      }
      try {
        final info = await candidate.inspect().timeout(inspectTimeout);
        if (info.available) {
          selected = candidate;
          break;
        }
      } catch (_) {}
    }

    if (selected == null) {
      return const DevelopmentToolInstallResult(
        succeeded: false,
        message: '没有可安装工具的 Linux 环境。请先完成内置 Alpine 或 Termux 初始化。',
      );
    }

    final command = target == null
        ? (selected.kind == LinuxRuntimeKind.builtinProot
            ? alpineCommand
            : termuxCommand)
        : _targetCommand(target, selected.kind);
    final workingDirectory = await _workingDirectory(selected.kind);
    final result = await selected.run(
      LinuxCommandRequest(
        commandLine: command,
        executable:
            selected.kind == LinuxRuntimeKind.builtinProot ? 'apk' : 'pkg',
        normalizedCommand:
            selected.kind == LinuxRuntimeKind.builtinProot ? 'apk' : 'pkg',
        arguments: const [],
      ),
      workingDirectory: workingDirectory,
      timeout: installTimeout,
    );

    if (result.succeeded) {
      return DevelopmentToolInstallResult(
        succeeded: true,
        runtime: selected.kind,
        message: target == null
            ? (selected.kind == LinuxRuntimeKind.builtinProot
                ? '常用工具已安装到内置 Alpine。'
                : '常用工具已安装到 Termux。')
            : '${target.label} 所需的可安装工具已配置到${selected.kind == LinuxRuntimeKind.builtinProot ? '内置 Alpine' : 'Termux'}。',
      );
    }

    final output = result.output.trim();
    return DevelopmentToolInstallResult(
      succeeded: false,
      runtime: selected.kind,
      message: output.isEmpty
          ? '安装失败（退出码 ${result.exitCode}）。请检查网络和剩余空间后重试。'
          : '安装失败：${_tail(output)}',
    );
  }

  String _targetCommand(DevelopmentTarget target, LinuxRuntimeKind kind) {
    final packages = target.tools
        .map((tool) => kind == LinuxRuntimeKind.builtinProot
            ? tool.alpinePackages
            : tool.termuxPackages)
        .expand((items) => items)
        .toSet()
        .toList()
      ..sort();
    if (packages.isEmpty) {
      return 'echo "${target.label} 不支持在当前 Linux 环境中自动安装"';
    }
    return kind == LinuxRuntimeKind.builtinProot
        ? 'apk update && apk add --no-cache ${packages.join(' ')}'
        : 'pkg update -y && pkg install -y ${packages.join(' ')}';
  }

  Future<String> _workingDirectory(LinuxRuntimeKind kind) async {
    if (kind == LinuxRuntimeKind.termux) {
      return '/sdcard/pocketforge-bridge';
    }
    final support = await _supportDirectory();
    final directory = Directory(p.join(support.path, 'tool-installer'));
    await directory.create(recursive: true);
    return directory.path;
  }

  String _tail(String value) {
    const limit = 500;
    return value.length <= limit
        ? value
        : value.substring(value.length - limit);
  }
}
