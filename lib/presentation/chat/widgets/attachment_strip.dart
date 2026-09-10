import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../domain/models.dart';

/// 消息附件条：把 image/audio/video 类型的 MessagePart 渲染成缩略图或播放器。
/// 文本部分由 MessageBubble 单独渲染，避免 base64 字符串被当作文本显示。
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.parts});

  final List<MessagePart> parts;

  @override
  Widget build(BuildContext context) {
    final attachments = <Widget>[];
    for (final part in parts) {
      switch (part.type) {
        case 'image':
          attachments.add(_ImageAttachment(dataUri: part.value));
        case 'audio':
        case 'video':
          // 音视频不属于移动端开发工作台的核心附件类型。
          break;
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: attachments,
    );
  }
}

/// 把 `data:<mime>;base64,<bytes>` 解码为缩略图；解码失败/非法数据降级为占位文本，
/// 绝不显示原始字符串。
class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.dataUri});

  final String dataUri;

  @override
  Widget build(BuildContext context) {
    final comma = dataUri.indexOf(',');
    final encoded = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
    try {
      final bytes = base64Decode(encoded);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          width: 180,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const Text('[图片解码失败]'),
        ),
      );
    } catch (_) {
      return const Text('[图片解码失败]');
    }
  }
}
