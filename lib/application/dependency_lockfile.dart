import 'dart:io';

import 'package:path/path.dart' as p;

import 'project_kind.dart';

class LockfileChoice {
  const LockfileChoice({
    required this.id,
    required this.label,
    required this.relativePath,
    required this.installCommand,
    this.packageManager,
  });

  final String id;
  final String label;
  final String relativePath;
  final String installCommand;
  final String? packageManager;
}

class LockfileConflict implements Exception {
  const LockfileConflict(this.choices);
  final List<LockfileChoice> choices;
  @override
  String toString() => '检测到多个锁文件，需要选择包管理器';
}

class DependencyLockfile {
  const DependencyLockfile();

  static const nodeLocks = [
    LockfileChoice(
      id: 'npm',
      label: 'npm (package-lock.json)',
      relativePath: 'package-lock.json',
      installCommand: 'npm ci',
      packageManager: 'npm',
    ),
    LockfileChoice(
      id: 'pnpm',
      label: 'pnpm (pnpm-lock.yaml)',
      relativePath: 'pnpm-lock.yaml',
      installCommand: 'pnpm install --frozen-lockfile',
      packageManager: 'pnpm',
    ),
    LockfileChoice(
      id: 'yarn',
      label: 'yarn (yarn.lock)',
      relativePath: 'yarn.lock',
      installCommand: 'yarn install --frozen-lockfile',
      packageManager: 'yarn',
    ),
  ];

  static const pythonLocks = [
    LockfileChoice(
      id: 'pip',
      label: 'pip (requirements.txt)',
      relativePath: 'requirements.txt',
      installCommand: 'python -m pip install -r requirements.txt',
      packageManager: 'pip',
    ),
    LockfileChoice(
      id: 'poetry',
      label: 'poetry (poetry.lock)',
      relativePath: 'poetry.lock',
      installCommand: 'poetry install --no-root',
      packageManager: 'poetry',
    ),
  ];

  List<LockfileChoice> present(String workspacePath, ProjectKind kind) {
    final candidates = switch (kind) {
      ProjectKind.node => nodeLocks,
      ProjectKind.python => pythonLocks,
      _ => const <LockfileChoice>[],
    };
    return [
      for (final item in candidates)
        if (File(p.join(workspacePath, item.relativePath)).existsSync()) item,
    ];
  }

  LockfileChoice? resolve({
    required String workspacePath,
    required ProjectKind kind,
    String? selectedId,
  }) {
    final found = present(workspacePath, kind);
    if (found.isEmpty) return null;
    if (found.length == 1) return found.single;
    if (selectedId != null) {
      for (final item in found) {
        if (item.id == selectedId) return item;
      }
    }
    throw LockfileConflict(found);
  }
}
