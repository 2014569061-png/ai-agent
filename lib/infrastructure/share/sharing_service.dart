import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'sharing_image_reader.dart';

/// 系统分享接收服务（入站分享）。
///
/// 冷启动时捕获 `getInitialMedia` 存入 `_pending` 缓冲（此时 ChatPage 可能尚未
/// 订阅，broadcast stream 会丢事件）；运行时通过 `getMediaStream` 监听热分享
/// （Android singleTop 的 onNewIntent）并**按批次**分发。
///
/// 因此 [shares] 的事件类型是 `List<String>`：一次系统分享就是一个批次，调用方
/// 据此把「相册多选分享的 3 张图」合并进同一个会话，而不是凭空开出 3 个会话。
/// ChatPage 订阅后先 `drainPending()` 消费冷启动分享，再监听 `shares`。
/// Web / 平台不支持时静默降级（不抛错）。
class SharingService {
  SharingService._();
  static final SharingService instance = SharingService._();

  final _shares = StreamController<List<String>>.broadcast();
  final _pending = <String>[];

  Stream<List<String>> get shares => _shares.stream;

  /// Android may surface a VIEW deep link through the sharing plugin's media
  /// channel. These intents are handled by DeepLinkService, never as chat text.
  static bool isShareableText(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri?.scheme.toLowerCase() != 'nexus';
  }

  void _addPending(String value) {
    if (value.trim().isNotEmpty && isShareableText(value)) {
      _pending.add(value);
    }
  }

  /// 按批次分发，空批次直接丢弃（例如整批都不是可分享内容）。
  void _emitBatch(List<String> values) {
    final shareable = values.where(isShareableText).toList();
    if (shareable.isNotEmpty) _shares.add(shareable);
  }

  /// 取出并清空冷启动阶段缓冲的分享内容。
  List<String> drainPending() {
    final result = List<String>.of(_pending);
    _pending.clear();
    return result;
  }

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      final media = await ReceiveSharingIntent.instance.getInitialMedia();
      for (final m in media) {
        _addPending(await _mediaToText(m));
      }
    } catch (_) {
      // Web 或平台不支持：静默降级。
    }
    try {
      ReceiveSharingIntent.instance.getMediaStream().listen((files) {
        unawaited(_emitMedia(files));
      });
    } catch (_) {
      // 热分享监听失败不影响冷启动分享。
    }
  }

  /// 同一批次内保持顺序，避免多个异步转码交错打乱「图 1、图 2」的先后。
  Future<void> _emitMedia(List<SharedMediaFile> files) async {
    final converted = <String>[];
    for (final file in files) {
      converted.add(await _mediaToText(file));
    }
    _emitBatch(converted);
  }

  Future<String> _mediaToText(SharedMediaFile m) async {
    if (m.type == SharedMediaType.image) {
      return await sharedImageToPromptText(m.path) ?? '[图片] ${m.path}';
    }
    return m.path;
  }
}
