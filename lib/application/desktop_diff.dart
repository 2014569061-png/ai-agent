class DesktopDiffLine {
  const DesktopDiffLine(this.text,
      {this.oldLine, this.newLine, this.header = false});
  final String text;
  final int? oldLine, newLine;
  final bool header;
}

class DesktopDiffHunk {
  const DesktopDiffHunk(this.header, this.lines, this.patch);
  final String header, patch;
  final List<DesktopDiffLine> lines;
}

class DesktopDiff {
  const DesktopDiff(this.preamble, this.hunks);
  final List<String> preamble;
  final List<DesktopDiffHunk> hunks;
  static DesktopDiff parse(String text) {
    final preamble = <String>[], hunks = <DesktopDiffHunk>[];
    final source = text.split('\n');
    int oldLine = 0, newLine = 0;
    String? header;
    var raw = <String>[], lines = <DesktopDiffLine>[];
    void flush() {
      if (header != null) {
        hunks.add(DesktopDiffHunk(header, List.unmodifiable(lines),
            '${[...preamble, ...raw].join('\n')}\n'));
      }
    }

    final pattern = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');
    for (var i = 0; i < source.length; i++) {
      final line = source[i];
      if (line.isEmpty && i == source.length - 1) continue;
      final match = pattern.firstMatch(line);
      if (match != null) {
        flush();
        header = line;
        raw = [line];
        lines = [];
        oldLine = int.parse(match[1]!);
        newLine = int.parse(match[2]!);
      } else if (header == null) {
        preamble.add(line);
      } else {
        raw.add(line);
        if (line.startsWith('+')) {
          lines.add(DesktopDiffLine(line, newLine: newLine++));
        } else if (line.startsWith('-')) {
          lines.add(DesktopDiffLine(line, oldLine: oldLine++));
        } else if (line.startsWith(' ')) {
          lines.add(
              DesktopDiffLine(line, oldLine: oldLine++, newLine: newLine++));
        } else {
          lines.add(DesktopDiffLine(line, header: true));
        }
      }
    }
    flush();
    return DesktopDiff(preamble, hunks);
  }
}
