import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/plan_panel.dart';

PlanState _plan({String status = 'draft', List<PlanStep>? steps}) => PlanState(
      status: status,
      steps: steps ??
          const [
            PlanStep(id: 's1', description: '抓取首页结构'),
            PlanStep(id: 's2', description: '写入数据库'),
          ],
    );

void main() {
  testWidgets('未确认计划可编辑，保存后回调编辑文本', (tester) async {
    String? edited;
    var approved = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlanPanel(
            plan: _plan(),
            goal: '重构登录模块',
            onApprove: () => approved = true,
            onCancel: () {},
            onApproveEdited: (text) => edited = text,
          ),
        ),
      ),
    ));
    await tester.pump();

    // 预展示意图
    await tester.tap(find.byKey(const ValueKey('plan_edit_button')));
    await tester.pump();
    final field = find.byKey(const ValueKey('plan_edit_field'));
    expect(field, findsOneWidget);
    expect(find.text('目标：重构登录模块\n\n1. 抓取首页结构\n2. 写入数据库'), findsOneWidget);

    await tester.enterText(field, '目标：重构登录模块\n\n1. 抓取首页结构\n2. 写入数据库\n3. 通知完成');
    final confirm = find.byKey(const ValueKey('plan_edit_confirm'));
    expect(confirm, findsOneWidget);
    // 聚焦时系统文本选择手柄可能覆盖按钮中心，直接触发 onPressed 更稳。
    tester.widget<FilledButton>(confirm).onPressed!();
    await tester.pump();

    expect(edited, isNotNull);
    expect(edited, contains('通知完成'));
    expect(approved, isFalse);
  });

  testWidgets('未接编辑回调时不显示编辑按钮，确认走原批准逻辑', (tester) async {
    var approved = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlanPanel(
            plan: _plan(),
            onApprove: () => approved = true,
            onCancel: () {},
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('plan_edit_button')), findsNothing);
    await tester.tap(find.text('确认并执行计划'));
    await tester.pump();
    expect(approved, isTrue);
  });

  testWidgets('执行中的计划不显示编辑入口', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlanPanel(
            plan: _plan(status: 'executing', steps: const [
              PlanStep(id: 's1', description: '抓取首页结构', status: 'running'),
              PlanStep(id: 's2', description: '写入数据库'),
            ]),
            onApprove: () {},
            onCancel: () {},
            onApproveEdited: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('plan_edit_button')), findsNothing);
    expect(find.byKey(const ValueKey('plan_collapsed')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan_collapsed')));
    await tester.pump();
    expect(find.text('停止执行计划'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan_edit_button')), findsNothing);
  });
}
