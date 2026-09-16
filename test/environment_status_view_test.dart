import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/environment_service.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';
import 'package:mobile_agent/presentation/environment/environment_status_view.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

void main() {
  testWidgets('multi-runtime status wraps long capability chips on phones',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    const alpine = LinuxRuntimeInfo(
      kind: LinuxRuntimeKind.builtinProot,
      label: '内置 Alpine',
      available: true,
      detail: '可用',
      supportsShellSyntax: true,
    );
    const termux = LinuxRuntimeInfo(
      kind: LinuxRuntimeKind.termux,
      label: 'Termux',
      available: true,
      detail: '可用',
      supportsShellSyntax: true,
      supportsInteractive: true,
      supportsLiveOutput: true,
      requiresExternalApp: true,
    );

    final snapshot = EnvironmentSnapshot(
      selected: alpine,
      candidates: [alpine, termux],
      architecture: 'Android ARM64',
      freeBytes: null,
      checkedAt: DateTime(2026, 9, 16),
      tools: const [
        EnvironmentToolStatus(
          id: 'node',
          label: 'Node.js',
          available: false,
          detail: 'selected runtime missing',
          required: true,
        ),
      ],
      templates: const [],
      missingCapabilities: const [],
      candidateStatuses: [
        const EnvironmentCandidateStatus(
          runtime: alpine,
          tools: [
            EnvironmentToolStatus(
              id: 'node',
              label: 'Node.js',
              available: false,
              detail: 'missing',
              required: true,
            ),
          ],
          probeCompleted: true,
        ),
        const EnvironmentCandidateStatus(
          runtime: termux,
          tools: [
            EnvironmentToolStatus(
              id: 'node',
              label: 'Node.js',
              available: true,
              detail: 'node v22',
              required: true,
            ),
          ],
          probeCompleted: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: EnvironmentStatusView(snapshot: snapshot),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Alpine · 可用'), findsOneWidget);
    expect(find.text('Termux · 可用'), findsOneWidget);
    expect(find.text('无'), findsOneWidget);
  });
}
