import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'desktop_git_service.dart';

/// 桌面端并发 Agent 线程与 Git Worktree 隔离管理器（对齐 Zed Parallel Agents & Claude Desktop）。
class DesktopWorktreeService {
  const DesktopWorktreeService({this.git = const DesktopGitService()});
  final DesktopGitService git;

  static const String worktreeFolderName = '.nexus/worktrees';

  /// 获取指定会话隔离的 worktree 目标绝对路径。
  String worktreePathFor(String root, String conversationId) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,200}$').hasMatch(conversationId)) {
      throw ArgumentError('无效的会话标识');
    }
    return p.normalize(
        p.join(p.absolute(root), worktreeFolderName, conversationId));
  }

  /// 检查给定工作区目录是否为隔离的 worktree。
  bool isWorktreeWorkspace(String workspacePath) {
    final normalized = p.normalize(workspacePath).replaceAll('\\', '/');
    return normalized.contains('/$worktreeFolderName/');
  }

  /// 为特定会话创建隔离的 Worktree 分支与独立文件系统目录。
  Future<DesktopWorktreeInfo> ensureSessionWorktree(
    String root, {
    required String conversationId,
    String? branchName,
  }) async {
    final targetPath = worktreePathFor(root, conversationId);
    final targetDir = Directory(targetPath);
    final ownerRoot = await Directory(root).resolveSymbolicLinks();
    final parent = targetDir.parent;
    await parent.create(recursive: true);
    if (!p.isWithin(ownerRoot, await parent.resolveSymbolicLinks())) {
      throw StateError('独立工作区目录不能通过链接指向项目外部');
    }
    await git.excludeManagedWorktrees(root);

    // 若已经存在且有效，直接返回
    if (await targetDir.exists()) {
      final existing = await git.listWorktrees(root);
      final match = existing
          .where((wt) => p.equals(p.normalize(wt.path), targetPath))
          .firstOrNull;
      if (match != null) return match;
    }

    final branch = branchName ?? 'thread-$conversationId';
    return git.addWorktree(
      root,
      path: targetPath,
      branch: branch,
      newBranch: true,
    );
  }

  /// 移除会话专属的 Worktree 并修剪元数据。
  Future<void> removeSessionWorktree(
    String root, {
    required String conversationId,
    bool force = false,
  }) async {
    final targetPath = worktreePathFor(root, conversationId);
    final targetDir = Directory(targetPath);
    if (!await targetDir.exists()) return;

    await git.removeWorktree(root, path: targetPath, force: force);
    await git.pruneWorktrees(root);
  }

  /// 列出当前仓库下所有活跃的 Worktrees。
  Future<List<DesktopWorktreeInfo>> listWorktrees(String root) =>
      git.listWorktrees(root);

  Future<void> bind(
      String conversationId, String root, String workspace) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'desktop.session.workspace.$conversationId',
        jsonEncode(
            {'root': p.normalize(root), 'workspace': p.normalize(workspace)}));
  }

  Future<({String root, String workspace})?> binding(
      String conversationId) async {
    final value = (await SharedPreferences.getInstance())
        .getString('desktop.session.workspace.$conversationId');
    if (value == null) return null;
    final map = jsonDecode(value) as Map<String, dynamic>;
    return (root: map['root'] as String, workspace: map['workspace'] as String);
  }

  Future<void> unbind(String conversationId) async =>
      (await SharedPreferences.getInstance())
          .remove('desktop.session.workspace.$conversationId')
          .then((_) {});
}

final desktopWorktreeServiceProvider = Provider(
    (ref) => DesktopWorktreeService(git: ref.watch(desktopGitServiceProvider)));

final desktopWorktreeListProvider = FutureProvider.autoDispose
    .family<List<DesktopWorktreeInfo>, String>((ref, root) async {
  final service = ref.watch(desktopWorktreeServiceProvider);
  return service.listWorktrees(root);
});
