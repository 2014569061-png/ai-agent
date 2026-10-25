enum ReminderStatus {
  scheduled('scheduled', '已计划'),
  snoozed('snoozed', '稍后提醒'),
  completed('completed', '已完成'),
  cancelled('cancelled', '已取消'),
  missed('missed', '已错过'),
  paused('paused', '待重新启用');

  const ReminderStatus(this.wireName, this.label);
  final String wireName;
  final String label;

  static ReminderStatus tryParse(String? raw) {
    for (final value in ReminderStatus.values) {
      if (value.wireName == raw) return value;
    }
    return ReminderStatus.scheduled;
  }
}

enum ExactAlarmCapability {
  granted('granted', '精确闹钟已授权'),
  degradedInexact('degraded_inexact', '降级为非精确提醒'),
  denied('denied', '闹钟权限受限');

  const ExactAlarmCapability(this.wireName, this.label);
  final String wireName;
  final String label;

  static ExactAlarmCapability tryParse(String? raw) {
    for (final value in ExactAlarmCapability.values) {
      if (value.wireName == raw) return value;
    }
    return ExactAlarmCapability.denied;
  }
}

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.title,
    this.notes = '',
    required this.scheduledAtUtc,
    this.timezoneId = 'Asia/Shanghai',
    this.utcOffsetMinutes = 480,
    this.dstActive = false,
    this.exactAlarmCapability = ExactAlarmCapability.denied,
    this.status = ReminderStatus.scheduled,
    this.snoozeCount = 0,
    this.snoozedUntilUtc,
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String notes;
  final DateTime scheduledAtUtc;
  final String timezoneId;
  final int utcOffsetMinutes;
  final bool dstActive;
  final ExactAlarmCapability exactAlarmCapability;
  final ReminderStatus status;
  final int snoozeCount;
  final DateTime? snoozedUntilUtc;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get effectiveTriggerUtc => snoozedUntilUtc ?? scheduledAtUtc;

  /// Computes a deterministic UTC trigger timestamp from a wall-clock schedule,
  /// explicitly resolving DST spring-forward gaps (shifting forward by 60m)
  /// and DST fall-back ambiguous hours.
  static DateTime computeNextTriggerUtc({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
    required int baseUtcOffsetMinutes,
    bool dstActive = false,
    bool dstSpringForwardGap = false,
    bool dstFallBackSecondOccurrence = false,
  }) {
    final adjustedMinute = dstSpringForwardGap ? minute + 60 : minute;
    final effectiveOffset = baseUtcOffsetMinutes +
        (dstActive && !dstFallBackSecondOccurrence ? 60 : 0);
    final wallUtc = DateTime.utc(year, month, day, hour, adjustedMinute);
    return wallUtc.subtract(Duration(minutes: effectiveOffset));
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'notes': notes,
        'scheduledAtUtc': scheduledAtUtc.toUtc().toIso8601String(),
        'timezoneId': timezoneId,
        'utcOffsetMinutes': utcOffsetMinutes,
        'dstActive': dstActive,
        'exactAlarmCapability': exactAlarmCapability.wireName,
        'status': status.wireName,
        'snoozeCount': snoozeCount,
        'snoozedUntilUtc': snoozedUntilUtc?.toUtc().toIso8601String(),
        'version': version,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}

abstract interface class ReminderDelivery {
  Future<ExactAlarmCapability> schedule(ReminderItem reminder);
  Future<void> cancel(String reminderId);
}
