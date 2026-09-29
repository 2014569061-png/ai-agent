import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Change sets (and the file originals saved for them) older than this are
/// removed.
const changeSetRetentionAge = Duration(days: 30);

/// At most this many of the most recently active tasks keep their change set.
const changeSetRetentionCount = 50;

/// Deletes per-task change-set directories under `<documents>/changesets/`
/// that are older than [maxAge] or beyond the [keep] most recently active.
/// Protected tasks do not count towards [keep].
///
/// A task's activity time is the newer of its change-set manifest and its
/// baseline manifest (the directory mtime when neither exists). Tasks in [protect] (e.g. the
/// one that just ran) are never deleted. Best effort: a directory that cannot
/// be deleted is skipped and retried next time. Returns the number deleted.
Future<int> pruneChangeSets({
  Directory? root,
  Set<String> protect = const {},
  int keep = changeSetRetentionCount,
  Duration maxAge = changeSetRetentionAge,
  DateTime? now,
}) async {
  final base = root ??
      Directory(
          p.join((await getApplicationDocumentsDirectory()).path, 'changesets'));
  if (!await base.exists()) return 0;

  final tasks = <(Directory, DateTime)>[];
  await for (final entity in base.list(followLinks: false)) {
    if (entity is! Directory) continue;
    tasks.add((entity, await _lastActivity(entity)));
  }
  tasks.sort((a, b) => b.$2.compareTo(a.$2));

  final cutoff = (now ?? DateTime.now()).subtract(maxAge);
  var deleted = 0;
  var kept = 0;
  for (final (dir, activity) in tasks) {
    // Protected tasks are always kept and do not use up the [keep] quota.
    if (protect.contains(p.basename(dir.path))) continue;
    if (!activity.isBefore(cutoff) && kept < keep) {
      kept++;
      continue;
    }
    try {
      await dir.delete(recursive: true);
      deleted++;
    } catch (_) {
      // 尽力而为：删不掉只会多占磁盘，下次运行结束时会再试。
    }
  }
  return deleted;
}

/// Newest manifest write for the task; the directory's own mtime is only a
/// fallback for directories without any manifest (e.g. an interrupted write).
Future<DateTime> _lastActivity(Directory dir) async {
  DateTime? latest;
  for (final relative in const [
    'changeset.json',
    'baseline/manifest.json',
  ]) {
    final file = File(p.join(dir.path, relative));
    if (!await file.exists()) continue;
    final modified = await file.lastModified();
    if (latest == null || modified.isAfter(latest)) latest = modified;
  }
  return latest ?? (await dir.stat()).modified;
}
