import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/infrastructure/observability/unified_diff.dart';

void main() {
  test('buildUnifiedDiff emits strict hunks and exact line counts', () {
    final result = buildUnifiedDiff(
      'one\ntwo\nthree\n',
      'one\nchanged\nthree\nfour\n',
      oldPath: 'a/example.txt',
      newPath: 'b/example.txt',
    );

    expect(result.linesAdded, 2);
    expect(result.linesRemoved, 1);
    expect(result.diff, contains('--- a/example.txt'));
    expect(result.diff, contains('+++ b/example.txt'));
    expect(result.diff, contains('@@ -1,3 +1,4 @@'));
    expect(result.diff, contains('-two'));
    expect(result.diff, contains('+changed'));
    expect(result.diff, contains('+four'));
  });

  test('redacts credentials but keeps hashes of original contents', () {
    final result = buildUnifiedDiff(
      'apiKey=sk-1234567890123456\n',
      'apiKey=sk-abcdefghijklmnop\n',
    );
    expect(result.diff, contains('[REDACTED]'));
    expect(result.diff, isNot(contains('1234567890123456')));
    expect(result.contentHashBefore, isNotNull);
    expect(result.contentHashAfter, isNotNull);
  });

  test('truncated diffs stay within the requested UTF-8 byte limit', () {
    final result = buildUnifiedDiff(
      '',
      List<String>.filled(100, '中文内容').join('\n'),
      maxDiffBytes: 64,
    );
    expect(result.truncated, isTrue);
    expect(utf8.encode(result.diff).length, lessThanOrEqualTo(64));
  });

  test(
      'applyUnifiedDiff reverses an edit only when the current content matches',
      () {
    const before = 'one\ntwo\nthree\n';
    const after = 'one\nchanged\nthree\nfour\n';
    final diff = buildUnifiedDiff(before, after).diff;

    expect(applyUnifiedDiff(after, diff, reverse: true), before);
    expect(applyUnifiedDiff('one\nmanual\nthree\nfour\n', diff, reverse: true),
        isNull);
  });
}
