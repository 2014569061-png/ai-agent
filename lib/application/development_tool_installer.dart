import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../infrastructure/terminal/linux_runtime.dart';
import '../infrastructure/terminal/linux_runtime_factory.dart';

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

    final command = selected.kind == LinuxRuntimeKind.builtinProot
        ? alpineCommand
        : termuxCommand;
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
        message: selected.kind == LinuxRuntimeKind.builtinProot
            ? '常用工具已安装到内置 Alpine。'
            : '常用工具已安装到 Termux。',
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
