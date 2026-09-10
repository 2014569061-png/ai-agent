import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A line-oriented unified diff with accurate hunk ranges and change counts.
class UnifiedDiffResult {
  const UnifiedDiffResult({
    required this.diff,
    required this.linesAdded,
    required this.linesRemoved,
    required this.truncated,
    required this.bytesBefore,
    required this.bytesAfter,
    required this.contentHashBefore,
    required this.contentHashAfter,
  });

  final String diff;
  final int linesAdded;
  final int linesRemoved;
  final bool truncated;
  final int bytesBefore;
  final int bytesAfter;
  final String? contentHashBefore;
  final String? contentHashAfter;

  Map<String, dynamic> toMetadata(
          {required String operation, required String path}) =>
      {
        'operation': operation,
        'path': path,
        'bytesBefore': bytesBefore,
        'bytesAfter': bytesAfter,
        'linesAdded': linesAdded,
        'linesRemoved': linesRemoved,
        'contentHashBefore': contentHashBefore,
        'contentHashAfter': contentHashAfter,
        if (diff.isNotEmpty) 'diff': diff,
        if (truncated) 'diffTruncated': true,
      };
}

/// Removes credentials and other high-risk values before diagnostics are
/// persisted or exported. Hashes and byte counts are still calculated from the
/// original content so integrity data remains useful.
String redactSensitiveText(String value) {
  var result = value;
  result = result.replaceAll(
    RegExp(
        r'''(api[_-]?key|authorization|cookie|password|secret|token)\s*["']?\s*[:=]\s*(?:["'][^"']*["']|(?:Bearer\s+)?[^,\s}"']+)''',
        caseSensitive: false),
    r'$1=[REDACTED]',
  );
  result =
      result.replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{16,}\b'), 'sk-[REDACTED]');
  return result;
}

/// Builds a strict, deterministic unified diff without depending on a native
/// diff executable (the same implementation is used on Android, desktop and web).
UnifiedDiffResult buildUnifiedDiff(
  String before,
  String after, {
  String oldPath = 'a/file',
  String newPath = 'b/file',
  int contextLines = 3,
  int maxDiffBytes = 100 * 1024,
}) {
  final beforeBytes = utf8.encode(before).length;
  final afterBytes = utf8.encode(after).length;
  final beforeHash =
      before.isEmpty ? null : sha256.convert(utf8.encode(before)).toString();
  final afterHash =
      after.isEmpty ? null : sha256.convert(utf8.encode(after)).toString();
  final ops = _diffLines(before, after);
  final added = ops.where((op) => op.kind == _DiffKind.insert).length;
  final removed = ops.where((op) => op.kind == _DiffKind.delete).length;

  final full = _renderUnified(ops, oldPath, newPath, contextLines);
  final tooLarge = utf8.encode(full).length > maxDiffBytes;
  final diff = tooLarge
      ? _truncateDiff(redactSensitiveText(full), maxDiffBytes)
      : redactSensitiveText(full);
  return UnifiedDiffResult(
    diff: diff,
    linesAdded: added,
    linesRemoved: removed,
    truncated: tooLarge,
    bytesBefore: beforeBytes,
    bytesAfter: afterBytes,
    contentHashBefore: beforeHash,
    contentHashAfter: afterHash,
  );
}

/// Applies a previously generated unified diff to [current].
///
/// The audit UI uses the reverse direction to undo an `edit_file` operation.
/// Hunks are matched against the current file before writing so a later manual
/// edit is never silently overwritten. `null` means the patch is stale or
/// malformed and the caller should ask the user to inspect the file manually.
String? applyUnifiedDiff(
  String current,
  String diff, {
  bool reverse = false,
}) {
  final lines = diff.split('\n');
  final hunks = <_UnifiedHunk>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (!line.startsWith('@@ ')) continue;
    final match = RegExp(
      r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
    ).firstMatch(line);
    if (match == null) return null;
    final oldStart = int.parse(match.group(1)!);
    final oldCount = int.tryParse(match.group(2) ?? '1') ?? 1;
    final newStart = int.parse(match.group(3)!);
    final newCount = int.tryParse(match.group(4) ?? '1') ?? 1;
    final body = <String>[];
    index++;
    while (index < lines.length && !lines[index].startsWith('@@ ')) {
      final bodyLine = lines[index];
      if (bodyLine == r'\ No newline at end of file') {
        index++;
        continue;
      }
      if (bodyLine.isEmpty || !const {' ', '+', '-'}.contains(bodyLine[0])) {
        return null;
      }
      body.add(bodyLine);
      index++;
    }
    index--;

    final oldLines = <String>[];
    final newLines = <String>[];
    for (final bodyLine in body) {
      final content = bodyLine.substring(1);
      switch (bodyLine[0]) {
        case ' ':
          oldLines.add(content);
          newLines.add(content);
        case '-':
          oldLines.add(content);
        case '+':
          newLines.add(content);
      }
    }
    if (oldLines.length != oldCount || newLines.length != newCount) {
      return null;
    }
    hunks.add(_UnifiedHunk(
      oldStart: oldStart,
      newStart: newStart,
      oldLines: oldLines,
      newLines: newLines,
    ));
  }
  if (hunks.isEmpty) return null;

  final hadTrailingNewline = current.endsWith('\n');
  final result = _lines(current).toList();
  for (final hunk in hunks.reversed) {
    final expected = reverse ? hunk.newLines : hunk.oldLines;
    final replacement = reverse ? hunk.oldLines : hunk.newLines;
    final start = (reverse ? hunk.newStart : hunk.oldStart) - 1;
    if (start < 0 || start + expected.length > result.length) return null;
    for (var offset = 0; offset < expected.length; offset++) {
      if (result[start + offset] != expected[offset]) return null;
    }
    result.replaceRange(start, start + expected.length, replacement);
  }
  final restored = result.join('\n');
  if (hadTrailingNewline && restored.isNotEmpty) return '$restored\n';
  return restored;
}

class _UnifiedHunk {
  const _UnifiedHunk({
    required this.oldStart,
    required this.newStart,
    required this.oldLines,
    required this.newLines,
  });

  final int oldStart;
  final int newStart;
  final List<String> oldLines;
  final List<String> newLines;
}

enum _DiffKind { equal, delete, insert }

class _DiffOp {
  const _DiffOp(this.kind, this.line);
  final _DiffKind kind;
  final String line;
}

List<String> _lines(String value) {
  if (value.isEmpty) return const [];
  final result = value.split('\n');
  if (result.isNotEmpty && result.last.isEmpty) result.removeLast();
  return result;
}

List<_DiffOp> _diffLines(String before, String after) {
  final oldLines = _lines(before);
  final newLines = _lines(after);
  final n = oldLines.length;
  final m = newLines.length;
  // Avoid quadratic memory for very large files. A delete-all/insert-all
  // script is still a valid unified diff and keeps change counts exact.
  if (n > 0 && m > 0 && n * m > 4000000) {
    return [
      ...oldLines.map((line) => _DiffOp(_DiffKind.delete, line)),
      ...newLines.map((line) => _DiffOp(_DiffKind.insert, line)),
    ];
  }
  final table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      table[i][j] = oldLines[i] == newLines[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] > table[i][j + 1]
              ? table[i + 1][j]
              : table[i][j + 1]);
    }
  }
  final ops = <_DiffOp>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (oldLines[i] == newLines[j]) {
      ops.add(_DiffOp(_DiffKind.equal, oldLines[i++]));
      j++;
    } else if (table[i + 1][j] > table[i][j + 1]) {
      ops.add(_DiffOp(_DiffKind.delete, oldLines[i++]));
    } else {
      ops.add(_DiffOp(_DiffKind.insert, newLines[j++]));
    }
  }
  while (i < n) {
    ops.add(_DiffOp(_DiffKind.delete, oldLines[i++]));
  }
  while (j < m) {
    ops.add(_DiffOp(_DiffKind.insert, newLines[j++]));
  }
  return ops;
}

String _renderUnified(
    List<_DiffOp> ops, String oldPath, String newPath, int contextLines) {
  final changed = <int>[];
  for (var i = 0; i < ops.length; i++) {
    if (ops[i].kind != _DiffKind.equal) changed.add(i);
  }
  if (changed.isEmpty) return '';

  final ranges = <(int, int)>[];
  var start = changed.first - contextLines;
  var end = changed.first + contextLines;
  for (final index in changed.skip(1)) {
    final nextStart = index - contextLines;
    final nextEnd = index + contextLines;
    if (nextStart <= end + 1) {
      end = nextEnd;
    } else {
      ranges
          .add((start.clamp(0, ops.length - 1), end.clamp(0, ops.length - 1)));
      start = nextStart;
      end = nextEnd;
    }
  }
  ranges.add((start.clamp(0, ops.length - 1), end.clamp(0, ops.length - 1)));

  final out = StringBuffer()
    ..writeln('--- $oldPath')
    ..writeln('+++ $newPath');
  for (final range in ranges) {
    final from = range.$1;
    final to = range.$2;
    var oldBefore = 0;
    var newBefore = 0;
    for (var i = 0; i < from; i++) {
      if (ops[i].kind != _DiffKind.insert) oldBefore++;
      if (ops[i].kind != _DiffKind.delete) newBefore++;
    }
    final oldCount = ops
        .sublist(from, to + 1)
        .where((op) => op.kind != _DiffKind.insert)
        .length;
    final newCount = ops
        .sublist(from, to + 1)
        .where((op) => op.kind != _DiffKind.delete)
        .length;
    final oldStart = oldCount == 0 ? oldBefore : oldBefore + 1;
    final newStart = newCount == 0 ? newBefore : newBefore + 1;
    out.writeln('@@ -$oldStart,$oldCount +$newStart,$newCount @@');
    for (final op in ops.sublist(from, to + 1)) {
      final prefix = switch (op.kind) {
        _DiffKind.equal => ' ',
        _DiffKind.delete => '-',
        _DiffKind.insert => '+',
      };
      out.writeln('$prefix${op.line}');
    }
  }
  return out.toString().trimRight();
}

String _truncateDiff(String value, int maxBytes) {
  final bytes = utf8.encode(value);
  if (maxBytes <= 0) return '';
  if (bytes.length <= maxBytes) return value;
  final marker = '\n\\ No newline at end of file\n[diff truncated]';
  final markerBytes = utf8.encode(marker);
  if (markerBytes.length >= maxBytes) {
    final end = _utf8Boundary(markerBytes, maxBytes);
    return utf8.decode(markerBytes.sublist(0, end), allowMalformed: true);
  }
  final allowed = maxBytes - markerBytes.length;
  final end = _utf8Boundary(bytes, allowed);
  return '${utf8.decode(bytes.sublist(0, end), allowMalformed: true)}$marker';
}

int _utf8Boundary(List<int> bytes, int limit) {
  var end = limit.clamp(0, bytes.length);
  while (end > 0 && (bytes[end - 1] & 0xC0) == 0x80) {
    end--;
  }
  return end;
}
