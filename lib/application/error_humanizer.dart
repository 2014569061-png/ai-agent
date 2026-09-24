import 'dart:convert';

import '../domain/model_failure.dart';

/// 人话化错误摘要 + 保留原文的技术细节。
class HumanizedError {
  const HumanizedError({
    required this.summary,
    required this.detail,
    required this.failure,
  });

  final String summary;
  final String detail;
  final ModelFailure failure;
}

/// 消息正文中「技术细节」折叠块的标记，渲染侧按此拆分。
const String kErrorDetailMarker = '\n[技术细节]\n';

/// 把结构化失败映射为一句话人话，原始异常只保留在可折叠技术细节中。
HumanizedError humanizeError(
  String raw, {
  int? statusCode,
  String? failureKind,
  Duration? retryAfter,
}) {
  final text = raw.toLowerCase();
  final failure = ModelFailure.classify(
    raw,
    statusCode: statusCode,
    failureKind: failureKind,
    retryAfter: retryAfter,
  );
  final String summary;
  if (text.contains('xmlhttprequest') || text.contains('cors')) {
    summary = '网络请求被浏览器拦截（Web 版直连受 CORS 限制）。可改用桌面端，或在设置中配置代理网关。';
  } else {
    summary = switch (failure.serviceStatus) {
      ModelServiceStatus.offline => text.contains('timeout') ||
              text.contains('timed out') ||
              text.contains('timeoutexception')
          ? '请求超时，模型服务响应过慢，可重试。'
          : '连不上模型服务，请检查网络连接或服务地址。',
      ModelServiceStatus.authRequired => 'API 密钥无效或已过期，请到设置中检查模型服务配置。',
      ModelServiceStatus.rateLimited => retryAfter == null
          ? '触发服务限流，请稍后再试。'
          : '触发服务限流，请在 ${retryAfter.inSeconds} 秒后重试。',
      ModelServiceStatus.serverError => '模型服务暂时不可用，请稍后再试。',
      ModelServiceStatus.billing => '模型服务额度不足，请检查账户余额或用量限制。',
      ModelServiceStatus.online ||
      ModelServiceStatus.unknown =>
        '遇到未预期的错误，可点右上角重试；仍失败可展开下方技术细节反馈。',
    };
  }
  return HumanizedError(summary: summary, detail: raw, failure: failure);
}

/// 组装写入消息正文的错误段落：人话在前，原文进技术细节折叠。
String formatErrorForMessage(
  String raw, {
  int? statusCode,
  String? failureKind,
  Duration? retryAfter,
}) {
  final h = humanizeError(
    raw,
    statusCode: statusCode,
    failureKind: failureKind,
    retryAfter: retryAfter,
  );
  return '错误：${h.summary}$kErrorDetailMarker${h.detail}';
}

/// 拆分消息正文：主文本 + 技术细节（无标记时 detail 为 null）。
/// 兼容旧消息：正文含「错误：」段落且超长但无标记的，自动把错误段折叠。
({String main, String? detail}) splitErrorDetail(String text) {
  final markerIndex = text.indexOf(kErrorDetailMarker);
  if (markerIndex >= 0) {
    return (
      main: text.substring(0, markerIndex),
      detail: text.substring(markerIndex + kErrorDetailMarker.length),
    );
  }
  // 旧版消息兜底：错误段落超长且无标记时折叠后半段，避免整屏技术文本。
  final head = text.indexOf('\n错误：');
  if (head >= 0 && text.length - head > 200) {
    return (
      main: text.substring(0, head).trimRight(),
      detail: text.substring(head + 1)
    );
  }
  return (main: text, detail: null);
}

/// 消息正文中「可续跑暂停」提示的标记，后面紧跟一行 JSON 元数据。
///
/// 渲染侧识别后显示暂停提示卡（继续执行 / 从头重试 / 切换模型），不再把
/// 预算暂停渲染成「错误：遇到未预期的错误」。
const String kRunPauseMarker = '[[nexus:run-paused]]';

/// 旧版本把预算暂停写成错误段落，技术细节里是这句固定文案。必须连同技术
/// 细节标记一起匹配，避免回复正文里引用这句话时被误判成暂停。
const String _legacyBudgetPauseDetail = '$kErrorDetailMarker已达到单次执行步数预算';

/// 可续跑暂停的原因。
enum RunPauseKind {
  /// 达到单次任务的轮数上限。
  budget,

  /// 连续多次操作失败，自动熔断暂停。
  repeatedFailures,
}

/// 从消息正文解析出的暂停提示。
class RunPauseNotice {
  const RunPauseNotice({required this.kind, this.maxSteps, this.runId});

  final RunPauseKind kind;
  final int? maxSteps;
  final String? runId;

  String get title => switch (kind) {
        RunPauseKind.budget => maxSteps == null
            ? '已达到本次任务的轮数上限，暂停等待确认'
            : '已执行 $maxSteps 轮，暂停等待确认',
        RunPauseKind.repeatedFailures => '连续多次操作失败，已自动暂停',
      };

  String get description => switch (kind) {
        RunPauseKind.budget => '这不是手机的限制，而是单次任务的轮数上限，用来防止'
            '模型空转。点「继续执行」会从断点接着做，不会从头重复。',
        RunPauseKind.repeatedFailures => '为避免空转已先暂停。可以检查权限或环境后'
            '继续执行，也可以换个说法从头重试。',
      };
}

/// 组装写入消息正文的暂停提示：标记 + JSON 元数据占一行，下一行是一句人话
/// （复制、朗读或旧版本渲染时只会看到这句人话）。
String formatRunPauseForMessage({
  required RunPauseKind kind,
  required int maxSteps,
  String? runId,
}) {
  final notice = RunPauseNotice(kind: kind, maxSteps: maxSteps, runId: runId);
  final meta = jsonEncode({
    'kind': kind.name,
    'maxSteps': maxSteps,
    if (runId != null) 'runId': runId,
  });
  return '$kRunPauseMarker$meta\n${notice.title}。';
}

/// 拆分消息正文：暂停提示之前的正文 + 暂停提示（没有则 notice 为 null）。
({String main, RunPauseNotice? notice}) splitRunPauseNotice(String text) {
  final markerIndex = text.indexOf(kRunPauseMarker);
  if (markerIndex >= 0) {
    final metaStart = markerIndex + kRunPauseMarker.length;
    final lineEnd = text.indexOf('\n', metaStart);
    final meta = text.substring(metaStart, lineEnd < 0 ? text.length : lineEnd);
    return (
      main: text.substring(0, markerIndex).trimRight(),
      notice: _decodeRunPause(meta),
    );
  }
  final legacyIndex = text.indexOf(_legacyBudgetPauseDetail);
  if (legacyIndex >= 0) {
    final errorHead = text.lastIndexOf('错误：', legacyIndex);
    final cut = errorHead >= 0 ? errorHead : legacyIndex;
    return (
      main: text.substring(0, cut).trimRight(),
      notice: const RunPauseNotice(kind: RunPauseKind.budget),
    );
  }
  return (main: text, notice: null);
}

/// 去掉暂停标记与元数据，只保留那句人话（复制 / 朗读用）。
String stripRunPauseMarker(String text) {
  final markerIndex = text.indexOf(kRunPauseMarker);
  if (markerIndex < 0) return text;
  final lineEnd = text.indexOf('\n', markerIndex);
  final tail = lineEnd < 0 ? '' : text.substring(lineEnd + 1);
  return text.substring(0, markerIndex) + tail;
}

RunPauseNotice _decodeRunPause(String meta) {
  try {
    final decoded = jsonDecode(meta.trim());
    if (decoded is Map) {
      final kindName = decoded['kind']?.toString();
      final maxSteps = decoded['maxSteps'];
      return RunPauseNotice(
        kind: RunPauseKind.values.firstWhere(
          (kind) => kind.name == kindName,
          orElse: () => RunPauseKind.budget,
        ),
        maxSteps: maxSteps is num ? maxSteps.toInt() : null,
        runId: decoded['runId']?.toString(),
      );
    }
  } on FormatException {
    // 元数据损坏时仍按预算暂停展示，不影响继续执行。
  }
  return const RunPauseNotice(kind: RunPauseKind.budget);
}
