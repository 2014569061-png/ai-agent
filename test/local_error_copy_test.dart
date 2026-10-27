import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/local_error_copy.dart';

void main() {
  test('插件通道缺失时给出可读结论而不是原始异常', () {
    final copy = LocalErrorCopy.of(
      MissingPluginException('No implementation found for method status'),
    );
    expect(copy.code, 'channel_unavailable');
    expect(copy.summary, contains('未提供该能力'));
    expect(copy.summary, isNot(contains('MissingPluginException')));
    expect(copy.detail, contains('No implementation found'));
  });

  test('权限类平台异常单独归类', () {
    final copy = LocalErrorCopy.of(
      PlatformException(code: 'PERMISSION_DENIED', message: 'denied'),
      action: '创建任务',
    );
    expect(copy.code, 'permission_denied');
    expect(copy.headline(), '创建任务失败：系统未授予所需权限，请在系统设置中允许后重试');
  });

  test('未知异常仍给出可操作的建议', () {
    final copy = LocalErrorCopy.of(StateError('boom'));
    expect(copy.code, 'unexpected');
    expect(copy.summary, contains('重试'));
    expect(copy.detail.length, lessThanOrEqualTo(301));
  });
}
