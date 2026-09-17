import 'dart:io';

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
  final total = records.fold<_Coverage>(
    const _Coverage(),
    (sum, record) => sum + record,
  );
  final percent = total.percent;
  stdout.writeln(
    'Coverage: ${percent.toStringAsFixed(2)}% '
    '(${total.hitLines}/${total.totalLines})',
  );
  if (percent < minimum) {
    stderr.writeln(
      'Coverage ${percent.toStringAsFixed(2)}% is below the minimum '
      '${minimum.toStringAsFixed(2)}%.',
    );
    exitCode = 1;
  }
}

List<_Coverage> _readRecords(List<String> lines) {
  final records = <_Coverage>[];
  var totalLines = 0;
  var hitLines = 0;
  for (final line in lines) {
    if (line.startsWith('LF:')) {
      totalLines = int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      hitLines = int.parse(line.substring(3));
    } else if (line == 'end_of_record') {
      records.add(_Coverage(totalLines: totalLines, hitLines: hitLines));
      totalLines = 0;
      hitLines = 0;
    }
  }
  return records;
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
