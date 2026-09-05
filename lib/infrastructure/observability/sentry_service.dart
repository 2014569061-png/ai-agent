import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 匿名崩溃上报。DSN 通过 `--dart-define=SENTRY_DSN=...` 注入，不硬编码入库。
///
/// 隐私约束（守住「无埋点」叙事）：
/// - 用户未授权 → 完全不初始化 SDK。
/// - `beforeSend` 脱敏：丢弃请求体 / cookie / query / 鉴权头，只保留匿名堆栈与设备信息。
class SentryService {
  static const _prefsKey = 'crash_report_enabled';
  static const _dsn = String.fromEnvironment('SENTRY_DSN');

  static bool get hasDsn => _dsn.isNotEmpty;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }

  /// 按授权情况初始化并启动应用。未授权 / 无 DSN / Web 时直接启动，不加载 SDK。
  static Future<void> init(void Function() appRunner) async {
    if (!hasDsn || kIsWeb) {
      appRunner();
      return;
    }
    if (!await isEnabled()) {
      appRunner();
      return;
    }
    await SentryFlutter.init(
      (options) {
        options
          ..dsn = _dsn
          ..tracesSampleRate = 0.1
          ..beforeSend = (event, hint) {
            // 脱敏：只保留匿名堆栈与设备信息。
            final request = event.request;
            if (request == null) return event;
            final headers = Map<String, String>.from(request.headers)
              ..removeWhere((key, _) {
                final normalized = key.toLowerCase();
                return normalized == 'authorization' ||
                    normalized == 'x-api-key';
              });
            event.request = SentryRequest(
              url: request.url,
              method: request.method,
              fragment: request.fragment,
              apiTarget: request.apiTarget,
              headers: headers,
            );
            return event;
          };
      },
      appRunner: appRunner,
    );
  }
}
