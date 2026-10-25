import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/unique_id.dart';
import '../domain/result_card.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/database/result_action_store.dart';
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
      } catch (_) {
        // inspectionJson 损坏时退化为空 inspection。这是「解析失败的兜底」而
        // 不是错误吞没：制品记录本身仍能恢复出来，只是少了检查元数据。
      }
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
  const ArtifactService({this.rootDirectory});

  final Future<Directory> Function()? rootDirectory;

  Future<Directory> _root() async {
    if (rootDirectory != null) {
      final dir = await rootDirectory!();
      await dir.create(recursive: true);
      return dir;
    }
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

  /// Only publish a record after its private payload has been copied and hashed.
  /// Empty projectId is the backwards-compatible non-project scope, not a project.
  Future<ProjectArtifact> record({
    required AppDatabase db,
    String projectId = '',
    required String taskId,
    required String runId,
    required String workspacePath,
    required ArtifactInspection inspection,
  }) async {
    _validateRelativePath(inspection.relativePath);
    if (!inspection.exists) {
      throw StateError('Inspection reports missing payload');
    }
    final workspace = await Directory(workspacePath).resolveSymbolicLinks();
    final resolved = await File(p.join(workspace, inspection.relativePath))
        .resolveSymbolicLinks();
    if (!p.isWithin(workspace, resolved)) {
      throw ArgumentError('Artifact escapes workspace');
    }
    final source = File(resolved);
    final id = UniqueId.generate('art');
    final destination = Directory(p.join((await _root()).path, id));
    if (await destination.exists()) throw StateError('Artifact ID collision');
    await destination.create();
    try {
      final copied = await source
          .copy(p.join(destination.path, p.basename(inspection.relativePath)));
      final length = await copied.length();
      final digest = (await sha256.bind(copied.openRead()).first).toString();
      if ((inspection.bytes != null && inspection.bytes != length) ||
          (inspection.sha256 != null &&
              inspection.sha256!.isNotEmpty &&
              inspection.sha256!.toLowerCase() != digest)) {
        throw StateError('Payload changed since inspection');
      }
      final extension = p.extension(inspection.relativePath).toLowerCase();
      final artifact = ProjectArtifact(
        id: id,
        projectId: projectId,
        taskId: taskId,
        runId: runId,
        kind: extension == '.apk'
            ? 'apk'
            : extension == '.html'
                ? 'web'
                : const ['.png', '.jpg', '.jpeg', '.gif', '.webp']
                        .contains(extension)
                    ? 'image'
                    : const ['.txt', '.md', '.json', '.csv'].contains(extension)
                        ? 'text'
                        : 'file',
        relativePath: inspection.relativePath,
        hash: digest,
        bytes: length,
        createdAt: DateTime.now().toUtc(),
        inspectionJson: {
          ...inspection.toJson(),
          'payload': {
            'state': 'verified_copy',
            'sha256': digest,
            'bytes': length,
            'note':
                'Copy integrity only; not task, format, signature or safety verification',
          }
        },
      );
      // A published file also gets a real result card, not only debug seed data.
      // Both records commit together; failure removes only this new private copy.
      await db.transaction(() async {
        await db.saveArtifactRecord(artifact.toJson());
        await SqlResultActionRepository(db).saveCard(ResultCard(
          id: 'artifact-${artifact.id}',
          kind: ResultCardKind.file,
          resourceType: 'artifact',
          resourceId: artifact.id,
          resourceVersion: 1,
          title: p.basename(artifact.relativePath),
          summary: '已保存文件副本 · ${artifact.bytes} 字节；不代表任务验证通过',
          taskId: artifact.taskId,
          turnId: artifact.runId,
          createdAt: artifact.createdAt,
          updatedAt: artifact.createdAt,
        ));
      });
      return artifact;
    } catch (_) {
      // Only this operation's unique directory can be removed. Never remove the
      // workspace source, an earlier version, or a shared artifact directory.
      if (await destination.exists()) await destination.delete(recursive: true);
      rethrow;
    }
  }

  static void _validateRelativePath(String value) {
    if (value.isEmpty ||
        p.isAbsolute(value) ||
        value.contains('\\') ||
        value.contains(':') ||
        value.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw ArgumentError.value(
          value, 'relativePath', 'Portable relative file path required');
    }
  }

  Future<ArtifactPayload> inspectPayload(ProjectArtifact artifact) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(artifact.id)) {
      return const ArtifactPayload(ArtifactPayloadState.invalid);
    }
    try {
      _validateRelativePath(artifact.relativePath);
    } on ArgumentError {
      return const ArtifactPayload(ArtifactPayloadState.invalid);
    }
    final root = await _root();
    final file =
        File(p.join(root.path, artifact.id, p.basename(artifact.relativePath)));
    if (!await file.exists()) {
      return const ArtifactPayload(ArtifactPayloadState.missing);
    }
    final resolvedRoot = await root.resolveSymbolicLinks();
    final resolvedFile = await file.resolveSymbolicLinks();
    if (!p.isWithin(resolvedRoot, resolvedFile)) {
      return const ArtifactPayload(ArtifactPayloadState.invalid);
    }
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(artifact.hash)) {
      return const ArtifactPayload(ArtifactPayloadState.unverified);
    }
    final before = await file.stat();
    final digest = (await sha256.bind(file.openRead()).first).toString();
    final after = await file.stat();
    if (before.size != after.size ||
        before.modified != after.modified ||
        after.size != artifact.bytes ||
        digest != artifact.hash.toLowerCase()) {
      return const ArtifactPayload(ArtifactPayloadState.changed);
    }
    return ArtifactPayload(ArtifactPayloadState.intact, file: file);
  }

  Future<File> verifiedPayload(ProjectArtifact artifact) async {
    final payload = await inspectPayload(artifact);
    if (payload.state != ArtifactPayloadState.intact || payload.file == null) {
      throw StateError('Artifact payload unavailable: ${payload.state.name}');
    }
    return payload.file!;
  }

  static String hashBytes(List<int> bytes) => sha256.convert(bytes).toString();
}

enum ArtifactPayloadState { intact, missing, changed, unverified, invalid }

class ArtifactPayload {
  const ArtifactPayload(this.state, {this.file});
  final ArtifactPayloadState state;
  final File? file;
}
