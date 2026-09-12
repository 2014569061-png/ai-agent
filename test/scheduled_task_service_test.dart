import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/scheduled_task_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/plugins/plugin_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('delayed daily task is due after Doze window', () {
    const spec = ScheduleSpec(hour: 9, minute: 0);
    final now = DateTime(2026, 9, 12, 13);

    expect(spec.isDue(now, DateTime(2026, 9, 11, 9)), isTrue);
  });

  test('last run prevents replay of the same scheduled occurrence', () {
    const spec = ScheduleSpec(hour: 9, minute: 0);
    final now = DateTime(2026, 9, 12, 13);

    expect(spec.isDue(now, DateTime(2026, 9, 12, 10)), isFalse);
  });

  test('editing updatedAt does not suppress a due task', () async {
    final createdAt = DateTime(2026, 9, 11, 8);
    await db.saveScheduledTask(ScheduledTask(
      id: 'sched-1',
      name: '日报',
      prompt: '总结',
      cron: const ScheduleSpec(hour: 9, minute: 0).toCron(),
      agentId: null,
      enabled: true,
      lastResult: null,
      lastRunAt: DateTime(2026, 9, 11, 9),
      createdAt: createdAt,
      updatedAt: DateTime(2026, 9, 12, 10),
    ));

    final due =
        await ScheduledTaskService().dueTasks(db, DateTime(2026, 9, 12, 13));

    expect(due.map((task) => task.id), contains('sched-1'));
  });

  test('new task does not backfill schedules before creation', () async {
    await db.saveScheduledTask(ScheduledTask(
      id: 'sched-1',
      name: '日报',
      prompt: '总结',
      cron: const ScheduleSpec(hour: 9, minute: 0).toCron(),
      agentId: null,
      enabled: true,
      lastResult: null,
      lastRunAt: null,
      createdAt: DateTime(2026, 9, 12, 10),
      updatedAt: DateTime(2026, 9, 12, 10),
    ));

    final due =
        await ScheduledTaskService().dueTasks(db, DateTime(2026, 9, 12, 13));

    expect(due, isEmpty);
  });

  test('plugin agent import is idempotent', () async {
    final plugin = await PluginStore().importPlugin(
      db: db,
      name: 'presets',
      kind: 'agent',
      manifestJson: jsonEncode({
        'name': 'presets',
        'kind': 'agent',
        'agents': [
          {'name': '评审', 'systemPrompt': '检查代码'}
        ],
      }),
    );

    await PluginStore().importAgents(db);
    final reimported = await PluginStore().importPlugin(
      db: db,
      name: ' presets ',
      kind: 'agent',
      manifestJson: plugin.manifestJson,
    );
    await PluginStore().importAgents(db);

    final agents = await db.allAgents();
    expect(reimported.id, plugin.id);
    expect(await db.allPlugins(), hasLength(1));
    expect(agents, hasLength(1));
    expect(agents.single.id, 'agent-plugin-${plugin.id}-0');
  });
}
