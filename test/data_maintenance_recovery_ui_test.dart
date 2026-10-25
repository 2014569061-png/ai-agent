import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/data_maintenance_actions.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/runtime_maintenance_store.dart';
import 'package:mobile_agent/presentation/settings/data_backup_page.dart';
import 'package:mobile_agent/presentation/settings/settings_components.dart';

class _Actions extends DataMaintenanceActions {
  _Actions(AppDatabase db, this.status)
      : super(database: () async => db, refresh: () async {});
  RuntimeRecoveryStatus status;
  int calls = 0;
  @override
  Future<RuntimeRecoveryStatus> recoveryStatus() async => status;
  @override
  Future<void> recoverInterrupted() async {
    calls++;
    status = const RuntimeRecoveryStatus(false, false, '没有中断的维护或遗留运行');
  }
}

void main() {
  testWidgets(
      'Windows backup settings show the closed-program scheduling limitation',
      (tester) async {
    SharedPreferences.setMockInitialValues({'settings.backup.auto': true});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final actions =
        _Actions(db, const RuntimeRecoveryStatus(false, false, '没有中断的维护或遗留运行'));
    await tester.pumpWidget(ProviderScope(overrides: [
      databaseProvider.overrideWith((ref) async => db),
      dataMaintenanceActionsProvider.overrideWithValue(actions),
    ], child: const MaterialApp(home: DataBackupPage())));
    await tester.pumpAndSettle();
    final limitation = find.text('每 24 小时创建加密全量快照；桌面关闭程序后无法调度');
    expect(limitation, findsOneWidget);
    await tester.ensureVisible(limitation);
    expect(tester.widget<SettingsSwitch>(find.byType(SettingsSwitch)).value,
        isTrue);
    await tester.tap(find.byType(SettingsSwitch));
    await tester.pumpAndSettle();
    expect(
        (await SharedPreferences.getInstance()).getBool('settings.backup.auto'),
        isFalse);
    expect(limitation, findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  for (final recoverable in [false, true]) {
    testWidgets(
        'recovery entry ${recoverable ? "requires typed confirmation" : "is disabled without evidence"}',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final actions = _Actions(
          db,
          RuntimeRecoveryStatus(
              true, recoverable, recoverable ? '已确认旧进程退出' : '原执行进程仍存活，拒绝解除'));
      await tester.pumpWidget(ProviderScope(overrides: [
        databaseProvider.overrideWith((ref) async => db),
        dataMaintenanceActionsProvider.overrideWithValue(actions),
      ], child: const MaterialApp(home: DataBackupPage())));
      await tester.pumpAndSettle();
      if (!recoverable) {
        await tester.scrollUntilVisible(find.text('运行维护'), 250,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('运行维护'));
        await tester.pumpAndSettle();
      }
      final title = find.text('恢复中断的数据维护');
      await tester.scrollUntilVisible(title, 250,
          scrollable: find.byType(Scrollable).first);
      final tile = tester.widget<SettingsTile>(
          find.ancestor(of: title, matching: find.byType(SettingsTile)).first);
      if (!recoverable) {
        expect(tile.onTap, isNull);
        expect(actions.calls, 0);
        return;
      }
      expect(tile.onTap, isNotNull);
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(find.text('恢复中断维护后的运行能力？'), findsOneWidget);
      expect(find.textContaining('不会自动回滚崩溃时的文件或密钥'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, '恢复运行');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '错误确认词');
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '恢复运行');
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      expect(actions.calls, 0);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(actions.calls, 1);
      expect(find.text('恢复中断维护后的运行能力？'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  }
}
