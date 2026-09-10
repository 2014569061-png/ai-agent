import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/plan_panel.dart';
import 'package:mobile_agent/presentation/theme/app_theme.dart';
import 'package:mobile_agent/presentation/widgets/nexus_status_pill.dart';

void main() {
  group('resolvePlanTerminalStatus', () {
    // 复用 ChatController 的纯函数静态方法，覆盖三类状态收敛。

    PlanStep step(String id, String status) =>
        PlanStep(id: id, description: '步骤$id', status: status);

    List<PlanStep> allCompleted(int n) =>
        [for (var i = 0; i < n; i++) step('s$i', 'completed')];

    test('所有步骤完成且运行成功 → completed', () {
      final r = ChatController.resolvePlanTerminalStatus(
        steps: allCompleted(3),
        currentStatus: 'executing',
        runStatus: 'success',
      );
      expect(r, 'completed');
    });

    test('所有步骤完成但 runStatus=paused → 仍收敛为 completed（恢复后不再残留 paused）', () {
      // 预算暂停后从断点续跑：步骤全部完成时，即使 runStatus 是 paused
      // 也应收敛为 completed，避免顶层长期停留在 paused。
      final r = ChatController.resolvePlanTerminalStatus(
        steps: allCompleted(3),
        currentStatus: 'paused',
        runStatus: 'paused',
      );
      expect(r, 'completed');
    });

    test('运行尚未结束（runStatus=null）且所有步骤完成 → completed', () {
      // 这是“所有步骤完成但顶层仍 executing”的直接修复路径。
      final r = ChatController.resolvePlanTerminalStatus(
        steps: allCompleted(2),
        currentStatus: 'executing',
      );
      expect(r, 'completed');
    });

    test('运行尚未结束且有步骤仍在运行 → 保持 executing（返回 null 不强行改态）', () {
      final r = ChatController.resolvePlanTerminalStatus(
        steps: [step('s1', 'completed'), step('s2', 'running')],
        currentStatus: 'executing',
      );
      expect(r, isNull);
    });

    test('被取消/打断 → cancelled，不残留 executing', () {
      final r = ChatController.resolvePlanTerminalStatus(
        steps: [step('s1', 'running'), step('s2', 'pending')],
        currentStatus: 'executing',
        runStatus: 'cancelled',
        cancelled: true,
      );
      expect(r, 'cancelled');
    });

    test('运行尚未结束且存在失败步骤且全部终态 → failed', () {
      // _reconcilePlanTopLevel 以 runStatus=null 调用：有失败步骤时收敛为 failed。
      final r = ChatController.resolvePlanTerminalStatus(
        steps: [step('s1', 'completed'), step('s2', 'failed')],
        currentStatus: 'executing',
      );
      expect(r, 'failed');
    });

    test('未全部完成且非成功/取消 → failed', () {
      final r = ChatController.resolvePlanTerminalStatus(
        steps: [step('s1', 'completed'), step('s2', 'pending')],
        currentStatus: 'executing',
        runStatus: 'failed',
      );
      expect(r, 'failed');
    });

    test('空步骤列表 → 返回 null 不改态', () {
      expect(
        ChatController.resolvePlanTerminalStatus(
          steps: const [],
          currentStatus: 'executing',
          runStatus: 'success',
        ),
        isNull,
      );
    });
  });

  group('normalizePlanStepsForTerminal', () {
    PlanStep step(String id, String status) =>
        PlanStep(id: id, description: '步骤$id', status: status);

    test('终态 completed → 残留 running / pending 步骤置为 completed', () {
      final r = ChatController.normalizePlanStepsForTerminal(
        [step('s1', 'running'), step('s2', 'pending'), step('s3', 'failed')],
        'completed',
      );
      expect(r.map((e) => e.status).toList(),
          ['completed', 'completed', 'failed']);
    });

    test('终态 failed → 残留 running / pending 步骤置为 failed', () {
      final r = ChatController.normalizePlanStepsForTerminal(
        [step('s1', 'running'), step('s2', 'pending'), step('s3', 'completed')],
        'failed',
      );
      expect(
          r.map((e) => e.status).toList(), ['failed', 'failed', 'completed']);
    });

    test('终态 cancelled → 残留 running / pending 步骤置为 failed（不再转圈）', () {
      final r = ChatController.normalizePlanStepsForTerminal(
        [step('s1', 'running'), step('s2', 'pending')],
        'cancelled',
      );
      expect(r.map((e) => e.status).toList(), ['failed', 'failed']);
    });

    test('终态 paused → 步骤保持原样（供继续执行从断点续跑）', () {
      final r = ChatController.normalizePlanStepsForTerminal(
        [step('s1', 'completed'), step('s2', 'running'), step('s3', 'pending')],
        'paused',
      );
      expect(
          r.map((e) => e.status).toList(), ['completed', 'running', 'pending']);
    });

    test('全部已是终态 → 不改变任何步骤', () {
      final r = ChatController.normalizePlanStepsForTerminal(
        [step('s1', 'completed'), step('s2', 'failed')],
        'completed',
      );
      expect(r.map((e) => e.status).toList(), ['completed', 'failed']);
    });
  });

  group('NexusStatusPill paused', () {
    testWidgets('paused 字符串映射为“已暂停”，不再退化为待确认', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: NexusStatusPill.fromString('paused'),
        ),
      ));
      expect(find.text('已暂停'), findsOneWidget);
      expect(find.text('待确认'), findsNothing);
    });
  });

  group('PlanPanel paused UI', () {
    PlanState pausedPlan() => const PlanState(
          steps: [
            PlanStep(id: 's1', description: '第一步', status: 'completed'),
            PlanStep(id: 's2', description: '第二步', status: 'running'),
          ],
          status: 'paused',
        );

    testWidgets('暂停态展示“继续执行”入口，不再静默无操作', (tester) async {
      var resumed = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PlanPanel(
            plan: pausedPlan(),
            onApprove: () {},
            onCancel: () {},
            onResume: () => resumed = true,
          ),
        ),
      ));
      expect(find.text('继续执行'), findsOneWidget);
      await tester.tap(find.text('继续执行'));
      expect(resumed, isTrue);
    });

    testWidgets('暂停态状态徽标显示已暂停', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PlanPanel(
            plan: pausedPlan(),
            onApprove: () {},
            onCancel: () {},
            onResume: () {},
          ),
        ),
      ));
      expect(find.text('已暂停'), findsOneWidget);
    });
  });
}
