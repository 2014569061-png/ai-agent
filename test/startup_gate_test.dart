import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/main.dart';

void main() {
  testWidgets('StartupGate enters onboarding when the loader reports first run',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StartupGate(onboardingLoader: () async => false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('配置模型服务'), findsOneWidget);
  });
}
