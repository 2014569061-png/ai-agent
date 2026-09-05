import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'sharing_image_reader.dart';

/// 系统分享接收服务（入站分享）。
///
/// 冷启动时捕获 `getInitialMedia` 存入 `_pending` 缓冲（此时
/// ChatPage 可能尚未订阅，broadcast stream 会丢事件）；运行时通过
/// `getMediaStream` 监听热分享（Android singleTop 的 onNewIntent）实时分发。
/// ChatPage 订阅后先 `drainPending()` 消费冷启动分享，再监听 `shares`。
/// Web / 平台不支持时静默降级（不抛错）。
class SharingService {
  SharingService._();
  static final SharingService instance = SharingService._();

  final _shares = StreamController<String>.broadcast();
  final _pending = <String>[];

  Stream<String> get shares => _shares.stream;

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
        final value = _mediaToText(m);
        if (value.trim().isNotEmpty) _pending.add(value);
      }
    } catch (_) {
      // Web 或平台不支持：静默降级。
    }
    try {
      ReceiveSharingIntent.instance.getMediaStream().listen((files) {
        for (final m in files) {
          _shares.add(_mediaToText(m));
        }
      });
    } catch (_) {
      // 热分享监听失败不影响冷启动分享。
    }
  }

  String _mediaToText(SharedMediaFile m) {
    if (m.type == SharedMediaType.image) {
      return readSharedImageAsDataUri(m.path) ?? '[图片] ${m.path}';
    }
    return m.path;
  }
}
