import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/database/database_maintenance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1').getSingle();
  });

  tearDown(() => database.close());

  test('maintenance job runs once after it completes', () async {
    var runs = 0;
    final coordinator = DatabaseMaintenanceCoordinator(
      database: database,
      jobs: [
        DatabaseMaintenanceJob(
          key: 'test_once',
          targetVersion: 1,
          run: (_) async => runs++,
        ),
      ],
    );

    await coordinator.runPending();
    await coordinator.runPending();

    expect(runs, 1);
    final row = await database
        .customSelect(
          'SELECT attempts, completed_at FROM data_maintenance_jobs '
          "WHERE job_key = 'test_once'",
        )
        .getSingle();
    expect(row.read<int>('attempts'), 1);
    expect(row.read<String>('completed_at'), isNotEmpty);
  });

  test('failed maintenance job is retried on the next run', () async {
    var runs = 0;
    final coordinator = DatabaseMaintenanceCoordinator(
      database: database,
      jobs: [
        DatabaseMaintenanceJob(
          key: 'test_retry',
          targetVersion: 1,
          run: (_) async {
            runs++;
            if (runs == 1) throw StateError('injected failure');
          },
        ),
      ],
    );

    await coordinator.runPending();
    var row = await database
        .customSelect(
          'SELECT attempts, last_error_type, completed_at '
          "FROM data_maintenance_jobs WHERE job_key = 'test_retry'",
        )
        .getSingle();
    expect(row.read<int>('attempts'), 1);
    expect(row.read<String>('last_error_type'), 'StateError');
    expect(row.readNullable<String>('completed_at'), isNull);

    await coordinator.runPending();
    row = await database
        .customSelect(
          'SELECT attempts, last_error_type, completed_at '
          "FROM data_maintenance_jobs WHERE job_key = 'test_retry'",
        )
        .getSingle();
    expect(runs, 2);
    expect(row.read<int>('attempts'), 2);
    expect(row.readNullable<String>('last_error_type'), isNull);
    expect(row.read<String>('completed_at'), isNotEmpty);
  });

  test('failed job rolls back its business writes', () async {
    final coordinator = DatabaseMaintenanceCoordinator(
      database: database,
      jobs: [
        DatabaseMaintenanceJob(
          key: 'test_transaction',
          targetVersion: 1,
          run: (db) async {
            await db.customStatement(
              "INSERT INTO prompt_templates "
              "(id, name, content, category, tags_json, is_favorite, "
              "created_at, updated_at) VALUES "
              "('partial', 'partial', 'partial', 'test', '[]', 0, "
              "'2026-09-17T00:00:00.000', '2026-09-17T00:00:00.000')",
            );
            throw StateError('rollback');
          },
        ),
      ],
    );

    await coordinator.runPending();

    expect(await database.findPromptTemplate('partial'), isNull);
  });
}
