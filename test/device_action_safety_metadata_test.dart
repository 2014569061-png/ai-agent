import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/device_action_runner.dart';
import 'package:mobile_agent/presentation/settings/device_action_confirm_sheet.dart';

void main() {
  PreparedDeviceAction action(Map<String, dynamic> preview,
          {String plan = 'plan-1'}) =>
      PreparedDeviceAction(
          description: '待确认设备动作',
          arguments: const {'action': 'set_wifi', 'enabled': true},
          planId: plan,
          preview: {'riskClass': 'requiresConfirmation', ...preview});
  test('only explicit true means recoverable', () {
    expect(action({'reversible': true}).reversible, isTrue);
    expect(action({'reversible': false}).recoveryKnown, isTrue);
    expect(action({'reversible': false}).reversible, isFalse);
    for (final value in [null, 'true', 1]) {
      final item = action({'reversible': value});
      expect(item.recoveryKnown, isFalse);
      expect(item.reversible, isFalse);
    }
    expect(action({}).reversible, isFalse);
  });
  Future<void> show(
      WidgetTester tester, List<PreparedDeviceAction> actions) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                DeviceActionConfirmSheet(title: '确认设备操作', actions: actions))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'unknown recovery is not advertised as recoverable or irreversible',
      (tester) async {
    await show(tester, [action({})]);
    expect(find.text('恢复能力未知'), findsOneWidget);
    expect(find.text('可恢复'), findsNothing);
    expect(find.text('不可撤销'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('device-action-confirm')))
            .onPressed,
        isNull);
    expect(find.byKey(const Key('device-action-ack')), findsOneWidget);
  });
  testWidgets('replacement preview invalidates previous acknowledgement',
      (tester) async {
    await show(tester, [
      action({'reversible': false})
    ]);
    final confirm = find.byKey(const Key('device-action-confirm'));
    await tester.tap(find.byKey(const Key('device-action-ack')));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await show(tester, [
      action({'reversible': false}, plan: 'plan-2')
    ]);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
  });
}
