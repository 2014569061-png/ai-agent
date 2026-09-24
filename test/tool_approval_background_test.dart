// 审批弹窗在「显示期间被切到后台」时的收敛行为。
//
// 这一条覆盖的是一个真实死锁：弹窗已经不可见，后台又冻结 Dart 定时器，若不主动
// 交还，需要审批的工具会在后台一直等下去。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/tool_approval_sheet.dart';

ToolCall _call() => const ToolCall(
      id: 'call-1',
      name: 'run_command',
      arguments: {'CommandLine': 'echo hi'},
    );

Future<ToolApproval?> _pumpSheet(
  WidgetTester tester, {
  VoidCallback? onBackgrounded,
  VoidCallback? onExpired,
}) async {
  ToolApproval? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            result = await showModalBottomSheet<ToolApproval>(
              context: context,
              builder: (_) => ToolApprovalSheet(
                call: _call(),
                risk: ToolRisk.requiresConfirmation,
                onBackgrounded: onBackgrounded,
                onExpired: onExpired,
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('弹窗期间切到后台：回调触发且弹窗以 reject 收敛', (tester) async {
    var handedOff = 0;
    await _pumpSheet(tester, onBackgrounded: () => handedOff++);
    expect(find.byType(ToolApprovalSheet), findsOneWidget);

    // 切到后台（锁屏 / 切走应用）。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(handedOff, 1, reason: '应把这次不可见的审批交还调用方');

    // 后台期间帧被冻结，弹窗的退场动画要走完必须先回到前台。
    // 真实生命周期是逐级过渡的：paused → hidden → inactive → resumed，
    // 直接跳转会触发框架自身的状态机断言。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(ToolApprovalSheet), findsNothing,
        reason: '弹窗应以 reject 收敛，留下一个无人可见的审批更糟');
  });

  testWidgets('回调只触发一次：后台状态变化不会重复交还', (tester) async {
    var handedOff = 0;
    await _pumpSheet(tester, onBackgrounded: () => handedOff++);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(handedOff, 1);
  });

  testWidgets('恢复前台不会触发交还', (tester) async {
    var handedOff = 0;
    await _pumpSheet(tester, onBackgrounded: () => handedOff++);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(handedOff, 0);
    expect(find.byType(ToolApprovalSheet), findsOneWidget);
  });

  testWidgets('inactive 不触发交还：下拉通知栏等瞬时失焦不应中止审批', (tester) async {
    var handedOff = 0;
    await _pumpSheet(tester, onBackgrounded: () => handedOff++);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    expect(handedOff, 0);
    expect(find.byType(ToolApprovalSheet), findsOneWidget);
  });

  testWidgets('未注入 onBackgrounded 时行为不变：弹窗留在原地', (tester) async {
    await _pumpSheet(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(find.byType(ToolApprovalSheet), findsOneWidget,
        reason: '没有接通知通道时擅自 pop 会变成一次无提示的静默拒绝');
  });

  testWidgets('已经是过期态时不再交还', (tester) async {
    var handedOff = 0;
    await _pumpSheet(
      tester,
      onBackgrounded: () => handedOff++,
      onExpired: () {},
      // 立即过期，进入 expired 态。
    );
    // 直接推进到超时，使弹窗进入 expired。
    await tester.pump(const Duration(minutes: 6));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(handedOff, 0);
  });
}