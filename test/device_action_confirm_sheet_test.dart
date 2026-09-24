import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/device_action_runner.dart';
import 'package:mobile_agent/presentation/settings/device_action_confirm_sheet.dart';
import 'package:mobile_agent/presentation/settings/device_automation_page.dart';
import 'package:mobile_agent/presentation/settings/device_backups_page.dart';

void main() {
  PreparedDeviceAction action({required String risk, bool reversible = true}) =>
      PreparedDeviceAction(
        description: '开启勿扰模式（Root）',
        arguments: const {'action': 'set_do_not_disturb', 'enabled': true},
        planId: 'plan_1',
        preview: {
          'target': '系统勿扰',
          'impact': '可能静默通知和来电',
          'command': 'cmd notification set_dnd priority',
          'riskClass': risk,
          'reversible': reversible,
          'rollback': '再次关闭勿扰',
        },
      );

  Future<bool?> open(WidgetTester tester, List<PreparedDeviceAction> actions) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDeviceActionConfirmSheet(
              context,
              title: '执行？',
              actions: actions,
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('dangerous actions require an explicit acknowledgement',
      (tester) async {
    await open(tester, [action(risk: 'dangerous')]);
    expect(find.text('cmd notification set_dnd priority'), findsOneWidget);
    expect(find.text('危险 · 需二次确认'), findsOneWidget);
    final confirm = find.byKey(const Key('device-action-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.byKey(const Key('device-action-ack')));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('irreversible actions are clearly marked', (tester) async {
    await open(tester, [action(risk: 'requiresConfirmation', reversible: false)]);
    expect(find.text('不可撤销'), findsOneWidget);
    expect(find.byKey(const Key('device-action-ack')), findsOneWidget);
  });

  testWidgets('ordinary reversible actions can be confirmed directly',
      (tester) async {
    await open(tester, [action(risk: 'requiresConfirmation')]);
    expect(find.text('可恢复'), findsOneWidget);
    expect(find.byKey(const Key('device-action-ack')), findsNothing);
    final confirm = find.byKey(const Key('device-action-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('items without a valid preview are never executable',
      (tester) async {
    await open(tester, [
      PreparedDeviceAction(
        description: '清理下载目录',
        arguments: const {'action': 'clean_folder'},
        error: '没有符合条件的文件，无需清理',
      ),
    ]);
    expect(find.text('没有符合条件的文件，无需清理'), findsOneWidget);
    expect(find.text('没有可执行项'), findsOneWidget);
    final confirm = find.byKey(const Key('device-action-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
  });

  testWidgets('automation and backup pages explain Android-only support',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: DeviceAutomationPage(isAndroidPlatform: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('此页面仅支持 Android'), findsOneWidget);

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: DeviceBackupsPage(isAndroidPlatform: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('此页面仅支持 Android'), findsOneWidget);
  });
}
