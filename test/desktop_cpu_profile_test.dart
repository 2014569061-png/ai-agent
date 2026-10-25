import 'package:flutter_test/flutter_test.dart';
import '../tool/desktop_cpu_profile.dart';

void main() {
  test('CPU summaries separate exclusive work from inclusive callers', () {
    final profile = <String, dynamic>{
      'sampleCount': 100,
      'samplePeriod': 1000,
      'functions': [
        {
          'function': {'name': 'caller'},
          'exclusiveTicks': 1,
          'inclusiveTicks': 95
        },
        {
          'function': {'name': 'hotLayout'},
          'exclusiveTicks': 60,
          'inclusiveTicks': 70
        },
      ]
    };
    final summary = summarizeDesktopCpuProfile(profile);
    expect(summary['sampleCount'], 100);
    expect((summary['topExclusive'] as List).first['name'], 'hotLayout');
    expect((summary['topInclusive'] as List).first['name'], 'caller');
    expect((profile['functions'] as List).first['function']['name'], 'caller');
  });
  test('empty CPU samples fail instead of producing a zero-cost profile', () {
    expect(
        () => summarizeDesktopCpuProfile({'sampleCount': 0, 'functions': []}),
        throwsStateError);
  });
  test('CPU summary bounds output without dropping the hottest function', () {
    final summary = summarizeDesktopCpuProfile({
      'sampleCount': 100,
      'samplePeriod': 1000,
      'functions': List.generate(
          80,
          (i) => {
                'function': {'name': 'f$i'},
                'exclusiveTicks': i,
                'inclusiveTicks': i
              })
    });
    final hottest = summary['topExclusive'] as List;
    expect(hottest.length, 35);
    expect(hottest.first['name'], 'f79');
  });
}
