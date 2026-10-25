import 'dart:async';
import 'package:flutter/foundation.dart';
import '../infrastructure/database/app_database.dart';
import 'automatic_backup_service.dart';
import 'scheduled_task_runner.dart' show runDueScheduledTasks;
import 'session_operation_guard.dart';

/// Runs while the application process is alive, including when hidden to tray.
/// Missed schedules are coalesced by ScheduleSpec; overlapping ticks are skipped.
class DesktopScheduler {
  DesktopScheduler(
    this.database, {
    Future<void> Function(AppDatabase db)? runAutomaticBackup,
    Future<void> Function(AppDatabase db)? runScheduledTasks,
  })  : _runAutomaticBackup = runAutomaticBackup ?? _checkAutomaticBackup,
        _runScheduledTasks = runScheduledTasks ?? runDueScheduledTasks;
  final Future<AppDatabase> Function() database;
  final Future<void> Function(AppDatabase db) _runAutomaticBackup;
  final Future<void> Function(AppDatabase db) _runScheduledTasks;

  static Future<void> _checkAutomaticBackup(AppDatabase db) async {
    await runDueAutomaticBackup(db);
  }

  Timer? _timer;
  bool _running = false, _closed = false;
  void start() {
    if (_closed || _timer != null) return;
    _timer =
        Timer.periodic(const Duration(seconds: 30), (_) => unawaited(tick()));
    unawaited(tick());
  }

  Future<void> tick() async {
    if (_closed || _running || SessionOperationGuard.restoring) return;
    _running = true;
    try {
      final db = await database();
      if (_closed || SessionOperationGuard.restoring) return;
      try {
        await _runAutomaticBackup(db);
      } catch (error, stack) {
        debugPrint('桌面自动备份失败，继续执行到期任务：$error\n$stack');
      }
      if (!_closed && !SessionOperationGuard.restoring) {
        await _runScheduledTasks(db);
      }
    } catch (error, stack) {
      debugPrint('桌面定时任务检查失败：$error\n$stack');
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
  }
}
