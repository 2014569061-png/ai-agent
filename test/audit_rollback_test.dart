import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/run_audit_report.dart';
import 'package:mobile_agent/infrastructure/observability/unified_diff.dart';

void main() {
  test('rollback edit_file restores the hashed pre-edit content', () async {
    final directory = await Directory.systemTemp.createTemp('nexus-audit-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/main.dart');
    const before = 'void main() {\n  print("old");\n}\n';
    const after = 'void main() {\n  print("new");\n}\n';
    await file.writeAsString(after);
    final metadata = buildUnifiedDiff(before, after).toMetadata(
      operation: 'edit',
      path: 'main.dart',
    );
    final entry = RunAuditEntry(
      eventId: 'event-1',
      sequenceNo: 1,
      tool: 'edit_file',
      status: 'success',
      effect: 'applied',
      code: 'OK',
      operation: 'edit',
      path: 'main.dart',
      metadata: metadata,
    );

    final result = await AuditRollbackService().rollbackEditFile(
      workspacePath: directory.path,
      entry: entry,
    );

    expect(result.ok, isTrue);
    expect(await file.readAsString(), before);
  });

  test('rollback refuses a later manual edit', () async {
    final directory = await Directory.systemTemp.createTemp('nexus-audit-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/main.dart');
    const before = 'old\n';
    const after = 'new\n';
    await file.writeAsString('manual\n');
    final metadata = buildUnifiedDiff(before, after).toMetadata(
      operation: 'edit',
      path: 'main.dart',
    );
    final entry = RunAuditEntry(
      eventId: 'event-2',
      sequenceNo: 2,
      tool: 'edit_file',
      status: 'success',
      effect: 'applied',
      code: 'OK',
      operation: 'edit',
      path: 'main.dart',
      metadata: metadata,
    );

    final result = await AuditRollbackService().rollbackEditFile(
      workspacePath: directory.path,
      entry: entry,
    );

    expect(result.ok, isFalse);
    expect(await file.readAsString(), 'manual\n');
  });
}
