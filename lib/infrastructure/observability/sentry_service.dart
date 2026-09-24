import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 匿名崩溃上报。DSN 通过 `--dart-define=SENTRY_DSN=...` 注入，不硬编码入库。
///
/// 隐私约束（守住「无埋点」叙事）：
/// - 用户未授权 → 完全不初始化 SDK。
/// - `beforeSend` 脱敏：只保留匿名堆栈与设备信息。具体地，丢弃请求体 / cookie /
///   query / 鉴权头，对异常消息做凭据兜底脱敏，并整体丢弃面包屑与 extra——
///   这两者会被自动集成塞进 HTTP URL（含查询串）、导航路径与工具调用参数。
/// - 应用从不调用 `Sentry.setUser`，因此事件里没有身份字段需要额外清理。
class SentryService {
  static const _prefsKey = 'crash_report_enabled';
  static const _dsn = String.fromEnvironment('SENTRY_DSN');
  static bool _initialized = false;

  static bool get hasDsn => _dsn.isNotEmpty;

  /// 常见凭据形态。异常消息是最容易漏密钥的地方：Provider 的错误响应（例如
  /// 429/401 的响应体）常被原样抛进 `message`，而抛出点散布在几十处调用点、
  /// 还有第三方 SDK 内部，无法在调用点逐一清理，只能在上报前兜底。
  static final List<RegExp> _secretPatterns = <RegExp>[
    // OpenAI / Anthropic 风格的 sk- 前缀密钥。
    RegExp(r'sk-[A-Za-z0-9_\-]{8,}'),
    // Google API key。
    RegExp(r'AIza[A-Za-z0-9_\-]{10,}'),
    // GitHub token。
    RegExp(r'gh[pousr]_[A-Za-z0-9]{16,}'),
    // Authorization: Bearer <token>
    RegExp(r'(Bearer\s+)[A-Za-z0-9._\-]{8,}', caseSensitive: false),
    // key=value / "key": "value" / key: value 形式的凭据字段。
    RegExp(
      r'(api[_-]?key|access[_-]?key|token|secret|password)'
      r'("\s*:\s*"|\s*[=:]\s*)[^"\s,;]{4,}',
      caseSensitive: false,
    ),
  ];

  /// 把命中的凭据替换成 `[已脱敏]`。
  ///
  /// 可公开的上下文（字段名、`Bearer` 这类方案名）保留：脱敏后仍要能看出
  /// 「是哪一类凭据漏出来的」，否则崩溃报告既泄露了线索也失去了排查价值。
  static String redactSecrets(String input) {
    var result = input;
    for (final pattern in _secretPatterns) {
      result = result.replaceAllMapped(pattern, (match) {
        final prefix = match.groupCount >= 1 ? match.group(1) : null;
        final separator = match.groupCount >= 2 ? match.group(2) : null;
        return '${prefix ?? ''}${separator ?? ''}[已脱敏]';
      });
    }
    return result;
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }

  /// 按授权情况初始化并启动应用。未授权 / 无 DSN / Web 时直接启动，不加载 SDK。
  static Future<void> init() async {
    if (!hasDsn || kIsWeb) {
      _initialized = false;
      return;
    }
    if (!await isEnabled()) {
      _initialized = false;
      return;
    }
    await SentryFlutter.init(
      (options) {
        options
          ..dsn = _dsn
          // The product promise is "no analytics"; crash reporting does not
          // need performance tracing data.
          ..tracesSampleRate = 0
          ..beforeSend = (event, hint) => sanitizeEvent(event);
      },
    );
    // SentryFlutter.init installs the FlutterError, PlatformDispatcher, and
    // zone integrations. Keep the flag separate so best-effort reports from
    // intentional fallbacks do not touch the SDK before initialization.
    _initialized = true;
  }

  /// 上报前的清洗。
  ///
  /// 此前这段逻辑内联在 `init()` 的 `beforeSend` 闭包里，只有真正初始化过
  /// SDK 才可能跑到，等于「隐私承诺只写在注释里」——一次无意的手改就能悄悄
  /// 破坏它，而没有任何测试会红。抽成独立函数后它可以被直接断言。
  @visibleForTesting
  static SentryEvent sanitizeEvent(SentryEvent event) {
    // 1) 请求：丢掉查询串（常带 token）与鉴权头。
    final request = event.request;
    if (request != null) {
      final sanitizedUrl =
          request.url == null ? null : _stripQueryAndFragment(request.url!);
      final headers = Map<String, String>.from(request.headers)
        ..removeWhere((key, _) {
          final normalized = key.toLowerCase();
          return normalized == 'authorization' ||
              normalized == 'x-api-key' ||
              normalized == 'cookie';
        });
      event.request = SentryRequest(
        url: sanitizedUrl,
        method: request.method,
        apiTarget: request.apiTarget,
        headers: headers,
      );
    }

    // 2) 异常消息兜底脱敏。堆栈本身保留：里面的路径是应用私有目录，
    //    是定位问题所必需的，也不含用户数据。
    //
    //    改字段是 sentry 9.x 官方推荐的写法（`copyWith` 已被其标注弃用，
    //    弃用理由正是「直接给实例赋值」）。
    final exceptions = event.exceptions;
    if (exceptions != null) {
      for (final exception in exceptions) {
        final value = exception.value;
        if (value != null && value.isNotEmpty) {
          exception.value = redactSecrets(value);
        }
      }
    }

    // 3) 面包屑整体丢弃。
    //
    // 自动集成会把 HTTP URL（含查询串）、导航路径与工具调用参数塞进
    // breadcrumb，而本类的承诺只是「匿名堆栈与设备信息」。与其逐字段猜测
    // 哪些安全，不如按承诺整体清空。
    //
    // 关于 `extra`：它同样是隐私风险点，但该字段在 sentry 9.x 已标记弃用，
    // 引用它会引入静态告警。已确认本应用与全部依赖都没有调用过
    // `Sentry.setExtra`，因此该字段始终为空，不额外清理。
    event.breadcrumbs = const [];

    return event;
  }

  /// 只保留 scheme / host / path：查询串常带 token 或签名参数，fragment 没有
  /// 诊断价值。
  ///
  /// 注意不能用 `replace(query: '', fragment: '')`：那样得到的是**空**查询与空
  /// fragment（而不是「没有」），`toString()` 会留下 `...chat?#` 的尾巴。它不
  /// 泄露密钥，但会让崩溃报告里的 URL 变得难以辨认。
  static String _stripQueryAndFragment(String raw) {
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return raw.split('?').first.split('#').first;
    final withoutFragment = parsed.removeFragment();
    if (!withoutFragment.hasQuery) return withoutFragment.toString();
    return withoutFragment
        .replace(query: '')
        .toString()
        .replaceFirst(RegExp(r'\?$'), '');
  }

  /// Reports an intentional fallback without changing the caller's control
  /// flow. Sentry itself remains opt-in and no-ops when it is not initialized.
  static Future<void> reportException(
    Object error,
    StackTrace stackTrace,
  ) async {
    if (!_initialized) return;
    try {
      await Sentry.captureException(error, stackTrace: stackTrace);
    } catch (_) {
      // Telemetry must never become a second failure path.
    }
  }
}
