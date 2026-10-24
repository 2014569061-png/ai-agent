import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sentry_service.dart';

/// 有意忽略的失败：调用方保持原有的吞掉语义，这里只补可观测性。
///
/// [phase] 是稳定的代码定位标识（如 `skillStore.delete`），仅用于调试输出，
/// 不要拼接动态内容。Sentry 只接收异常对象本身，遵循已有的上报授权策略。
void reportSilentFailure(String phase, Object error, StackTrace stackTrace) {
  if (kDebugMode) {
    debugPrint('[silent:$phase] ${error.runtimeType}');
  }
  unawaited(SentryService.reportException(error, stackTrace));
}
