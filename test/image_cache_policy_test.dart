import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/presentation/widgets/image_cache_policy.dart';

void main() {
  test('background image decode width follows the physical viewport', () {
    expect(
      imageCacheWidthFor(logicalWidth: 400, devicePixelRatio: 3),
      1200,
    );
    expect(
      imageCacheWidthFor(logicalWidth: 1200, devicePixelRatio: 3),
      2048,
    );
    expect(
      imageCacheWidthFor(logicalWidth: 0, devicePixelRatio: 3),
      1,
    );
  });
}
