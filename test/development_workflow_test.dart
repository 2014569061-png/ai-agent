import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/development_workflow.dart';

void main() {
  test('built-in workbench templates declare artifacts and checksums', () {
    for (final workflow in DevelopmentWorkflowTemplates.all) {
      expect(workflow.steps, isNotEmpty);
      expect(workflow.artifactPath, isNotNull);
      expect(workflow.steps.last.command, contains('sha256sum'));
    }
  });
}
