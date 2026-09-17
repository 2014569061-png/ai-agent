import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/environment_service.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';
import 'package:mobile_agent/presentation/chat/widgets/environment_sheet.dart';

void main() {
  test('Termux setup command replaces false values without duplicating keys',
      () {
    expect(termuxExternalAppsConfigCommand,
        contains('allow-external-apps = true'));
    expect(
      termuxExternalAppsConfigCommand,
      contains("sed '/^[[:space:]]*#\\?[[:space:]]*allow-external-apps"),
    );
    expect(termuxExternalAppsConfigCommand, isNot(contains('grep -q')));
    expect(termuxExternalAppsConfigCommand, contains('mv "\$tmp"'));
  });

  testWidgets('a hanging runtime inventory does not fail Termux installation',
      (tester) async {
    const channel = MethodChannel('nexus/termux_bridge');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isTermuxInstalled') return false;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentServiceProvider.overrideWithValue(
            _HangingEnvironmentService(),
          ),
        ],
        child: const MaterialApp(home: EnvironmentSheet()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('下载并安装 Termux'), findsWidgets);
    expect(find.textContaining('环境检测超时'), findsNothing);
    expect(find.textContaining('Termux 是外部工具链'), findsOneWidget);

    // Let the independent inventory timeout finish so the widget test leaves
    // no framework timer behind. Its failure must remain isolated from the
    // already-rendered Termux steps.
    await tester.pump(const Duration(seconds: 11));
    expect(find.textContaining('环境检测超时'), findsNothing);
  });
}

class _HangingEnvironmentService extends EnvironmentService {
  _HangingEnvironmentService() : super(candidates: <LinuxRuntimeAdapter>[]);

  @override
  Future<EnvironmentSnapshot> inspect({bool force = false}) =>
      Completer<EnvironmentSnapshot>().future;
}
