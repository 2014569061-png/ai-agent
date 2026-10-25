import 'package:drift/drift.dart';

import '../domain/reminder.dart';
import '../domain/unique_id.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/notifications/notification_service.dart';

class ReminderService {
  ReminderService(this._db,
      {this.delivery = const NotificationReminderDelivery()});

  final AppDatabase _db;
  final ReminderDelivery? delivery;
  bool _ready = false;

  Future<void> ensureReady() async {
    if (_ready) return;
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS nexus_reminders (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        scheduled_at_utc INTEGER NOT NULL,
        timezone_id TEXT NOT NULL DEFAULT 'Asia/Shanghai',
        utc_offset_minutes INTEGER NOT NULL DEFAULT 480,
        dst_active INTEGER NOT NULL DEFAULT 0,
        exact_alarm_capability TEXT NOT NULL DEFAULT 'denied',
        status TEXT NOT NULL DEFAULT 'scheduled',
        snooze_count INTEGER NOT NULL DEFAULT 0,
        snoozed_until_utc INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_nexus_reminders_status_due '
      'ON nexus_reminders(status, scheduled_at_utc)',
    );
    _ready = true;
  }

  Future<ReminderItem> create({
    String? id,
    required String title,
    String notes = '',
    required DateTime scheduledAtUtc,
    String timezoneId = 'Asia/Shanghai',
    int utcOffsetMinutes = 480,
    bool dstActive = false,
    ExactAlarmCapability exactAlarmCapability = ExactAlarmCapability.denied,
    DateTime? now,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(trimmed)) {
      throw const FormatException('提醒标题不能为空或包含控制字符');
    }
    await ensureReady();
    final clock = (now ?? DateTime.now()).toUtc();
    final item = ReminderItem(
      id: id ?? UniqueId.generate('rem', now: clock),
      title: trimmed,
      notes: notes.trim(),
      scheduledAtUtc: scheduledAtUtc.toUtc(),
      timezoneId: timezoneId.trim().isEmpty ? 'UTC' : timezoneId.trim(),
      utcOffsetMinutes: utcOffsetMinutes,
      dstActive: dstActive,
      exactAlarmCapability: exactAlarmCapability,
      status: ReminderStatus.scheduled,
      snoozeCount: 0,
      version: 1,
      createdAt: clock,
      updatedAt: clock,
    );
    await _db.customStatement(
      '''
      INSERT INTO nexus_reminders (
        id, title, notes, scheduled_at_utc, timezone_id, utc_offset_minutes,
        dst_active, exact_alarm_capability, status, snooze_count,
        snoozed_until_utc, version, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        item.id,
        item.title,
        item.notes,
        item.scheduledAtUtc.millisecondsSinceEpoch,
        item.timezoneId,
        item.utcOffsetMinutes,
        item.dstActive ? 1 : 0,
        item.exactAlarmCapability.wireName,
        item.status.wireName,
        item.snoozeCount,
        item.snoozedUntilUtc?.millisecondsSinceEpoch,
        item.version,
        item.createdAt.millisecondsSinceEpoch,
        item.updatedAt.millisecondsSinceEpoch,
      ],
    );
    return _schedule(item.id);
  }

  Future<ReminderItem> _schedule(String id) async {
    final item = (await findById(id))!;
    ExactAlarmCapability capability = ExactAlarmCapability.denied;
    try {
      capability =
          await delivery?.schedule(item) ?? ExactAlarmCapability.denied;
    } catch (_) {
      // Keep the persisted item visible, with a truthful unavailable status.
    }
    await _db.customStatement(
      'UPDATE nexus_reminders SET exact_alarm_capability = ? WHERE id = ? AND version = ?',
      [capability.wireName, id, item.version],
    );
    return (await findById(id))!;
  }

  Future<List<ReminderItem>> list({bool includeCompleted = true}) async {
    await ensureReady();
    final rows = await _db
        .customSelect(
          includeCompleted
              ? 'SELECT * FROM nexus_reminders ORDER BY scheduled_at_utc ASC'
              : "SELECT * FROM nexus_reminders WHERE status IN ('scheduled', 'snoozed') ORDER BY scheduled_at_utc ASC",
        )
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<ReminderItem?> findById(String id) async {
    await ensureReady();
    final rows = await _db.customSelect(
      'SELECT * FROM nexus_reminders WHERE id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).get();
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<ReminderItem> snooze(
    String id, {
    Duration duration = const Duration(minutes: 10),
    DateTime? now,
  }) async {
    if (duration.inMinutes <= 0) {
      throw const FormatException('延后时长必须大于 0 分钟');
    }
    final existing = await findById(id);
    if (existing == null) {
      throw StateError('提醒不存在：$id');
    }
    if (existing.status == ReminderStatus.cancelled ||
        existing.status == ReminderStatus.completed) {
      throw StateError('已结束的提醒不能稍后提醒');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final base = existing.effectiveTriggerUtc.isAfter(clock)
        ? existing.effectiveTriggerUtc
        : clock;
    final until = base.add(duration);
    final nextVersion = existing.version + 1;
    final nextCount = existing.snoozeCount + 1;
    await _db.customStatement(
      '''
      UPDATE nexus_reminders
      SET status = 'snoozed',
          snooze_count = ?,
          snoozed_until_utc = ?,
          version = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      <Object?>[
        nextCount,
        until.millisecondsSinceEpoch,
        nextVersion,
        clock.millisecondsSinceEpoch,
        id,
      ],
    );
    return _schedule(id);
  }

  Future<ReminderItem> reschedule(
    String id, {
    required DateTime scheduledAtUtc,
    String? timezoneId,
    int? utcOffsetMinutes,
    bool? dstActive,
    DateTime? now,
  }) async {
    final existing = await findById(id);
    if (existing == null) {
      throw StateError('提醒不存在：$id');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final nextVersion = existing.version + 1;
    await _db.customStatement(
      '''
      UPDATE nexus_reminders
      SET scheduled_at_utc = ?,
          timezone_id = ?,
          utc_offset_minutes = ?,
          dst_active = ?,
          status = 'scheduled',
          snoozed_until_utc = NULL,
          version = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      <Object?>[
        scheduledAtUtc.toUtc().millisecondsSinceEpoch,
        timezoneId ?? existing.timezoneId,
        utcOffsetMinutes ?? existing.utcOffsetMinutes,
        (dstActive ?? existing.dstActive) ? 1 : 0,
        nextVersion,
        clock.millisecondsSinceEpoch,
        id,
      ],
    );
    return _schedule(id);
  }

  Future<ReminderItem> complete(String id, {DateTime? now}) async {
    final existing = await findById(id);
    if (existing == null) {
      throw StateError('提醒不存在：$id');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    await delivery?.cancel(id);
    await _db.customStatement(
      '''
      UPDATE nexus_reminders
      SET status = 'completed',
          snoozed_until_utc = NULL,
          version = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      <Object?>[
        existing.version + 1,
        clock.millisecondsSinceEpoch,
        id,
      ],
    );
    return (await findById(id))!;
  }

  Future<ReminderItem> cancel(String id, {DateTime? now}) async {
    final existing = await findById(id);
    if (existing == null) {
      throw StateError('提醒不存在：$id');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    await delivery?.cancel(id);
    await _db.customStatement(
      '''
      UPDATE nexus_reminders
      SET status = 'cancelled',
          snoozed_until_utc = NULL,
          version = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      <Object?>[
        existing.version + 1,
        clock.millisecondsSinceEpoch,
        id,
      ],
    );
    return (await findById(id))!;
  }

  Future<void> delete(String id) async {
    await ensureReady();
    await delivery?.cancel(id);
    await _db.customStatement(
      'DELETE FROM nexus_reminders WHERE id = ?',
      <Object?>[id],
    );
  }

  ReminderItem _fromRow(QueryRow row) {
    final snoozedMs = row.readNullable<int>('snoozed_until_utc');
    return ReminderItem(
      id: row.read<String>('id'),
      title: row.read<String>('title'),
      notes: row.read<String>('notes'),
      scheduledAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('scheduled_at_utc'),
        isUtc: true,
      ),
      timezoneId: row.read<String>('timezone_id'),
      utcOffsetMinutes: row.read<int>('utc_offset_minutes'),
      dstActive: row.read<int>('dst_active') != 0,
      exactAlarmCapability: ExactAlarmCapability.tryParse(
        row.read<String>('exact_alarm_capability'),
      ),
      status: ReminderStatus.tryParse(row.read<String>('status')),
      snoozeCount: row.read<int>('snooze_count'),
      snoozedUntilUtc: snoozedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(snoozedMs, isUtc: true),
      version: row.read<int>('version'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
    );
  }
}
