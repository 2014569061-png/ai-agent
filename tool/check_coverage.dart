import 'dart:io';

/// 覆盖率门槛检查。
///
/// 用法：`dart run tool/check_coverage.dart [lcov 路径] [最低百分比]`
///
/// 关键点：分母**排除生成代码**。
///
/// 旧实现只累加每条记录的 LF/LH，完全忽略 `SF:`（源文件）行，于是
/// `app_database.g.dart` 这类 Drift 生成文件也进了分母——它有一万行、覆盖率
/// 只有三成多，单它一个就稀释掉约四分之一的分母。结果是门槛数值看着挺高，
/// 实际约束的是「生成代码被顺带跑到多少行」，而不是我们写的代码质量。
/// 生成文件不是人写的、也不该由人写测试，把它算进门槛只会让门槛失去意义。
void main(List<String> args) {
  final path = args.isEmpty ? 'coverage/lcov.info' : args.first;
  final minimum = args.length > 1 ? double.parse(args[1]) : 48.5;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Coverage file not found: $path');
    exitCode = 1;
    return;
  }

  final records = _readRecords(file.readAsLinesSync());
  var all = const _Coverage();
  var authored = const _Coverage();
  for (final record in records) {
    all += record.coverage;
    if (!record.generated) authored += record.coverage;
  }

  stdout.writeln(
    'Coverage (authored code): ${authored.percent.toStringAsFixed(2)}% '
    '(${authored.hitLines}/${authored.totalLines})',
  );
  stdout.writeln(
    'Coverage (including generated): ${all.percent.toStringAsFixed(2)}% '
    '(${all.hitLines}/${all.totalLines})',
  );
  if (authored.totalLines == 0) {
    stderr.writeln('No authored source lines found in $path');
    exitCode = 1;
    return;
  }
  if (authored.percent < minimum) {
    stderr.writeln(
      'Coverage ${authored.percent.toStringAsFixed(2)}% is below the minimum '
      '${minimum.toStringAsFixed(2)}%.',
    );
    exitCode = 1;
  }
}

/// 生成代码的判定。
///
/// 覆盖 Dart 生态常见的生成后缀（build_runner 系）与生成目录；判定放在文件名
/// 层面，避免依赖各代码生成器把 `generated` 标记写进 lcov。
bool _isGenerated(String sourcePath) {
  final normalized = sourcePath.replaceAll('\\', '/').toLowerCase();
  const suffixes = [
    '.g.dart',
    '.freezed.dart',
    '.gr.dart',
    '.mocks.dart',
    '.gql.dart',
    '.config.dart',
  ];
  if (suffixes.any(normalized.endsWith)) return true;
  return normalized.contains('/generated/') ||
      normalized.contains('/.dart_tool/');
}

List<_Record> _readRecords(List<String> lines) {
  final records = <_Record>[];
  var totalLines = 0;
  var hitLines = 0;
  var source = '';
  for (final line in lines) {
    if (line.startsWith('SF:')) {
      source = line.substring(3).trim();
    } else if (line.startsWith('LF:')) {
      totalLines = int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      hitLines = int.parse(line.substring(3));
    } else if (line == 'end_of_record') {
      records.add(_Record(
        coverage: _Coverage(totalLines: totalLines, hitLines: hitLines),
        // 没有 SF: 的畸形记录按「手写代码」处理：宁可把它留在门槛里，
        // 也不要因为解析问题悄悄放行。
        generated: source.isNotEmpty && _isGenerated(source),
      ));
      totalLines = 0;
      hitLines = 0;
      source = '';
    }
  }
  return records;
}

class _Record {
  const _Record({required this.coverage, required this.generated});

  final _Coverage coverage;
  final bool generated;
}

class _Coverage {
  const _Coverage({this.totalLines = 0, this.hitLines = 0});

  final int totalLines;
  final int hitLines;

  double get percent => totalLines == 0 ? 100 : hitLines * 100 / totalLines;

  _Coverage operator +(_Coverage other) => _Coverage(
        totalLines: totalLines + other.totalLines,
        hitLines: hitLines + other.hitLines,
      );
}
