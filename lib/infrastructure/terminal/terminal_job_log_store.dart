import 'dart:io';

import 'package:path/path.dart' as p;
import '../../domain/sensitive_tool_policy.dart';

/// Job logs are diagnostic metadata, not an unredacted second result store.
class TerminalJobLogStore {
  TerminalJobLogStore(this.directory,
      {this.maxFiles = 50, this.maxAge = const Duration(days: 7)});
  final Directory directory;
  final int maxFiles;
  final Duration maxAge;
  Future<void> _cleanup = Future<void>.value();

  static const retainedOutputChars = 256 * 1024;
  static String boundedOutput(String text) {
    if (text.length <= retainedOutputChars) return text;
    var start = text.length - retainedOutputChars;
    final unit = text.codeUnitAt(start);
    if (unit >= 0xdc00 && unit <= 0xdfff) start++;
    return '[输出已截断，仅保留末尾 $retainedOutputChars 字符]\n${text.substring(start)}';
  }

  static String persistedPayload(String type, String payload) =>
      type == 'started'
          ? SensitiveToolPolicy.redactArgumentText('terminal', payload)
          : SensitiveToolPolicy.redactResultText('terminal', payload);

  Future<void> prune({required Iterable<String> Function() activePaths}) {
    bool isActive(String path) =>
        activePaths().any((active) => p.equals(active, path));
    _cleanup = _cleanup.then((_) async {
      if (!await directory.exists()) return;
      final files = <(File, DateTime)>[];
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File ||
            !RegExp(r'^job-.*\.log$').hasMatch(p.basename(entity.path))) {
          continue;
        }
        if (isActive(entity.path)) continue;
        files.add((entity, (await entity.stat()).modified));
      }
      files.sort((a, b) => b.$2.compareTo(a.$2));
      final cutoff = DateTime.now().subtract(maxAge);
      var retained = 0;
      for (final entry in files) {
        // Recheck after awaits: a newer job must not lose its active log.
        if (isActive(entry.$1.path)) continue;
        if (retained >= maxFiles || entry.$2.isBefore(cutoff)) {
          await entry.$1.delete();
        } else {
          retained++;
        }
      }
    }).catchError((Object error) {
      // Retention is best effort when storage is unavailable. All newly written
      // payloads are redacted independently, and command results remain in RAM.
    });
    return _cleanup;
  }
}
