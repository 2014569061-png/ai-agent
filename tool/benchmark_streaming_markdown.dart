import 'dart:convert';
import 'dart:io';
import 'package:mobile_agent/presentation/markdown/markdown_render_policy.dart';

/// Host-only microbenchmark. The reference rescans with a fresh scanner; it is
/// not a measurement of an older release or Flutter's frame/paint performance.
/// Run: dart run tool/benchmark_streaming_markdown.dart > benchmark.json
void main() {
  final cases = <Map<String, Object>>[];
  var checksum = 0;
  for (final length in [2000, 10000, 50000]) {
    for (final paragraphs in [false, true]) {
      final unit = paragraphs ? 'paragraph **bold**\n\n' : 'abcdefghij';
      final text = (unit * (length ~/ unit.length + 1)).substring(0, length);
      final frames = [
        for (var end = 100; end <= length; end += 100) text.substring(0, end)
      ];
      final freshTimes = <int>[];
      final incrementalTimes = <int>[];
      int incrementalScanned = 0;
      for (var sample = -2; sample < 7; sample++) {
        // Alternate order to reduce systematic first-run bias; two warmups.
        for (final incremental
            in sample.isEven ? [true, false] : [false, true]) {
          final scanner = StreamingMarkdownScanner();
          final timer = Stopwatch()..start();
          for (final frame in frames) {
            final result = incremental
                ? scanner.update(frame)
                : MarkdownRenderPolicy.splitForStreaming(frame);
            checksum += result.stable.length + result.tail.length;
          }
          timer.stop();
          if (sample >= 0) {
            (incremental ? incrementalTimes : freshTimes)
                .add(timer.elapsedMicroseconds);
          }
          if (incremental) incrementalScanned = scanner.scannedCharacters;
        }
      }
      int median(List<int> values) {
        values.sort();
        return values[values.length ~/ 2];
      }

      cases.add({
        'characters': length,
        'fixture': paragraphs ? 'paragraphs' : 'single-paragraph',
        'frames': frames.length,
        'appendCharacters': 100,
        'samples': 7,
        'freshScannerMedianUs': median(freshTimes),
        'incrementalScannerMedianUs': median(incrementalTimes),
        'freshScannedCharacters':
            frames.fold<int>(0, (sum, frame) => sum + frame.length),
        'incrementalScannedCharacters': incrementalScanned,
      });
    }
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'schema': 1,
    'utc': DateTime.now().toUtc().toIso8601String(),
    'os': Platform.operatingSystem,
    'dart': Platform.version,
    'processors': Platform.numberOfProcessors,
    'peakRssBytes': ProcessInfo.maxRss,
    'note': 'Host JIT microbenchmark only. Prefix checks and substring allocations remain. '
        'Fresh scanner reference is not a pre-change release. No device FPS or memory-reduction claim.',
    'checksum': checksum,
    'cases': cases,
  }));
}
