import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/presentation/chat/widgets/chat_empty_state.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/liquid_glass.dart';

void main() {
  testWidgets('empty state provides a model setup primary action',
      (tester) async {
    var configured = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ChatEmptyState(
          onConfigureModel: () => configured = true,
        ),
      ),
    ));

    expect(find.text('配置模型'), findsOneWidget);
    await tester.tap(find.text('配置模型'));
    expect(configured, isTrue);
  });

  testWidgets('empty state asks to choose a project before workspace exists',
      (tester) async {
    var picked = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ChatEmptyState(
          providerConfigured: true,
          onWorkspaceTap: () => picked = true,
        ),
      ),
    ));

    expect(find.text('选择项目'), findsOneWidget);
    await tester.tap(find.text('选择项目'));
    expect(picked, isTrue);
  });

  testWidgets('empty state changes the primary action with workspace state',
      (tester) async {
    var analyzed = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ChatEmptyState(
          providerConfigured: true,
          hasWorkspace: true,
          suggestions: const [QuickAction(label: '解读项目')],
          onAnalyzeWorkspace: () => analyzed = true,
        ),
      ),
    ));

    expect(find.text('分析当前项目'), findsOneWidget);
    await tester.tap(find.text('分析当前项目'));
    expect(analyzed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state action grid uses liquid glass in liquid mode',
      (tester) async {
    AppAppearanceController.glassIntensity.value = 0.85;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: ChatEmptyState(providerConfigured: true),
      ),
    ));

    expect(find.byType(LiquidGlass), findsAtLeastNWidgets(4));
  });
}
