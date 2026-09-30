import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/models.dart';

/// ChatMessage 与会话日志 payload 之间的编解码。
///
/// 只编码**模型可见**的字段：role、parts、toolCallId、toolCalls、reasoning。
/// id、用量、耗时等展示元数据不进入模型请求，因此既不参与编码，也不参与
/// 内容哈希——同样内容的消息在日志里只存一份。
/// 拆出的附件内容。
typedef SessionBlobData = ({String data, String? mimeType});

abstract final class ChatMessageCodec {
  static Map<String, dynamic> encode(ChatMessage message) => {
        'role': message.role.name,
        'parts': [
          for (final part in message.parts)
            {
              'type': part.type,
              'value': part.value,
              if (part.mimeType != null) 'mimeType': part.mimeType,
            },
        ],
        if (message.toolCallId != null) 'toolCallId': message.toolCallId,
        if (message.toolCalls.isNotEmpty)
          'toolCalls': [
            for (final call in message.toolCalls)
              {
                'id': call.id,
                'name': call.name,
                'arguments': call.arguments,
                if (call.providerMetadata.isNotEmpty)
                  'providerMetadata': call.providerMetadata,
              },
          ],
        if (message.reasoning != null) 'reasoning': message.reasoning,
      };

  /// 超过这个长度的附件内容（图片、文件、音视频的 base64 或路径）不内联进
  /// 日志，改存 session_blobs，payload 里只留 `blob`（sha256）与 `size`。
  static const blobThreshold = 512;

  /// 附件缺失（已被清理）时代替原内容的文本。
  static const missingBlobText = '[附件已清理]';

  /// 日志用编码：与 [encode] 相同，但把大附件拆出为 blob。
  ///
  /// [contentKey] 仍按 [encode] 的完整内容计算，与拆分前的日志保持一致。
  static ({Map<String, dynamic> payload, Map<String, SessionBlobData> blobs})
      encodeForLog(ChatMessage message) {
    final payload = encode(message);
    final blobs = <String, SessionBlobData>{};
    final parts = <Map<String, dynamic>>[];
    for (final part in message.parts) {
      if (part.type == 'text' || part.value.length <= blobThreshold) {
        parts.add({
          'type': part.type,
          'value': part.value,
          if (part.mimeType != null) 'mimeType': part.mimeType,
        });
        continue;
      }
      final hash = sha256.convert(utf8.encode(part.value)).toString();
      blobs[hash] = (data: part.value, mimeType: part.mimeType);
      parts.add({
        'type': part.type,
        'blob': hash,
        'size': part.value.length,
        if (part.mimeType != null) 'mimeType': part.mimeType,
      });
    }
    payload['parts'] = parts;
    return (payload: payload, blobs: blobs);
  }

  /// payload 引用的 blob 哈希。
  static Iterable<String> blobRefs(Map<String, dynamic> payload) sync* {
    for (final raw in (payload['parts'] as List<dynamic>? ?? const [])) {
      if (raw is Map && raw['blob'] is String) yield raw['blob'] as String;
    }
  }

  /// [blobs] 为 blob 哈希 → 内容；引用缺失的附件解码为 [missingBlobText]。
  static ChatMessage decode(Map<String, dynamic> json,
          {Map<String, String> blobs = const {}}) =>
      ChatMessage(
        role: MessageRole.values.byName(json['role'] as String),
        parts: [
          for (final raw in (json['parts'] as List<dynamic>? ?? const []))
            _decodePart(Map<String, dynamic>.from(raw as Map), blobs),
        ],
        toolCallId: json['toolCallId'] as String?,
        toolCalls: [
          for (final raw in (json['toolCalls'] as List<dynamic>? ?? const []))
            _decodeCall(Map<String, dynamic>.from(raw as Map)),
        ],
        reasoning: json['reasoning'] as String?,
      );

  /// 规范化 JSON：对象键排序，保证同样内容得到同样字节。
  static String canonicalJson(ChatMessage message) =>
      jsonEncode(_canonical(encode(message)));

  static final Expando<String> _keyCache = Expando<String>('contentKey');

  /// 模型可见内容的 sha256。按对象身份缓存：执行器在多步之间复用同一批
  /// 消息对象，每条消息只需哈希一次（附件图片等大内容尤其重要）。
  static String contentKey(ChatMessage message) =>
      _keyCache[message] ??=
          sha256.convert(utf8.encode(canonicalJson(message))).toString();

  static MessagePart _decodePart(
      Map<String, dynamic> json, Map<String, String> blobs) {
    final blob = json['blob'];
    if (blob is String && !blobs.containsKey(blob)) {
      return const MessagePart.text(missingBlobText);
    }
    final value =
        blob is String ? blobs[blob]! : json['value'] as String? ?? '';
    final mimeType = json['mimeType'] as String?;
    return switch (json['type']) {
      'file' => MessagePart.file(value, mimeType: mimeType),
      'image' => MessagePart.image(value, mimeType: mimeType),
      'audio' => MessagePart.audio(value, mimeType: mimeType),
      'video' => MessagePart.video(value, mimeType: mimeType),
      _ => MessagePart.text(value),
    };
  }

  static ToolCall _decodeCall(Map<String, dynamic> json) => ToolCall(
        id: json['id'] as String,
        name: json['name'] as String,
        arguments: Map<String, dynamic>.from(
            (json['arguments'] as Map?) ?? const <String, dynamic>{}),
        providerMetadata: Map<String, dynamic>.from(
            (json['providerMetadata'] as Map?) ?? const <String, dynamic>{}),
      );

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _canonical(value[k])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }
}
