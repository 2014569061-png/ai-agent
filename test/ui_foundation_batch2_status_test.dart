import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/application/orchestration_module.dart';
import 'package:mobile_agent/domain/collaboration_models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/theme/app_palette.dart';
import 'package:mobile_agent/presentation/theme/app_status_colors.dart';
import 'package:mobile_agent/presentation/memory/memory_page.dart';
import 'package:mobile_agent/presentation/tasks/collaboration_timeline.dart';

class _NoExecution implements OrchestrationModule {
  int forbiddenCalls = 0;
  @override
  Stream<CollaborationEvent> watch(String runId) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    forbiddenCalls++;
    throw StateError('Execution forbidden in UI fixture');
  }
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  late AppDatabase db;
  late _NoExecution module;
  final now = DateTime(2026, 10, 18, 2);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    module = _NoExecution();
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> host(WidgetTester t, Widget page, bool dark, bool hc) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(320, 2600);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          orchestrationModuleProvider.overrideWithValue(module)
        ],
        child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    highContrast: hc,
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true),
                child: child!),
            home: page)));
    await t.pumpAndSettle();
  }

  AppStatusColors expected(WidgetTester t, Finder anchor, AppStatusTone tone) =>
      AppStatusColors.resolve(t.element(anchor), tone);
  void pair(WidgetTester t, Finder finder, AppStatusTone tone, bool hc) {
    expect(finder, findsOneWidget);
    final container = t.widget<Container>(finder),
        colors = expected(t, finder, tone);
    final bg = (container.decoration! as BoxDecoration).color!;
    expect(bg, colors.background);
    expect(bg.a, 1);
    for (final text in t
        .widgetList<Text>(
            find.descendant(of: finder, matching: find.byType(Text)))
        .where((x) => x.style?.color != null)) {
      final fg = text.style!.color!;
      expect(fg, colors.foreground);
      expect(_contrast(fg, bg), greaterThanOrEqualTo(hc ? 7 : 4.5));
    }
  }

  for (final dark in [false, true]) {
    for (final hc in [false, true]) {
      for (final kind in ['偏好', '事实', '需要完整显示而不是截断的自定义分类']) {
        testWidgets('memory metadata320 font2 dark=$dark hc=$hc kind=$kind',
            (t) async {
          await db.saveMemory(Memory(
              id: 'fixture',
              content: '只在内存中的记忆样本',
              category: kind,
              sourceConversationId: null,
              sourceType: 'manual',
              enabled: true,
              importance: 5,
              createdAt: now,
              updatedAt: now));
          await host(t, const MemoryPage(), dark, hc);
          final type = kind == '偏好'
              ? AppStatusTone.brand
              : kind == '事实'
                  ? AppStatusTone.success
                  : AppStatusTone.neutral;
          pair(t, find.byKey(const ValueKey('memory-category-fixture')), type,
              hc);
          pair(t, find.byKey(const ValueKey('memory-importance-fixture')),
              AppStatusTone.warning, hc);
          expect(find.text(kind), findsOneWidget);
          expect(find.text('手动录入'), findsOneWidget);
          expect(find.textContaining('更新于 2026-10-18'), findsOneWidget);
          expect((await db.allMemories()).single.category, kind);
          expect(module.forbiddenCalls, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(milliseconds: 100));
          await t.pumpAndSettle();
        });
      }
      for (final consumed in [50, 70, 90]) {
        testWidgets(
            'timeline status320 font2 dark=$dark hc=$hc budget=$consumed',
            (t) async {
          await db.saveCollaborationRun(CollaborationRun(
              id: 'fixture-run',
              taskId: 'fixture-task',
              mode: 'parallel',
              status: 'awaiting_execution_approval',
              budgetTokens: 100,
              consumedTokens: consumed,
              maxAgents: 3,
              maxRounds: 1,
              currentRound: 1,
              planJson: '{}',
              resultJson: jsonEncode({
                'summary': '内存测试汇总',
                'disagreements': ['保留分歧'],
                'risks': ['证据待核验']
              }),
              error: null,
              createdAt: now,
              updatedAt: now));
          for (final status in ['completed', 'failed', 'running']) {
            await db.saveCollaborationAgentRun(CollaborationAgentRun(
                id: status,
                collaborationRunId: 'fixture-run',
                role: 'reviewer',
                agentProfileId: null,
                status: status,
                round: 1,
                contextManifest: '[]',
                allowedTools: '[]',
                inputDigest: 'fixture',
                outputSummary: '仅展示状态',
                failureReason: null,
                inputTokens: 1,
                outputTokens: 1,
                cachedTokens: 0,
                startedAt: now,
                finishedAt: status == 'running' ? null : now));
          }
          await host(t, const CollaborationTimelinePage(runId: 'fixture-run'),
              dark, hc);
          pair(t, find.byKey(const ValueKey('collaboration-approval-banner')),
              AppStatusTone.warning, hc);
          for (final entry in {
            'completed': AppStatusTone.success,
            'failed': AppStatusTone.danger,
            'running': AppStatusTone.brand
          }.entries) {
            final finder =
                find.byKey(ValueKey('collaboration-agent-status-${entry.key}'));
            final container = t.widget<Container>(finder),
                colors = expected(t, finder, entry.value);
            expect((container.decoration! as BoxDecoration).color,
                colors.background);
            expect(
                t
                    .widget<Icon>(find.descendant(
                        of: finder, matching: find.byType(Icon)))
                    .color,
                colors.foreground);
          }
          final budget = find.text('$consumed% 预算占用');
          final tone = consumed > 80
              ? AppStatusTone.danger
              : consumed > 60
                  ? AppStatusTone.warning
                  : AppStatusTone.success;
          expect(t.widget<Text>(budget).style!.color,
              expected(t, budget, tone).foreground);
          for (final label in ['分歧与权衡取舍', '风险与证据缺口']) {
            final finder = find.text(label),
                fg = t.widget<Text>(finder).style!.color!;
            expect(fg, expected(t, finder, AppStatusTone.warning).foreground);
            expect(
                _contrast(fg,
                    dark ? AppPalette.darkSurface : AppPalette.lightSurface),
                greaterThanOrEqualTo(hc ? 7 : 4.5));
          }
          expect(find.text('确认结果'), findsOneWidget);
          expect((await db.findCollaborationRun('fixture-run'))!.status,
              'awaiting_execution_approval');
          expect(module.forbiddenCalls, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(milliseconds: 100));
          await t.pumpAndSettle();
        });
      }
    }
  }
}
