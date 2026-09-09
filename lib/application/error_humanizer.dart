
/// 人话化错误摘要 + 保留原文的技术细节。
class HumanizedError {
  const HumanizedError({required this.summary, required this.detail});
  final String summary;
  final String detail;
}

/// 消息正文中「技术细节」折叠块的标记，渲染侧按此拆分。
const String kErrorDetailMarker = '\n[技术细节]\n';

/// 把原始异常映射为一句话人话。规则按序匹配，命中即返回；全部未命中走兜底。
HumanizedError humanizeError(String raw) {
  final text = raw.toLowerCase();
  final String summary;
  if (text.contains('xmlhttprequest') || text.contains('cors')) {
    summary = '网络请求被浏览器拦截（Web 版直连受 CORS 限制）。可改用桌面端，或在设置中配置代理网关。';
  } else if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection errored') ||
      text.contains('network is unreachable')) {
    summary = '连不上模型服务，请检查网络连接或服务地址。';
  } else if (text.contains('timeoutexception') ||
      text.contains('timed out') ||
      text.contains('timeout')) {
    summary = '请求超时，模型服务响应过慢，可重试。';
  } else if (text.contains('401') ||
      text.contains('403') ||
      text.contains('invalid_api_key') ||
      text.contains('invalid api key') ||
      text.contains('unauthorized')) {
    summary = 'API 密钥无效或已过期，请到设置中检查模型服务配置。';
  } else if (text.contains('429') ||
      text.contains('rate limit') ||
      text.contains('quota')) {
    summary = '触发服务限流或额度不足，请稍后再试。';
  } else if (text.contains('500') ||
      text.contains('502') ||
      text.contains('503') ||
      text.contains('server error')) {
    summary = '模型服务暂时不可用，请稍后再试。';
  } else {
    summary = '遇到未预期的错误，可点右上角重试；仍失败可展开下方技术细节反馈。';
  }
  return HumanizedError(summary: summary, detail: raw);
}

/// 组装写入消息正文的错误段落：人话在前，原文进技术细节折叠。
String formatErrorForMessage(String raw) {
  final h = humanizeError(raw);
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
    return (main: text.substring(0, head).trimRight(), detail: text.substring(head + 1));
  }
  return (main: text, detail: null);
}
