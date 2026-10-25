import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/presentation/chat/widgets/chat_empty_state.dart';
import 'package:mobile_agent/presentation/theme/app_appearance_controller.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';

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

    expect(find.text('分析当前项目'), findsOneWidget);
    await tester.tap(find.text('分析当前项目'));
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

  testWidgets('empty state keeps creation out of the welcome suggestions',
      (tester) async {
    var created = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ChatEmptyState(
          providerConfigured: true,
          onCreateAgent: () => created = true,
        ),
      ),
    ));

    expect(find.text('创建 Agent'), findsNothing);
    expect(created, isFalse);
  });

  testWidgets('welcome remains readable on narrow screens with large text',
      (tester) async {
    AppAppearanceController.glassIntensity.value = 0.85;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: ChatEmptyState(providerConfigured: true),
      ),
    ));

    expect(find.text('N'), findsOneWidget);
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: const Scaffold(body: ChatEmptyState(providerConfigured: true)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('整理一份资料'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
