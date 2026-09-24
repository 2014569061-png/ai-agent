import 'dart:convert';

import 'models.dart';

/// Optional, versioned display-only data. Never contains provider credentials,
/// and never changes the message text supplied to the model.
class MessageDisplayMetadata {
  const MessageDisplayMetadata._();

  static String? encode(ChatMessage message) {
    final usage = message.usage;
    final fields = <String, Object>{
      if (message.modelName != null) 'modelName': message.modelName!,
      if (message.elapsed != null) 'elapsedUs': message.elapsed!.inMicroseconds,
      if (message.ttft != null) 'ttftUs': message.ttft!.inMicroseconds,
      if (message.reasoningDuration != null)
        'reasoningUs': message.reasoningDuration!.inMicroseconds,
      if (usage != null)
        'usage': {
          'promptTokens': usage.promptTokens,
          'completionTokens': usage.completionTokens,
          'cachedTokens': usage.cachedTokens,
          'cacheWriteTokens': usage.cacheWriteTokens,
          'reasoningTokens': usage.reasoningTokens,
          'usageReported': usage.usageReported,
          'cacheStatsReported': usage.cacheStatsReported,
        },
    };
    return fields.isEmpty ? null : jsonEncode({'version': 1, ...fields});
  }

  static ChatMessage restore(ChatMessage message, String? encoded) {
    if (encoded == null || encoded.isEmpty || encoded.length > 16384) {
      return message;
    }
    try {
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic> || data['version'] != 1) return message;
      final model = data['modelName'];
      final rawUsage = data['usage'];
      final usage = rawUsage is Map<String, dynamic>
          ? Usage(
              promptTokens: _integer(rawUsage['promptTokens']) ?? 0,
              completionTokens: _integer(rawUsage['completionTokens']) ?? 0,
              cachedTokens: _integer(rawUsage['cachedTokens']) ?? 0,
              cacheWriteTokens: _integer(rawUsage['cacheWriteTokens']) ?? 0,
              reasoningTokens: _integer(rawUsage['reasoningTokens']) ?? 0,
              usageReported: rawUsage['usageReported'] == true,
              cacheStatsReported: rawUsage['cacheStatsReported'] == true,
            )
          : null;
      return message.copyWith(
        modelName: model is String && model.length <= 512 ? model : null,
        elapsed: _duration(data['elapsedUs']),
        ttft: _duration(data['ttftUs']),
        reasoningDuration: _duration(data['reasoningUs']),
        usage: usage,
      );
    } catch (_) {
      // Legacy/imported malformed metadata must not hide the message body.
      return message;
    }
  }

  static int? _integer(Object? value) =>
      value is int && value >= 0 && value <= 31536000000000 ? value : null;

  static Duration? _duration(Object? value) {
    final microseconds = _integer(value);
    return microseconds == null ? null : Duration(microseconds: microseconds);
  }
}
