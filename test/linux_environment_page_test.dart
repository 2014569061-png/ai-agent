import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/environment_service.dart';
import 'package:mobile_agent/infrastructure/terminal/linux_runtime.dart';
import 'package:mobile_agent/presentation/settings/linux_environment_page.dart';
import 'package:mobile_agent/presentation/widgets/nexus_loading_skeleton.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('preference failure exits skeleton state and exposes retry',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LinuxEnvironmentPage(
          environmentService: _ThrowingEnvironmentService(),
          preferencesLoader: () async =>
              Future<SharedPreferences>.error(StateError('prefs unavailable')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NexusListSkeleton), findsNothing);
    expect(find.textContaining('偏好设置读取失败'), findsOneWidget);
    expect(find.byTooltip('重新检测'), findsOneWidget);
    expect(find.textContaining('allow-external-apps'), findsOneWidget);
  });

  testWidgets('environment failure exits skeleton state and exposes retry',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LinuxEnvironmentPage(
          environmentService: _ThrowingEnvironmentService(),
          preferencesLoader: SharedPreferences.getInstance,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NexusListSkeleton), findsNothing);
    expect(find.textContaining('检测出错'), findsOneWidget);
    expect(find.byTooltip('重新检测'), findsOneWidget);
  });

  testWidgets('environment check timeout exits skeleton state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LinuxEnvironmentPage(
          environmentService: _HangingEnvironmentService(),
          environmentCheckTimeout: const Duration(milliseconds: 20),
          preferencesLoader: SharedPreferences.getInstance,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NexusListSkeleton), findsNothing);
    expect(find.textContaining('环境检测超时'), findsOneWidget);
    expect(find.byTooltip('重新检测'), findsOneWidget);
  });
}

class _ThrowingEnvironmentService extends EnvironmentService {
  _ThrowingEnvironmentService() : super(candidates: <LinuxRuntimeAdapter>[]);

  @override
  Future<EnvironmentSnapshot> inspect({bool force = false}) async {
    throw StateError('environment unavailable');
  }
}

class _HangingEnvironmentService extends EnvironmentService {
  _HangingEnvironmentService() : super(candidates: <LinuxRuntimeAdapter>[]);

  @override
  Future<EnvironmentSnapshot> inspect({bool force = false}) =>
      Completer<EnvironmentSnapshot>().future;
}
