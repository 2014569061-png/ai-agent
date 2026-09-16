import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/unique_id.dart';
import '../infrastructure/tools/workspace_tools.dart';
import 'change_review.dart';

class ChangeSetFile {
  const ChangeSetFile({
    required this.relativePath,
    required this.operation,
    required this.beforeHash,
    required this.afterHash,
    this.beforeRef,
    this.afterRef,
    this.reversible = true,
  });

  final String relativePath;
  final String operation;
  final String beforeHash;
  final String afterHash;
  final String? beforeRef;
  final String? afterRef;
  final bool reversible;

  Map<String, dynamic> toJson() => {
        'relativePath': relativePath,
        'operation': operation,
        'beforeHash': beforeHash,
        'afterHash': afterHash,
        if (beforeRef != null) 'beforeRef': beforeRef,
        if (afterRef != null) 'afterRef': afterRef,
        'reversible': reversible,
      };

  factory ChangeSetFile.fromJson(Map<String, dynamic> json) => ChangeSetFile(
        relativePath: json['relativePath']?.toString() ?? '',
        operation: json['operation']?.toString() ?? 'edit',
        beforeHash: json['beforeHash']?.toString() ?? '',
        afterHash: json['afterHash']?.toString() ?? '',
        beforeRef: json['beforeRef']?.toString(),
        afterRef: json['afterRef']?.toString(),
        reversible: json['reversible'] != false,
      );
}

class ChangeSet {
  const ChangeSet({
    required this.id,
    required this.taskId,
    required this.projectId,
    required this.files,
    required this.createdAt,
  });

  final String id;
  final String taskId;
  final String projectId;
  final List<ChangeSetFile> files;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'projectId': projectId,
        'files': files.map((file) => file.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChangeSet.fromJson(Map<String, dynamic> json) => ChangeSet(
        id: json['id']?.toString() ?? '',
        taskId: json['taskId']?.toString() ?? '',
        projectId: json['projectId']?.toString() ?? '',
        files: (json['files'] as List? ?? const [])
            .whereType<Map>()
            .map((item) =>
                ChangeSetFile.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class RollbackConflict {
  const RollbackConflict({required this.path, required this.reason});
  final String path;
  final String reason;
}

class ChangeSetService {
  const ChangeSetService();

  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'changesets'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<ChangeSet> capture({
    required String projectId,
    required String taskId,
    required String workspacePath,
    required ChangeReview review,
  }) async {
    final sandbox = WorkspaceSandbox(workspacePath);
    final files = <ChangeSetFile>[];
    final objectDir = Directory(p.join((await _root()).path, taskId));
    await objectDir.create(recursive: true);
    for (final change in review.files) {
      final current = File(sandbox.resolvePath(change.path));
      String afterHash = '';
      String? afterRef;
      var reversible = true;
      try {
        if (await current.exists()) {
          final bytes = await current.readAsBytes();
          afterHash = sha256.convert(bytes).toString();
          afterRef = p.join(objectDir.path, '${change.path.replaceAll('/', '_')}.after');
          await File(afterRef).writeAsBytes(bytes, flush: true);
        }
      } catch (_) {
        reversible = false;
      }
      files.add(ChangeSetFile(
        relativePath: change.path,
        operation: change.operation,
        beforeHash: '',
        afterHash: afterHash,
        afterRef: afterRef,
        reversible: reversible && change.operation != 'binary',
      ));
    }
    final set = ChangeSet(
      id: UniqueId.generate('cs'),
      taskId: taskId,
      projectId: projectId,
      files: files,
      createdAt: DateTime.now(),
    );
    await File(p.join(objectDir.path, 'changeset.json'))
        .writeAsString(jsonEncode(set.toJson()), flush: true);
    return set;
  }

  Future<List<RollbackConflict>> rollback({
    required String workspacePath,
    required ChangeSet changeSet,
    required Map<String, String> currentHashes,
  }) async {
    final conflicts = <RollbackConflict>[];
    final sandbox = WorkspaceSandbox(workspacePath);
    final journal = <String>[];
    for (final file in changeSet.files) {
      if (!file.reversible) {
        conflicts.add(RollbackConflict(path: file.relativePath, reason: '不可自动回退'));
        continue;
      }
      final currentHash = currentHashes[file.relativePath];
      if (currentHash != null &&
          file.afterHash.isNotEmpty &&
          currentHash != file.afterHash) {
        conflicts.add(RollbackConflict(
          path: file.relativePath,
          reason: '人工后续修改，拒绝静默覆盖',
        ));
        continue;
      }
      final target = File(sandbox.resolvePath(file.relativePath));
      try {
        if (file.operation == 'create' || file.operation == 'write') {
          if (await target.exists()) await target.delete();
          journal.add('deleted:${file.relativePath}');
        } else if (file.beforeRef != null) {
          await File(file.beforeRef!).copy(target.path);
          journal.add('restored:${file.relativePath}');
        }
      } catch (error) {
        conflicts.add(RollbackConflict(
          path: file.relativePath,
          reason: '回退中断：$error；已处理 ${journal.join(', ')}',
        ));
        break;
      }
    }
    return conflicts;
  }
}
