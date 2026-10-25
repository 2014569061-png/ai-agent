import 'dart:convert';

import '../domain/tool_result.dart';

/// Bounds the model-facing JSON envelope, not WebView extraction or IPC memory.
/// Identity/URL metadata is never silently rewritten. No continuation is offered.
class BrowserPayloadBudget {
  static const maxBytes = 32 * 1024;

  static ToolResult limit(ToolResult input, {int budget = maxBytes}) {
    if (budget < 512 || budget > maxBytes) {
      throw ArgumentError.value(budget, 'budget', 'must be 512..$maxBytes');
    }
    if (utf8.encode(input.encode()).length <= budget) return input;
    final data = <String, dynamic>{
      ...?input.data,
      'truncated': true,
      'payloadTruncated': true,
      'nodesTruncated': false,
      'textTruncated': false,
      'payloadMaxBytes': budget,
      'continuationAvailable': false,
    };
    ToolResult envelope() => ToolResult(
          ok: input.ok,
          code: input.code,
          message: input.message,
          effect: input.effect,
          data: data,
        );
    bool fits() => utf8.encode(envelope().encode()).length <= budget;

    final originalNodes = data['nodes'];
    if (originalNodes is List && originalNodes.isNotEmpty) {
      // Keep the largest prefix that fits; never mutate the transport snapshot.
      data['nodesTruncated'] = true;
      data['nodes'] = <dynamic>[];
      if (fits()) {
        var low = 0, high = originalNodes.length - 1, best = 0;
        while (low <= high) {
          final middle = (low + high) ~/ 2;
          data['nodes'] = originalNodes.sublist(0, middle);
          if (fits()) {
            best = middle;
            low = middle + 1;
          } else {
            high = middle - 1;
          }
        }
        data['nodes'] = originalNodes.sublist(0, best);
        return envelope();
      }
    }
    final text = data['text'];
    if (text is String && text.isNotEmpty) {
      data['textTruncated'] = true;
      data['text'] = '';
      if (fits()) {
        var low = 0, high = text.length, best = 0;
        while (low <= high) {
          final middle = (low + high) ~/ 2;
          final end = _safeEnd(text, middle);
          data['text'] = text.substring(0, end);
          if (fits()) {
            best = end;
            low = middle + 1;
          } else {
            high = middle - 1;
          }
        }
        data['text'] = text.substring(0, best);
        return envelope();
      }
    }
    // Do not forge a usable snapshot by stripping oversized identity metadata.
    // Preserve side effects even when the result cannot be delivered in full.
    return ToolResult.failure(
      code: 'BROWSER_PAYLOAD_TOO_LARGE',
      message: '浏览器必要元数据超出结果预算；请重新观察，勿盲目重复操作',
      effect: input.effect,
      data: {'payloadMaxBytes': budget, 'continuationAvailable': false},
    );
  }

  static int _safeEnd(String text, int end) {
    if (end > 0 && end < text.length) {
      final left = text.codeUnitAt(end - 1), right = text.codeUnitAt(end);
      if (left >= 0xd800 &&
          left <= 0xdbff &&
          right >= 0xdc00 &&
          right <= 0xdfff) {
        return end - 1;
      }
    }
    return end;
  }
}
