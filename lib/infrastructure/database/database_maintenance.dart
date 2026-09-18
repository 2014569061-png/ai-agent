import 'package:drift/drift.dart';

import 'app_database.dart';

typedef DatabaseMaintenanceAction = Future<void> Function(AppDatabase database);

class DatabaseMaintenanceJob {
  const DatabaseMaintenanceJob({
    required this.key,
    required this.targetVersion,
    required this.run,
  });

  final String key;
  final int targetVersion;
  final DatabaseMaintenanceAction run;
}

class DatabaseMaintenanceCoordinator {
  DatabaseMaintenanceCoordinator({
    required AppDatabase database,
    required List<DatabaseMaintenanceJob> jobs,
  })  : _database = database,
        _jobs = List.unmodifiable(jobs);

  final AppDatabase _database;
  final List<DatabaseMaintenanceJob> _jobs;

  Future<void> runPending() async {
    for (final job in _jobs) {
      if (await _isCompleted(job)) continue;
      try {
        await _database.transaction(() async {
          if (await _isCompleted(job)) return;
          await job.run(_database);
          final now = DateTime.now().toIso8601String();
          await _database.customStatement(
            'INSERT INTO data_maintenance_jobs '
            '(job_key, target_version, attempts, last_error_type, '
            'completed_at, updated_at) VALUES (?, ?, 1, NULL, ?, ?) '
            'ON CONFLICT(job_key) DO UPDATE SET '
            'target_version = excluded.target_version, '
            'attempts = data_maintenance_jobs.attempts + 1, '
            'last_error_type = NULL, completed_at = excluded.completed_at, '
            'updated_at = excluded.updated_at',
            [job.key, job.targetVersion, now, now],
          );
        });
      } catch (error) {
        final now = DateTime.now().toIso8601String();
        await _database.customStatement(
          'INSERT INTO data_maintenance_jobs '
          '(job_key, target_version, attempts, last_error_type, '
          'completed_at, updated_at) VALUES (?, ?, 1, ?, NULL, ?) '
          'ON CONFLICT(job_key) DO UPDATE SET '
          'target_version = excluded.target_version, '
          'attempts = data_maintenance_jobs.attempts + 1, '
          'last_error_type = excluded.last_error_type, completed_at = NULL, '
          'updated_at = excluded.updated_at',
          [job.key, job.targetVersion, error.runtimeType.toString(), now],
        );
      }
    }
  }

  Future<bool> _isCompleted(DatabaseMaintenanceJob job) async {
    final row = await _database.customSelect(
      'SELECT target_version, completed_at FROM data_maintenance_jobs '
      'WHERE job_key = ?',
      variables: [Variable<String>(job.key)],
    ).getSingleOrNull();
    if (row == null) return false;
    return row.read<int>('target_version') >= job.targetVersion &&
        row.readNullable<String>('completed_at') != null;
  }
}

List<DatabaseMaintenanceJob> defaultDatabaseMaintenanceJobs() => [
      DatabaseMaintenanceJob(
        key: 'seed_default_prompt_templates',
        targetVersion: 1,
        run: (database) => database.ensureDefaultPromptTemplates(),
      ),
    ];
