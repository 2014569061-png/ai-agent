import '../infrastructure/tools/command_tool.dart';

class DevelopmentWorkflowStep {
  const DevelopmentWorkflowStep({required this.id, required this.command});
  final String id;
  final String command;
}

class DevelopmentWorkflow {
  const DevelopmentWorkflow({
    required this.id,
    required this.name,
    required this.steps,
    this.artifactPath,
    this.checksum = true,
  });

  final String id;
  final String name;
  final List<DevelopmentWorkflowStep> steps;
  final String? artifactPath;
  final bool checksum;
}

class DevelopmentWorkflowTemplates {
  static const goArm64 = DevelopmentWorkflow(
    id: 'go-build-arm64',
    name: 'Go ARM64 构建',
    steps: [
      DevelopmentWorkflowStep(
          id: 'build',
          command: 'GOOS=linux GOARCH=arm64 go build -o dist/app ./...'),
      DevelopmentWorkflowStep(id: 'checksum', command: 'sha256sum dist/app'),
    ],
    artifactPath: 'dist/app',
  );

  static const flutterApk = DevelopmentWorkflow(
    id: 'flutter-build-apk',
    name: 'Flutter APK 构建',
    steps: [
      DevelopmentWorkflowStep(
          id: 'build', command: 'flutter build apk --release'),
      DevelopmentWorkflowStep(
          id: 'checksum',
          command: 'sha256sum build/app/outputs/flutter-apk/app-release.apk'),
    ],
    artifactPath: 'build/app/outputs/flutter-apk/app-release.apk',
  );

  static const all = <DevelopmentWorkflow>[goArm64, flutterApk];
}

class DevelopmentWorkflowResult {
  const DevelopmentWorkflowResult({
    required this.success,
    required this.steps,
    this.artifactPath,
    this.sha256,
  });

  final bool success;
  final List<TerminalSessionExecution> steps;
  final String? artifactPath;
  final String? sha256;
}

/// Runs trusted, user-selected workflow templates through the existing
/// terminal bridge. Commands are still checked by TerminalCommandService.
class DevelopmentWorkflowRunner {
  DevelopmentWorkflowRunner(this.service);
  final TerminalCommandService service;

  Future<DevelopmentWorkflowResult> run(
      DevelopmentWorkflow workflow, String cwd) async {
    final session = await service.openSession(workingDirectory: cwd);
    final results = <TerminalSessionExecution>[];
    try {
      for (final step in workflow.steps) {
        final result = await service.executeSession(
            sessionId: session.id, command: step.command);
        results.add(result);
        if (!result.ok) {
          return DevelopmentWorkflowResult(success: false, steps: results);
        }
      }
      return DevelopmentWorkflowResult(
        success: true,
        steps: results,
        artifactPath: workflow.artifactPath,
        sha256: _sha256(results.last.message),
      );
    } finally {
      await service.closeSession(session.id);
    }
  }

  String? _sha256(String value) {
    final match = RegExp(r'\b[a-fA-F0-9]{64}\b').firstMatch(value);
    return match?.group(0)?.toLowerCase();
  }
}
