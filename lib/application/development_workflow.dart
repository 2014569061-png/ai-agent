import '../infrastructure/tools/command_tool.dart';
import 'development_verification.dart';
import 'project_kind.dart';
import 'project_kind_detector.dart';

class DevelopmentWorkflowStep {
  const DevelopmentWorkflowStep({
    required this.id,
    required this.command,
    this.title,
    this.kind = 'command',
    this.timeout = const Duration(minutes: 10),
    this.expectedArtifactPath,
  });

  final String id;
  final String command;
  final String? title;
  final String kind;
  final Duration timeout;
  final String? expectedArtifactPath;
}

class DevelopmentWorkflow {
  const DevelopmentWorkflow({
    required this.id,
    required this.name,
    required this.steps,
    this.artifactPath,
    this.checksum = true,
    this.projectKind,
  });

  final String id;
  final String name;
  final List<DevelopmentWorkflowStep> steps;
  final String? artifactPath;
  final bool checksum;
  final ProjectKind? projectKind;
}

class DevelopmentWorkflowTemplates {
  static const flutterApk = DevelopmentWorkflow(
    id: 'flutter-verify-apk',
    name: 'Flutter 分析 / 测试 / 构建',
    projectKind: ProjectKind.flutter,
    steps: [
      DevelopmentWorkflowStep(id: 'analyze', command: 'flutter analyze'),
      DevelopmentWorkflowStep(id: 'test', command: 'flutter test'),
      DevelopmentWorkflowStep(
        id: 'build',
        command: 'flutter build apk --release',
        timeout: Duration(minutes: 20),
        expectedArtifactPath: 'build/app/outputs/flutter-apk/app-release.apk',
      ),
    ],
    artifactPath: 'build/app/outputs/flutter-apk/app-release.apk',
  );

  static const androidGradle = DevelopmentWorkflow(
    id: 'android-gradle-verify',
    name: 'Android Gradle 测试 / 构建',
    projectKind: ProjectKind.androidGradle,
    steps: [
      DevelopmentWorkflowStep(id: 'test', command: 'gradlew test'),
      DevelopmentWorkflowStep(
        id: 'build',
        command: 'gradlew assembleRelease',
        timeout: Duration(minutes: 20),
        expectedArtifactPath: 'app/build/outputs/apk/release/app-release.apk',
      ),
    ],
    artifactPath: 'app/build/outputs/apk/release/app-release.apk',
  );

  static const nodeVerify = DevelopmentWorkflow(
    id: 'node-verify',
    name: 'Node 测试 / 构建',
    projectKind: ProjectKind.node,
    steps: [
      DevelopmentWorkflowStep(id: 'test', command: 'npm test'),
      DevelopmentWorkflowStep(id: 'build', command: 'npm run build'),
    ],
  );

  static const pythonTest = DevelopmentWorkflow(
    id: 'python-test',
    name: 'Python 测试',
    projectKind: ProjectKind.python,
    steps: [
      DevelopmentWorkflowStep(id: 'test', command: 'python -m pytest'),
    ],
  );

  static const goArm64 = DevelopmentWorkflow(
    id: 'go-build-arm64',
    name: 'Go ARM64 构建',
    projectKind: ProjectKind.go,
    steps: [
      DevelopmentWorkflowStep(
        id: 'test',
        command: 'go test ./...',
      ),
      DevelopmentWorkflowStep(
        id: 'build',
        command: 'GOOS=linux GOARCH=arm64 go build -o dist/app ./...',
        expectedArtifactPath: 'dist/app',
      ),
    ],
    artifactPath: 'dist/app',
  );

  static const staticWeb = DevelopmentWorkflow(
    id: 'static-web-check',
    name: '静态网页检查',
    projectKind: ProjectKind.staticWeb,
    steps: [
      DevelopmentWorkflowStep(
        id: 'artifact',
        command: '',
        kind: 'artifact',
        expectedArtifactPath: 'index.html',
      ),
    ],
    artifactPath: 'index.html',
    checksum: false,
  );

  static const all = <DevelopmentWorkflow>[
    flutterApk,
    androidGradle,
    nodeVerify,
    pythonTest,
    goArm64,
    staticWeb,
  ];

  static DevelopmentWorkflow forKind(ProjectKind kind) => switch (kind) {
        ProjectKind.flutter => flutterApk,
        ProjectKind.androidGradle => androidGradle,
        ProjectKind.node => nodeVerify,
        ProjectKind.python => pythonTest,
        ProjectKind.go => goArm64,
        ProjectKind.staticWeb => staticWeb,
        ProjectKind.javaApk => staticWeb,
        ProjectKind.unknown => flutterApk,
      };
}

class DevelopmentWorkflowResult {
  const DevelopmentWorkflowResult({
    required this.success,
    required this.steps,
    this.plan,
    this.artifactPath,
    this.sha256,
    this.artifactExists = false,
    this.artifactBytes,
    this.packageName,
    this.notes = const [],
  });

  final bool success;
  final List<TerminalSessionExecution> steps;
  final DevelopmentVerificationPlan? plan;
  final String? artifactPath;
  final String? sha256;
  final bool artifactExists;
  final int? artifactBytes;
  final String? packageName;
  final List<String> notes;
}

/// Runs trusted, user-selected workflow templates through the existing
/// terminal bridge. Commands are still checked by TerminalCommandService.
class DevelopmentWorkflowRunner {
  DevelopmentWorkflowRunner(
    this.service, {
    DevelopmentVerificationService? verification,
    ProjectKindDetector detector = const ProjectKindDetector(),
  })  : _verification = verification ?? DevelopmentVerificationService(),
        _detector = detector;

  final TerminalCommandService service;
  final DevelopmentVerificationService _verification;
  final ProjectKindDetector _detector;

  Future<DevelopmentWorkflow> detectWorkflow(String cwd) async {
    final project = await _detector.detect(cwd);
    if (!project.isKnown) return DevelopmentWorkflowTemplates.flutterApk;
    return DevelopmentWorkflowTemplates.forKind(project.kind);
  }

  Future<DevelopmentWorkflowResult> run(
    DevelopmentWorkflow workflow,
    String cwd, {
    String? retryStepId,
    DevelopmentVerificationPlan? previousPlan,
  }) async {
    final plan = previousPlan ??
        _verification.planFromDetection(await _detector.detect(cwd));
    final result = await _verification.run(
      service: service,
      workspacePath: cwd,
      plan: _mergeWorkflow(plan, workflow),
      retryStepId: retryStepId,
    );
    final executions = result.plan.steps
        .where((step) =>
            step.status == VerificationStepStatus.passed ||
            step.status == VerificationStepStatus.failed)
        .map((step) => TerminalSessionExecution(
              ok: step.status == VerificationStepStatus.passed,
              code: step.status == VerificationStepStatus.passed
                  ? 'ok'
                  : 'tool_error',
              message: step.output.isNotEmpty
                  ? step.output
                  : (step.error ?? step.title),
              data: {
                'stepId': step.id,
                'status': step.status.id,
                if (step.exitCode != null) 'exitCode': step.exitCode,
              },
            ))
        .toList(growable: false);
    return DevelopmentWorkflowResult(
      success: result.success,
      steps: executions,
      plan: result.plan,
      artifactPath: result.artifact?.absolutePath ??
          result.artifact?.relativePath ??
          workflow.artifactPath,
      sha256: result.artifact?.sha256,
      artifactExists: result.artifact?.exists ?? false,
      artifactBytes: result.artifact?.bytes,
      packageName: result.artifact?.packageName,
      notes: result.artifact?.notes ?? const [],
    );
  }

  DevelopmentVerificationPlan _mergeWorkflow(
    DevelopmentVerificationPlan detected,
    DevelopmentWorkflow workflow,
  ) {
    if (workflow.steps.isEmpty) {
      return detected.steps.isNotEmpty
          ? detected
          : _verification.planFromDetection(detected.project);
    }
    return DevelopmentVerificationPlan(
      project: detected.project,
      primaryArtifactPath: workflow.artifactPath ?? detected.primaryArtifactPath,
      steps: [
        for (final step in workflow.steps)
          VerificationStep(
            id: step.id,
            title: step.title ?? step.id,
            command: step.command
                .replaceFirst(RegExp(r'^\./gradlew\b'), 'gradlew'),
            kind: step.kind,
            timeout: step.timeout,
            expectedArtifactPath: step.expectedArtifactPath,
          ),
      ],
    );
  }
}
