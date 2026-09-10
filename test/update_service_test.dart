import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/infrastructure/update/update_service.dart';

void main() {
  test('parses GitHub SHA-256 sidecar formats', () {
    const digest =
        '4cec4b6b0e26d501e29b884cc401a8962d16527435d1c1ecda69aa67f7d8b3a8';
    expect(UpdateService.parseSha256('$digest  app-release.apk'), digest);
    expect(UpdateService.parseSha256('sha256:$digest'), digest);
    expect(UpdateService.parseSha256('invalid checksum'), isNull);
  });

  group('isNewer', () {
    test('0.8.6.1 对 0.8.6 是更新（第四段可比较）', () {
      expect(UpdateService.isNewer('0.8.6.1', '0.8.6'), isTrue);
    });

    test('0.8.6.2 对 0.8.6.1 是更新', () {
      expect(UpdateService.isNewer('0.8.6.2', '0.8.6.1'), isTrue);
    });

    test('0.8.6.1 对 0.8.6.2 不是更新', () {
      expect(UpdateService.isNewer('0.8.6.1', '0.8.6.2'), isFalse);
    });

    test('相同版本不是更新', () {
      expect(UpdateService.isNewer('0.8.6', '0.8.6'), isFalse);
      expect(UpdateService.isNewer('0.8.6.1', '0.8.6.1'), isFalse);
    });

    test('0.8.7 对 0.8.6 是更新', () {
      expect(UpdateService.isNewer('0.8.7', '0.8.6'), isTrue);
    });

    test('缺段按 0 补位：0.9 对 0.8.6 是更新，0.8 对 0.8.6 不是', () {
      expect(UpdateService.isNewer('0.9', '0.8.6'), isTrue);
      expect(UpdateService.isNewer('0.8', '0.8.6'), isFalse);
    });
  });
}
