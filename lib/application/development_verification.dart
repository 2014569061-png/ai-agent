import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../infrastructure/tools/command_tool.dart';
import '../infrastructure/tools/workspace_tools.dart';
import 'project_kind.dart';
import 'project_kind_detector.dart';

enum VerificationStepStatus {
  pending,
  running,
  passed,
  failed,
  skipped,
}

extension VerificationStepStatusX on VerificationStepStatus {
  String get id => name;

  String get label => switch (this) {
        VerificationStepStatus.pending => '等待',
        VerificationStepStatus.running => '执行中',
        VerificationStepStatus.passed => '通过',
        VerificationStepStatus.failed => '失败',
        VerificationStepStatus.skipped => '跳过',
      };

  static VerificationStepStatus parse(String? value) =>
      VerificationStepStatus.values.firstWhere(
        (item) => item.name == value,
        orElse: () => VerificationStepStatus.pending,
      );
}

class VerificationStep {
  const VerificationStep({
    required this.id,
    required this.title,
    required this.command,
    this.kind = 'command',
    this.required = true,
    this.timeout = const Duration(minutes: 10),
    this.expectedArtifactPath,
    this.status = VerificationStepStatus.pending,
    this.output = '',
    this.exitCode,
    this.startedAt,
    this.finishedAt,
    this.error,
  });

  final String id;
  final String title;
  final String command;
  final String kind;
  final bool required;
  final Duration timeout;
  final String? expectedArtifactPath;
  final VerificationStepStatus status;
  final String output;
  final int? exitCode;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? error;

  bool get canRetry =>
      status == VerificationStepStatus.failed ||
      status == VerificationStepStatus.skipped;

  VerificationStep copyWith({
    VerificationStepStatus? status,
    String? output,
    int? exitCode,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? error,
    bool clearError = false,
  }) {
    return VerificationStep(
      id: id,
      title: title,
      command: command,
      kind: kind,
      required: required,
      timeout: timeout,
      expectedArtifactPath: expectedArtifactPath,
      status: status ?? this.status,
      output: output ?? this.output,
      exitCode: exitCode ?? this.exitCode,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      error: clearError ? null : (error ?? this.error),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'command': command,
        'kind': kind,
        'required': required,
        'timeoutSeconds': timeout.inSeconds,
        if (expectedArtifactPath != null)
          'expectedArtifactPath': expectedArtifactPath,
        'status': status.id,
        'output': output,
        if (exitCode != null) 'exitCode': exitCode,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        if (error != null) 'error': error,
      };

  factory VerificationStep.fromJson(Map<String, dynamic> json) {
    return VerificationStep(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      command: json['command']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'command',
      required: json['required'] as bool? ?? true,
      timeout: Duration(
          seconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 600),
      expectedArtifactPath: json['expectedArtifactPath']?.toString(),
      status: VerificationStepStatusX.parse(json['status']?.toString()),
      output: json['output']?.toString() ?? '',
      exitCode: (json['exitCode'] as num?)?.toInt(),
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
      finishedAt: DateTime.tryParse(json['finishedAt']?.toString() ?? ''),
      error: json['error']?.toString(),
    );
  }
}

class ArtifactInspection {
  const ArtifactInspection({
    required this.relativePath,
    required this.exists,
    this.validFormat,
    this.absolutePath,
    this.bytes,
    this.sha256,
    this.packageName,
    this.signed,
    this.notes = const [],
  });

  final String relativePath;
  final bool exists;
  final String? absolutePath;
  final int? bytes;
  final String? sha256;
  final String? packageName;
  final bool? validFormat;
  final bool? signed;
  final List<String> notes;

  bool get isValid {
    if (!exists) return false;
    if (relativePath.toLowerCase().endsWith('.apk')) {
      return validFormat == true;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'relativePath': relativePath,
        'exists': exists,
        if (validFormat != null) 'validFormat': validFormat,
        if (absolutePath != null) 'absolutePath': absolutePath,
        if (bytes != null) 'bytes': bytes,
        if (sha256 != null) 'sha256': sha256,
        if (packageName != null) 'packageName': packageName,
        if (signed != null) 'signed': signed,
        'notes': notes,
      };

  factory ArtifactInspection.fromJson(Map<String, dynamic> json) {
    return ArtifactInspection(
      relativePath: json['relativePath']?.toString() ?? '',
      exists: json['exists'] as bool? ?? false,
      validFormat: json['validFormat'] as bool?,
      absolutePath: json['absolutePath']?.toString(),
      bytes: (json['bytes'] as num?)?.toInt(),
      sha256: json['sha256']?.toString(),
      packageName: json['packageName']?.toString(),
      signed: json['signed'] as bool?,
      notes: (json['notes'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}

class DevelopmentVerificationPlan {
  const DevelopmentVerificationPlan({
    required this.project,
    required this.steps,
    this.primaryArtifactPath,
  });

  final ProjectKindDetection project;
  final List<VerificationStep> steps;
  final String? primaryArtifactPath;

  Map<String, dynamic> toJson() => {
        'project': project.toJson(),
        'steps': steps.map((step) => step.toJson()).toList(),
        if (primaryArtifactPath != null)
          'primaryArtifactPath': primaryArtifactPath,
      };

  factory DevelopmentVerificationPlan.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as List? ?? const [];
    return DevelopmentVerificationPlan(
      project: json['project'] is Map
          ? ProjectKindDetection.fromJson(
              Map<String, dynamic>.from(json['project'] as Map))
          : const ProjectKindDetection(
              kind: ProjectKind.unknown, confidence: 0, signals: []),
      steps: rawSteps
          .whereType<Map>()
          .map((item) =>
              VerificationStep.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      primaryArtifactPath: json['primaryArtifactPath']?.toString(),
    );
  }
}

class DevelopmentVerificationResult {
  const DevelopmentVerificationResult({
    required this.plan,
    required this.success,
    this.artifact,
  });

  final DevelopmentVerificationPlan plan;
  final bool success;
  final ArtifactInspection? artifact;
}

/// Builds project-aware analyze/test/build steps and verifies real artifacts.
class DevelopmentVerificationService {
  DevelopmentVerificationService({
    ProjectKindDetector detector = const ProjectKindDetector(),
    ArtifactInspector inspector = const ArtifactInspector(),
  })  : _detector = detector,
        _inspector = inspector;

  final ProjectKindDetector _detector;
  final ArtifactInspector _inspector;

  String _gradleCommand(String? configured, String task) {
    final value = configured?.trim();
    if (value == null || value.isEmpty) return 'gradlew $task';
    return value
        .replaceFirst(RegExp(r'^\./gradlew\b'), 'gradlew')
        .replaceFirst(RegExp(r'^gradlew\.bat\b', caseSensitive: false), 'gradlew');
  }

  Future<DevelopmentVerificationPlan> planFor(
    String workspacePath, {
    bool includeBuild = true,
  }) async {
    final project = await _detector.detect(workspacePath);
    return planFromDetection(project, includeBuild: includeBuild);
  }

  DevelopmentVerificationPlan planFromDetection(
    ProjectKindDetection project, {
    bool includeBuild = true,
  }) {
    final steps = switch (project.kind) {
      ProjectKind.flutter => [
          const VerificationStep(
            id: 'analyze',
            title: '静态分析',
            command: 'flutter analyze',
          ),
          const VerificationStep(
            id: 'test',
            title: '运行测试',
            command: 'flutter test',
          ),
          if (includeBuild) ...[
            const VerificationStep(
              id: 'build',
              title: '构建 APK',
              command: 'flutter build apk --release',
              timeout: Duration(minutes: 20),
              expectedArtifactPath:
                  'build/app/outputs/flutter-apk/app-release.apk',
            ),
            const VerificationStep(
              id: 'artifact',
              title: '检查构建产物',
              command: '',
              kind: 'artifact',
              expectedArtifactPath:
                  'build/app/outputs/flutter-apk/app-release.apk',
            ),
          ],
        ],
      ProjectKind.androidGradle => [
          VerificationStep(
            id: 'test',
            title: 'Gradle 测试',
            command: _gradleCommand(project.testCommand, 'test'),
          ),
          if (includeBuild) ...[
            VerificationStep(
              id: 'build',
              title: 'Gradle 构建',
              command:
                  _gradleCommand(project.buildCommand, 'assembleRelease'),
              timeout: const Duration(minutes: 20),
              expectedArtifactPath:
                  'app/build/outputs/apk/release/app-release.apk',
            ),
            const VerificationStep(
              id: 'artifact',
              title: '检查构建产物',
              command: '',
              kind: 'artifact',
              expectedArtifactPath:
                  'app/build/outputs/apk/release/app-release.apk',
            ),
          ],
        ],
      ProjectKind.node => [
          if (project.testCommand != null)
            VerificationStep(
              id: 'test',
              title: '运行测试',
              command: project.testCommand!,
            ),
          if (includeBuild && project.buildCommand != null)
            VerificationStep(
              id: 'build',
              title: '构建项目',
              command: project.buildCommand!,
            ),
          if (project.testCommand == null &&
              (!includeBuild || project.buildCommand == null))
            const VerificationStep(
              id: 'inspect',
              title: '检查 Node 清单',
              command: '',
              kind: 'inspect',
              required: false,
            ),
        ],
      ProjectKind.python => [
          VerificationStep(
            id: 'test',
            title: '运行测试',
            command: project.testCommand ?? 'python -m pytest',
          ),
        ],
      ProjectKind.go => [
          const VerificationStep(
            id: 'test',
            title: 'Go 测试',
            command: 'go test ./...',
          ),
          if (includeBuild) ...[
            const VerificationStep(
              id: 'build',
              title: 'Go 构建',
              command: 'go build -o dist/app ./...',
              expectedArtifactPath: 'dist/app',
            ),
            const VerificationStep(
              id: 'artifact',
              title: '检查构建产物',
              command: '',
              kind: 'artifact',
              expectedArtifactPath: 'dist/app',
            ),
          ],
        ],
      ProjectKind.staticWeb => [
          const VerificationStep(
            id: 'artifact',
            title: '检查网页入口',
            command: '',
            kind: 'artifact',
            expectedArtifactPath: 'index.html',
          ),
        ],
      ProjectKind.javaApk => [
          if (includeBuild) ...[
            VerificationStep(
              id: 'build',
              title: '构建 APK',
              command: project.buildCommand ?? 'sh build.sh',
              timeout: const Duration(minutes: 20),
              expectedArtifactPath: 'dist/app-debug.apk',
            ),
            const VerificationStep(
              id: 'artifact',
              title: '检查 APK 产物',
              command: '',
              kind: 'artifact',
              expectedArtifactPath: 'dist/app-debug.apk',
            ),
          ] else
            const VerificationStep(
              id: 'artifact',
              title: '检查 APK 产物',
              command: '',
              kind: 'artifact',
              expectedArtifactPath: 'dist/app-debug.apk',
            ),
        ],
      ProjectKind.unknown => const [
          VerificationStep(
            id: 'inspect',
            title: '识别项目类型',
            command: '',
            kind: 'inspect',
            required: false,
          ),
        ],
    };
    String? artifactPath;
    for (final step in steps) {
      final path = step.expectedArtifactPath;
      if (path != null && path.isNotEmpty) artifactPath = path;
    }
    return DevelopmentVerificationPlan(
      project: project,
      steps: steps,
      primaryArtifactPath: artifactPath,
    );
  }

  Future<DevelopmentVerificationResult> run({
    required TerminalCommandService service,
    required String workspacePath,
    DevelopmentVerificationPlan? plan,
    String? retryStepId,
  }) async {
    var current = plan ??
        await planFor(workspacePath, includeBuild: retryStepId == null);
    final session = await service.openSession(workingDirectory: workspacePath);
    ArtifactInspection? artifact;
    try {
      final startIndex = retryStepId == null
          ? 0
          : current.steps.indexWhere((step) => step.id == retryStepId);
      if (startIndex < 0) {
        return DevelopmentVerificationResult(plan: current, success: false);
      }
      for (var i = 0; i < current.steps.length; i++) {
        if (i < startIndex &&
            current.steps[i].status == VerificationStepStatus.passed) {
          continue;
        }
        if (retryStepId != null && i < startIndex) continue;
        current = _replaceStep(
          current,
          current.steps[i].copyWith(
            status: VerificationStepStatus.running,
            startedAt: DateTime.now(),
            clearError: true,
          ),
        );
        final step = current.steps[i];
        if (step.kind == 'artifact' || step.kind == 'inspect') {
          if (step.expectedArtifactPath == null ||
              step.expectedArtifactPath!.isEmpty) {
            current = _replaceStep(
              current,
              step.copyWith(
                status: step.required
                    ? VerificationStepStatus.failed
                    : VerificationStepStatus.skipped,
                finishedAt: DateTime.now(),
                error: step.required ? '未声明可检查产物' : '无可执行验证命令，已跳过',
              ),
            );
            if (step.required) {
              return DevelopmentVerificationResult(
                plan: current,
                success: false,
                artifact: artifact,
              );
            }
            continue;
          }
          artifact = await _inspector.inspect(
            workspacePath: workspacePath,
            relativePath: step.expectedArtifactPath!,
            expectedPackageName: current.project.packageName,
          );
          current = _replaceStep(
            current,
            step.copyWith(
              status: artifact.isValid
                  ? VerificationStepStatus.passed
                  : VerificationStepStatus.failed,
              output: jsonEncode(artifact.toJson()),
              finishedAt: DateTime.now(),
              error: artifact.isValid
                  ? null
                  : (artifact.exists
                      ? (artifact.notes.isNotEmpty
                          ? artifact.notes.join('；')
                          : '产物无效：${step.expectedArtifactPath}')
                      : '产物不存在：${step.expectedArtifactPath}'),
            ),
          );
          if (!artifact.isValid && step.required) {
            return DevelopmentVerificationResult(
              plan: current,
              success: false,
              artifact: artifact,
            );
          }
          continue;
        }

        final execution = await service.executeSession(
          sessionId: session.id,
          command: step.command,
          timeout: step.timeout,
        );
        final output = execution.data?['output']?.toString() ?? execution.message;
        final ok = execution.ok;
        current = _replaceStep(
          current,
          step.copyWith(
            status: ok
                ? VerificationStepStatus.passed
                : VerificationStepStatus.failed,
            output: output,
            exitCode: (execution.data?['exitCode'] as num?)?.toInt(),
            finishedAt: DateTime.now(),
            error: ok ? null : execution.message,
          ),
        );
        if (!ok) {
          return DevelopmentVerificationResult(
            plan: current,
            success: false,
            artifact: artifact,
          );
        }
      }
      if (current.primaryArtifactPath != null) {
        artifact ??= await _inspector.inspect(
          workspacePath: workspacePath,
          relativePath: current.primaryArtifactPath!,
          expectedPackageName: current.project.packageName,
        );
      }
      final requiredSteps =
          current.steps.where((step) => step.required).toList();
      final executed = current.steps
          .where((step) =>
              step.status == VerificationStepStatus.passed ||
              step.status == VerificationStepStatus.failed)
          .toList();
      final success = requiredSteps.isNotEmpty &&
          executed.isNotEmpty &&
          requiredSteps
              .every((step) => step.status == VerificationStepStatus.passed);
      return DevelopmentVerificationResult(
        plan: current,
        success: success,
        artifact: artifact,
      );
    } finally {
      await service.closeSession(session.id);
    }
  }

  DevelopmentVerificationPlan _replaceStep(
      DevelopmentVerificationPlan plan, VerificationStep updated) {
    return DevelopmentVerificationPlan(
      project: plan.project,
      primaryArtifactPath: plan.primaryArtifactPath,
      steps: [
        for (final step in plan.steps)
          if (step.id == updated.id) updated else step,
      ],
    );
  }
}

class ArtifactInspector {
  const ArtifactInspector();

  Future<ArtifactInspection> inspect({
    required String workspacePath,
    required String relativePath,
    String? expectedPackageName,
  }) async {
    final notes = <String>[];
    final String fullPath;
    try {
      fullPath = WorkspaceSandbox(workspacePath).resolvePath(relativePath);
    } on ArgumentError {
      return ArtifactInspection(
        relativePath: relativePath,
        exists: false,
        notes: const ['产物路径越出工作区'],
      );
    }
    final file = File(fullPath);
    if (!await file.exists()) {
      return ArtifactInspection(
        relativePath: relativePath,
        exists: false,
        absolutePath: fullPath,
        notes: const ['文件不存在'],
      );
    }
    final bytes = await file.length();
    final digest = sha256.convert(await file.readAsBytes()).toString();
    bool? signed;
    if (relativePath.toLowerCase().endsWith('.apk')) {
      final header = await file.openRead(0, 4).fold<List<int>>(
            <int>[],
            (previous, element) => previous..addAll(element),
          );
      final isZip = header.length >= 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4B &&
          (header[2] == 0x03 || header[2] == 0x05 || header[2] == 0x07) &&
          (header[3] == 0x04 || header[3] == 0x06 || header[3] == 0x08);
      if (!isZip) {
        notes.add('APK 文件头不是 ZIP，可能不是有效安装包');
      } else {
        notes.add('APK 文件头有效');
      }
      if (expectedPackageName != null && expectedPackageName.isNotEmpty) {
        notes.add('期望包名：$expectedPackageName（未解析真实包名，包名保持未知）');
      }
      final idsig =
          await File(p.join(p.dirname(fullPath), 'app-release.apk.idsig'))
              .exists();
      if (idsig) {
        signed = true;
        notes.add('发现 APK Signature Scheme v4 签名文件');
      } else {
        signed = null;
        notes.add('签名状态未知，不能仅凭文件体积判定已签名');
      }
      return ArtifactInspection(
        relativePath: relativePath,
        exists: true,
        validFormat: isZip,
        absolutePath: fullPath,
        bytes: bytes,
        sha256: digest,
        // 这里只校验了 ZIP 文件头，没有解析 AndroidManifest。把调用方传入的
        // 期望值写进 packageName 会让下游（产物记录、详情页「包名：…」）把
        // 一个未经解析的猜测当成已验证事实，因此保持未知，期望值只留在 notes。
        packageName: null,
        signed: signed,
        notes: notes,
      );
    }
    return ArtifactInspection(
      relativePath: relativePath,
      exists: true,
      validFormat: true,
      absolutePath: fullPath,
      bytes: bytes,
      sha256: digest,
      // 非 APK 产物同样不解析清单，包名一律保持未知。
      packageName: null,
      signed: signed,
      notes: notes,
    );
  }
}
