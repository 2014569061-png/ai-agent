// 阶段 3b：无 UI 运行经 ModuleHost 写入会话日志。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/headless_executor.dart';
import 'package:mobile_agent/application/modules/run_profile.dart';
import 'package:mobile_agent/application/session_log/session_event.dart';
import 'package:mobile_agent/application/session_log/session_event_store.dart';
import 'package:mobile_agent/application/session_log/session_log_reader.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';

// 空 Key + 非本地地址 ⇒ DemoProvider，不发网络请求。
const _demo = ProviderConfig(
    baseUrl: 'https://unused.invalid/v1', model: 'demo-model', apiKey: '');

Future<int> _eventCount(AppDatabase db) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM session_events')
      .getSingle();
  return row.read<int>('c');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('a task-bound background run is recorded under task:<id>', () async {
    final result = await HeadlessExecutor.runDetailed(
      db: db,
      config: _demo,
      prompt: '你好',
      taskId: 't-log',
    );
    expect(result.succeeded, isTrue, reason: '${result.error}');

    final events = await DriftSessionEventStore(db).events('task:t-log');
    expect(events.first.type, SessionEventType.turnStart);
    expect(events.last.type, SessionEventType.turnEnd);
    expect(events.last.payload['status'], 'completed');
    final derived = SessionLogReader(events).deriveMessages()!;
    expect(derived.first.role, MessageRole.system);
    expect(derived[1].text, '你好');
    expect(derived.last.role, MessageRole.assistant);
    expect(derived.last.text.trim(), result.text);
  });

  test('repeated runs of the same task append to one session', () async {
    for (var i = 0; i < 2; i++) {
      await HeadlessExecutor.runDetailed(
          db: db, config: _demo, prompt: '第 $i 次', taskId: 't-log');
    }
    final events = await DriftSessionEventStore(db).events('task:t-log');
    final runs = events
        .where((e) => e.type == SessionEventType.turnStart)
        .map((e) => e.runId)
        .toSet();
    expect(runs, hasLength(2));
    expect(SessionLogReader(events).unsealedRuns, isEmpty);
  });

  test('runs without a task or with a non-recording profile write nothing',
      () async {
    await HeadlessExecutor.runDetailed(db: db, config: _demo, prompt: 'a');
    await HeadlessExecutor.runDetailed(
      db: db,
      config: _demo,
      prompt: 'b',
      taskId: 't-sub',
      profile: RunProfile.subagent,
    );
    expect(await _eventCount(db), 0);
  });

  test('deleting a task removes its session log', () async {
    await HeadlessExecutor.runDetailed(
        db: db, config: _demo, prompt: '你好', taskId: 't-del');
    await HeadlessExecutor.runDetailed(
        db: db, config: _demo, prompt: '你好', taskId: 't-keep');
    expect(await DriftSessionEventStore(db).events('task:t-del'), isNotEmpty);

    await db.deleteTask('t-del');

    expect(await DriftSessionEventStore(db).events('task:t-del'), isEmpty);
    expect(await DriftSessionEventStore(db).events('task:t-keep'), isNotEmpty);
  });
}
