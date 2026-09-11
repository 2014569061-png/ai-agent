import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A-2 分层守护：锁定依赖方向，防止反向依赖复发。
///
/// 允许的依赖方向：domain →（无）；application → domain, infrastructure；
/// infrastructure → domain；presentation → domain, application, infrastructure。
/// 历史上 infrastructure → application 反向依赖曾达 6 处（形成环），
/// 2026-09-12 已清零 —— 本测试防复发。
void main() {
  const libRoot = 'lib';

  List<File> dartFilesUnder(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();

  test('lib/domain 不依赖 application / infrastructure', () {
    final violations = <String>[];
    for (final file in dartFilesUnder('$libRoot/domain')) {
      final src = file.readAsStringSync();
      if (src.contains("import '../application/")) {
        violations.add(file.path);
      }
      if (src.contains("import '../infrastructure/")) {
        violations.add(file.path);
      }
    }
    expect(violations, isEmpty, reason: 'domain 层必须零依赖');
  });

  test('lib/infrastructure 不反向依赖 application（A-2）', () {
    final violations = <String>[];
    for (final file in dartFilesUnder('$libRoot/infrastructure')) {
      final src = file.readAsStringSync();
      final lines = src.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains("import '../application/") ||
            line.contains("import '../../application/")) {
          violations.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'infrastructure → application 反向依赖已清零，请把编排逻辑'
            '搬到 application，或在 domain 定义端口');
  });
}
