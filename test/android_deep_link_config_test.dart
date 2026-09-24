import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android deep links have one owner: app_links, not default Navigator',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final activity = RegExp(
      r'<activity\b[^>]*android:name="\.MainActivity"[\s\S]*?</activity>',
    ).firstMatch(manifest)?.group(0);
    expect(activity, isNotNull);
    expect(
        RegExp(
          r'<meta-data\b(?=[^>]*android:name="flutter_deeplinking_enabled")(?=[^>]*android:value="false")[^>]*/>',
        ).hasMatch(activity!),
        isTrue);
    expect(activity, contains('android.intent.action.VIEW'));
    expect(activity, contains('android.intent.category.BROWSABLE'));
    expect(activity, contains('android:scheme="nexus"'));
  });
}
