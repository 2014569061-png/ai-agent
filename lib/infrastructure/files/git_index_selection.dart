import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Git owns nested .gitignore/negation/global-exclude semantics. An unavailable
/// Git executable or non-repository returns null, never an empty success set.
Future<Set<String>?> gitIndexSelection(String root) async {
  Process? process;
  Timer? timer;
  try {
    process = await Process.start(
        'git',
        [
          '-c',
          'core.fsmonitor=false',
          'ls-files',
          '-z',
          '--cached',
          '--others',
          '--exclude-standard',
          '--',
          '.',
        ],
        workingDirectory: root,
        runInShell: false);
    final child = process;
    var overflow = false;
    var timedOut = false;
    final bytes = <int>[];
    timer = Timer(const Duration(seconds: 3), () {
      timedOut = true;
      child.kill();
    });
    final output = child.stdout.forEach((chunk) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        overflow = true;
        child.kill();
      } else {
        bytes.addAll(chunk);
      }
    });
    final errors = child.stderr.drain<void>();
    final exitCode = await child.exitCode;
    await Future.wait([output, errors]);
    if (exitCode != 0 || overflow || timedOut) return null;
    return utf8
        .decode(bytes)
        .split('\u0000')
        .where((p) => p.isNotEmpty)
        .toSet();
  } catch (_) {
    return null;
  } finally {
    timer?.cancel();
  }
}
