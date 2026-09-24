import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presentation token escape counts do not grow', () {
    final source = _readDartFiles('lib/presentation');

    _assertWithinThreshold(
      files: source,
      pattern: RegExp(r'Color\s*\(\s*0x[0-9A-Fa-f]+'),
      maxAllowed: 103,
      tokenName: 'Color(0x...) 硬编码颜色',
      guidance: '新增颜色应收敛到语义 token (AppPalette)；有意迁移时同步调整基线。',
    );

    _assertWithinThreshold(
      files: source,
      pattern: RegExp(r'fontSize\s*:\s*[0-9]+(?:\.[0-9]+)?'),
      maxAllowed: 223,
      tokenName: 'fontSize 硬编码字号',
      guidance: '新增字号应使用已决策的字号 token (AppTokens.fontSize*)；有意迁移时同步调整基线。',
    );

    _assertWithinThreshold(
      files: source,
      pattern: RegExp(
        r'Duration\s*\(\s*(?:milliseconds|seconds|microseconds)\s*:\s*[0-9]+',
      ),
      maxAllowed: 35,
      tokenName: 'Duration(...) 动画时长',
      guidance: '新增动画时长应使用 NexusMotion / AppTokens.duration* token。',
    );
  });
}

List<File> _readDartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where(
        (file) => file.path.endsWith('.dart') && !file.path.endsWith('.g.dart'))
    .toList();

void _assertWithinThreshold({
  required List<File> files,
  required RegExp pattern,
  required int maxAllowed,
  required String tokenName,
  required String guidance,
}) {
  var total = 0;
  final fileViolations = <String, List<String>>{};

  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (pattern.hasMatch(line)) {
        total++;
        final cleanPath = file.path.replaceAll('\\', '/');
        fileViolations.putIfAbsent(cleanPath, () => []).add('  line ${i + 1}: ${line.trim()}');
      }
    }
  }

  if (total > maxAllowed) {
    final buffer = StringBuffer();
    buffer.writeln('$tokenName 超出上限：实测 $total 处，允许门槛 ≤$maxAllowed 处。$guidance\n违规明细列表：');
    for (final entry in fileViolations.entries) {
      buffer.writeln('${entry.key} (${entry.value.length} 处):');
      for (final matchLine in entry.value) {
        buffer.writeln(matchLine);
      }
    }
    fail(buffer.toString());
  }

  expect(total, lessThanOrEqualTo(maxAllowed));
}
