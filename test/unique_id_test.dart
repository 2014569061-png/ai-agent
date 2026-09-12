import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/unique_id.dart';

void main() {
  test('generates distinct ids when clock does not advance', () {
    final now = DateTime.fromMicrosecondsSinceEpoch(123456789);
    final ids = <String>{};

    for (var i = 0; i < 1000; i++) {
      expect(ids.add(UniqueId.generate('row', now: now)), isTrue);
    }
  });

  test('preserves the requested prefix and timestamp', () {
    final now = DateTime.fromMicrosecondsSinceEpoch(42);

    expect(UniqueId.generate('memory', now: now), startsWith('memory-42-'));
  });
}
