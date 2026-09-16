import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/development_workflow.dart';
import 'package:mobile_agent/application/project_kind.dart';

void main() {
  test('built-in workbench templates declare verification steps', () {
    for (final workflow in DevelopmentWorkflowTemplates.all) {
      expect(workflow.steps, isNotEmpty);
    }
    expect(
      DevelopmentWorkflowTemplates.flutterApk.artifactPath,
      'build/app/outputs/flutter-apk/app-release.apk',
    );
    expect(
      DevelopmentWorkflowTemplates.forKind(ProjectKind.androidGradle).id,
      'android-gradle-verify',
    );
  });
}
