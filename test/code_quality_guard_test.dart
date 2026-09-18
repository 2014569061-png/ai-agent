import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presentation token escape counts do not grow', () {
    final source = _readDartFiles('lib/presentation');

    expect(
      _count(source, RegExp(r'Color\s*\(\s*0x[0-9A-Fa-f]+')),
      lessThanOrEqualTo(182),
      reason: '新增颜色应收敛到语义 token；有意迁移时同步调整基线。',
    );
    expect(
      _count(source, RegExp(r'fontSize\s*:\s*[0-9]+(?:\.[0-9]+)?')),
      lessThanOrEqualTo(450),
      reason: '新增字号应使用已决策的字号 token；有意迁移时同步调整基线。',
    );
    expect(
      _count(
        source,
        RegExp(
          r'Duration\s*\(\s*(?:milliseconds|seconds|microseconds)\s*:\s*[0-9]+',
        ),
      ),
      lessThanOrEqualTo(35),
      reason: '新增动画时长应使用 NexusMotion token。',
    );
  });
}

List<File> _readDartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where(
        (file) => file.path.endsWith('.dart') && !file.path.endsWith('.g.dart'))
    .toList();

int _count(Iterable<File> files, RegExp pattern) {
  var total = 0;
  for (final file in files) {
    total += pattern.allMatches(file.readAsStringSync()).length;
  }
  return total;
}
