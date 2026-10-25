import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/scheduler.dart';
import '../tool/desktop_frame_pump.dart';
import '../tool/frame_timing_window.dart';

DesktopFrameSample frame(int id, int time, {int build = 10}) =>
    DesktopFrameSample(
      frameNumber: id,
      vsyncStartUs: time,
      buildUs: build,
      rasterUs: 2,
      vsyncOverheadUs: 1,
      totalSpanUs: build + 3,
    );

void main() {
  testWidgets('frame pump requested during post-frame waits for the next frame',
      (tester) async {
    Future<DesktopFrameBoundary>? nested;
    var nestedCompleted = false;
    final first = nextRenderedFrame();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      nested = nextRenderedFrame();
      nested!.then((_) => nestedCompleted = true);
    });
    await tester.pump(const Duration(milliseconds: 16));
    final firstStamp = await first;
    expect(nestedCompleted, false);
    await tester.pump(const Duration(milliseconds: 16));
    expect((await nested!).vsyncStartUs, greaterThan(firstStamp.vsyncStartUs));
    expect(nestedCompleted, true);
  });
  Map<String, Object> summarize(List<DesktopFrameSample> frames,
          {int count = 2}) =>
      summarizeFrameWindow(frames,
          afterFrame: 1,
          throughFrame: 3,
          minimumSamples: count,
          refreshHz: 240);

  test('frame IDs reject late previous-scene and future-scene samples', () {
    final result = summarize([
      frame(4, 400, build: 999999),
      frame(1, 100, build: 999999),
      frame(3, 300, build: 20),
      frame(2, 200),
      frame(2, 200),
    ]);
    expect(result['frames'], 2);
    expect(result['buildP95Us'], 20);
    expect(result['frameIntervalP95Us'], 100);
    expect(result['samplesComplete'], true);
  });
  test('empty or insufficient callbacks never become zero-cost success', () {
    expect(() => summarize([]), throwsStateError);
    expect(() => summarize([frame(2, 200)]), throwsStateError);
    expect(() => samplePercentile([], .95), throwsStateError);
  });
  test('boundary frame is assigned to only one adjacent scenario', () {
    final samples = [
      frame(1, 100),
      frame(2, 200),
      frame(3, 300),
      frame(4, 400)
    ];
    expect(summarize(samples)['frames'], 2);
    final next = summarizeFrameWindow(samples,
        afterFrame: 3, throughFrame: 4, minimumSamples: 1, refreshHz: 60);
    expect(next['frames'], 1);
    expect(next['buildP95Us'], 10);
  });
  test('nearest-rank percentile uses ceiling and does not mutate samples', () {
    final values = [4, 1, 3, 2];
    expect(samplePercentile(values, .95), 4);
    expect(samplePercentile(values, .5), 2);
    expect(values, [4, 1, 3, 2]);
  });
  test('invalid windows and display rates fail explicitly', () {
    expect(
        () => summarizeFrameWindow([],
            afterFrame: 3, throughFrame: 1, minimumSamples: 1, refreshHz: 60),
        throwsArgumentError);
    expect(
        () => summarizeFrameWindow([],
            afterFrame: 1, throughFrame: 3, minimumSamples: 0, refreshHz: 60),
        throwsArgumentError);
    expect(
        () => summarizeFrameWindow([],
            afterFrame: 1, throughFrame: 3, minimumSamples: 1, refreshHz: 0),
        throwsArgumentError);
    expect(() => summarize([frame(2, 200, build: -1), frame(3, 300)]),
        throwsStateError);
  });
  test('performance budget failure remains visible with complete samples', () {
    final result = summarize([frame(2, 200, build: 20000), frame(3, 300)]);
    expect(result['samplesComplete'], true);
    expect(result['reference60HzPassed'], false);
    expect(result['jankAtDisplayRate'], 1);
  });
}
