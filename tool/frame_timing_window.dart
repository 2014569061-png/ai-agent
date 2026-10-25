/// A boundary captured in the transient phase and completed after drawFrame.
class DesktopFrameBoundary {
  const DesktopFrameBoundary(this.frameNumber, this.vsyncStartUs);
  final int frameNumber, vsyncStartUs;
}

/// Pure sample-window policy shared by the release harness and unit tests.
/// Engine timing callbacks may arrive late, out of order, or in batches.
class DesktopFrameSample {
  const DesktopFrameSample({
    required this.frameNumber,
    required this.vsyncStartUs,
    required this.buildUs,
    required this.rasterUs,
    required this.vsyncOverheadUs,
    required this.totalSpanUs,
  });
  final int frameNumber, vsyncStartUs, buildUs, rasterUs;
  final int vsyncOverheadUs, totalSpanUs;
}

int samplePercentile(List<int> values, double percentile) {
  if (values.isEmpty) {
    throw StateError('Missing samples: percentile is undefined');
  }
  if (!percentile.isFinite || percentile <= 0 || percentile > 1) {
    throw ArgumentError.value(percentile, 'percentile');
  }
  final ordered = [...values]..sort();
  return ordered[(ordered.length * percentile).ceil() - 1];
}

Map<String, Object> summarizeFrameWindow(
  Iterable<DesktopFrameSample> samples, {
  required int afterFrame,
  required int throughFrame,
  required int minimumSamples,
  required double refreshHz,
}) {
  if (afterFrame >= throughFrame ||
      minimumSamples < 1 ||
      !refreshHz.isFinite ||
      refreshHz <= 0) {
    throw ArgumentError('Invalid frame window, minimum count, or refresh rate');
  }
  final byFrame = <int, DesktopFrameSample>{};
  for (final sample in samples) {
    if (sample.frameNumber > afterFrame && sample.frameNumber <= throughFrame) {
      if (sample.buildUs < 0 ||
          sample.rasterUs < 0 ||
          sample.vsyncOverheadUs < 0 ||
          sample.totalSpanUs < 0) {
        throw StateError('Invalid negative engine timing');
      }
      byFrame[sample.frameNumber] = sample;
    }
  }
  final window = byFrame.values.toList()
    ..sort((a, b) => a.frameNumber.compareTo(b.frameNumber));
  if (window.length < minimumSamples) {
    throw StateError('Missing frame samples: got ${window.length}, '
        'require $minimumSamples in ($afterFrame, $throughFrame]');
  }
  final budget = 1000000 / refreshHz;
  final intervals = [
    for (var i = 1; i < window.length; i++)
      window[i].vsyncStartUs - window[i - 1].vsyncStartUs
  ];
  return {
    'samplesComplete': true,
    'minimumSamples': minimumSamples,
    'frames': window.length,
    'afterFrame': afterFrame,
    'throughFrame': throughFrame,
    'buildP95Us': samplePercentile(window.map((f) => f.buildUs).toList(), .95),
    'rasterP95Us':
        samplePercentile(window.map((f) => f.rasterUs).toList(), .95),
    'vsyncOverheadP95Us':
        samplePercentile(window.map((f) => f.vsyncOverheadUs).toList(), .95),
    'totalSpanP95Us':
        samplePercentile(window.map((f) => f.totalSpanUs).toList(), .95),
    if (intervals.isNotEmpty)
      'frameIntervalP95Us': samplePercentile(intervals, .95),
    'displayBudgetUs': budget,
    'jankAtDisplayRate':
        window.where((f) => f.buildUs > budget || f.rasterUs > budget).length,
    'reference60HzPassed':
        samplePercentile(window.map((f) => f.buildUs).toList(), .95) <= 16667 &&
            samplePercentile(window.map((f) => f.rasterUs).toList(), .95) <=
                16667,
  };
}
