import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import 'development_verification.dart';

class ProjectArtifact {
  const ProjectArtifact({
    required this.id,
    required this.projectId,
    required this.taskId,
    required this.runId,
    required this.kind,
    required this.relativePath,
    required this.hash,
    required this.bytes,
    required this.createdAt,
    this.inspectionJson = const {},
  });

  final String id;
  final String projectId;
  final String taskId;
  final String runId;
  final String kind;
  final String relativePath;
  final String hash;
  final int bytes;
  final DateTime createdAt;
  final Map<String, dynamic> inspectionJson;

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'taskId': taskId,
        'runId': runId,
        'kind': kind,
        'relativePath': relativePath,
        'hash': hash,
        'bytes': bytes,
        'createdAt': createdAt.toIso8601String(),
        'inspectionJson': inspectionJson,
      };

  factory ProjectArtifact.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> inspection = const {};
    final raw = json['inspectionJson'];
    if (raw is Map) {
      inspection = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) inspection = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return ProjectArtifact(
      id: json['id']?.toString() ?? '',
      projectId: json['projectId']?.toString() ?? '',
      taskId: json['taskId']?.toString() ?? '',
      runId: json['runId']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'file',
      relativePath: json['relativePath']?.toString() ?? '',
      hash: json['hash']?.toString() ?? '',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      inspectionJson: inspection,
    );
  }
}

class ArtifactService {
  const ArtifactService();

  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'artifacts'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<List<ProjectArtifact>> list(
    AppDatabase db, {
    String? projectId,
    String? taskId,
  }) async {
    final rows = projectId == null
        ? await db.allArtifactRecords()
        : await db.artifactsForProject(projectId);
    return [
      for (final row in rows)
        if (taskId == null || row['taskId'] == taskId)
          ProjectArtifact.fromJson(row),
    ];
  }

  Future<ProjectArtifact> record({
    required AppDatabase db,
    required String projectId,
    required String taskId,
    required String runId,
    required String workspacePath,
    required ArtifactInspection inspection,
  }) async {
    final kind = inspection.relativePath.toLowerCase().endsWith('.apk')
        ? 'apk'
        : inspection.relativePath.toLowerCase().endsWith('.html')
            ? 'web'
            : 'file';
    final artifact = ProjectArtifact(
      id: UniqueId.generate('art'),
      projectId: projectId,
      taskId: taskId,
      runId: runId,
      kind: kind,
      relativePath: inspection.relativePath,
      hash: inspection.sha256 ?? '',
      bytes: inspection.bytes ?? 0,
      createdAt: DateTime.now(),
      inspectionJson: inspection.toJson(),
    );
    await db.saveArtifactRecord(artifact.toJson());
    try {
      final source = File(p.join(workspacePath, inspection.relativePath));
      if (await source.exists()) {
        final destDir = Directory(p.join((await _root()).path, artifact.id));
        await destDir.create(recursive: true);
        await source.copy(p.join(destDir.path, p.basename(source.path)));
      }
    } catch (_) {}
    return artifact;
  }

  static String hashBytes(List<int> bytes) => sha256.convert(bytes).toString();
}
