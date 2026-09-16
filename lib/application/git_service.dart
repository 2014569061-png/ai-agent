import 'dart:convert';
import 'dart:io';

import '../infrastructure/tools/command_tool.dart';

class GitStatusEntry {
  const GitStatusEntry({
    required this.path,
    required this.indexStatus,
    required this.workTreeStatus,
  });

  final String path;
  final String indexStatus;
  final String workTreeStatus;

  bool get staged => indexStatus.trim().isNotEmpty && indexStatus != ' ';
  bool get unstaged => workTreeStatus.trim().isNotEmpty && workTreeStatus != ' ';
}

class GitService {
  GitService({TerminalCommandService? terminal, String workspacePath = '.'})
      : _terminal = terminal ??
            TerminalCommandService(workspacePath: workspacePath);

  final TerminalCommandService _terminal;

  Future<CommandResult> clone({
    required String url,
    required String destination,
    String? credentialRef,
  }) {
    if (credentialRef != null && credentialRef.isNotEmpty) {
      // 凭据只通过安全存储引用传入运行时环境，禁止拼进命令或日志。
    }
    return _run(['clone', url, destination], cwd: Directory.current.path);
  }

  Future<List<GitStatusEntry>> status(String workspacePath) async {
    final result = await _run(['status', '--porcelain=v1', '-z'],
        cwd: workspacePath);
    if (result.exitCode != 0) {
      throw StateError(result.output);
    }
    return parsePorcelain(result.output);
  }

  Future<String> diff(String workspacePath, {List<String> paths = const []}) async {
    final result = await _run(['diff', '--', ...paths], cwd: workspacePath);
    return result.output;
  }

  Future<List<String>> branches(String workspacePath) async {
    final result = await _run(['branch', '--list', '--format=%(refname:short)'],
        cwd: workspacePath);
    return const LineSplitter()
        .convert(result.output)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  Future<CommandResult> checkout(
    String workspacePath,
    String branch, {
    bool create = false,
    bool force = false,
  }) {
    if (force) {
      throw StateError('拒绝默认 hard reset / 强制切换');
    }
    return _run(
      create ? ['checkout', '-b', branch] : ['checkout', branch],
      cwd: workspacePath,
    );
  }

  Future<CommandResult> stage(String workspacePath, List<String> paths) {
    if (paths.isEmpty) {
      throw ArgumentError('提交前必须显式选择文件，不能自动暂存全部改动');
    }
    return _run(['add', '--', ...paths], cwd: workspacePath);
  }

  Future<CommandResult> commit(String workspacePath, String message) {
    return _run(['commit', '-m', message], cwd: workspacePath);
  }

  Future<CommandResult> fetch(String workspacePath) =>
      _run(['fetch', '--prune'], cwd: workspacePath);

  Future<CommandResult> push(String workspacePath, {String? remote, String? branch}) {
    return _run([
      'push',
      if (remote != null) remote,
      if (branch != null) branch,
    ], cwd: workspacePath);
  }

  Future<CommandResult> _run(List<String> args, {required String cwd}) {
    final escaped = args
        .map((arg) => arg.contains(RegExp(r'[\s"]')) ? '"${arg.replaceAll('"', '\\"')}"' : arg)
        .join(' ');
    return _terminal.run('git $escaped', workingDirectory: cwd);
  }

  List<GitStatusEntry> parsePorcelain(String stdout) {
    final entries = <GitStatusEntry>[];
    for (final raw in stdout.split('\x00')) {
      if (raw.trim().isEmpty) continue;
      if (raw.length < 3) continue;
      entries.add(GitStatusEntry(
        path: raw.substring(3),
        indexStatus: raw.substring(0, 1),
        workTreeStatus: raw.substring(1, 2),
      ));
    }
    return entries;
  }
}
