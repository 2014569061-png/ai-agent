import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'sharing_image_reader.dart';
import 'share_batch_intake.dart';

/// 系统分享接收服务（入站分享）。
///
/// 冷启动时捕获 `getInitialMedia` 存入 `_pending` 缓冲（此时 ChatPage 可能尚未
/// 订阅，broadcast stream 会丢事件）；运行时通过 `getMediaStream` 监听热分享
/// （Android singleTop 的 onNewIntent）并**按批次**分发。
///
/// 因此 [shares] 的事件类型是 `List<String>`：一次系统分享就是一个批次，调用方
/// 据此把「相册多选分享的 3 张图」合并进同一个会话，而不是凭空开出 3 个会话。
/// 生产入口绑定统一队列，保留批次并经可见性门禁与核对页后加入已有草稿。
/// `shares` 与 `drainPending()` 仅保留给兼容订阅方。
/// Web / 平台不支持时静默降级（不抛错）。
class SharingService {
  SharingService._();
  static final SharingService instance = SharingService._();

  final _shares = StreamController<List<String>>.broadcast();
  final _pending = <List<String>>[];
  void Function(List<String>)? _entrySink;
  void Function(String)? _onFailure;
  Future<void>? _initialization;
  late final _intake = ShareBatchIntake(
      onBatch: _emitBatch,
      onFailure: () => _onFailure?.call('分享内容未能接收或队列已满，请重新分享'));

  void bindEntrySink(void Function(List<String>) sink,
      {void Function(String)? onFailure}) {
    _entrySink = sink;
    _onFailure = onFailure;
    final batches = List<List<String>>.of(_pending);
    _pending.clear();
    for (final batch in batches) {
      sink(batch);
    }
  }

  Stream<List<String>> get shares => _shares.stream;

  /// Android may surface a VIEW deep link through the sharing plugin's media
  /// channel. These intents are handled by DeepLinkService, never as chat text.
  static bool isShareableText(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri?.scheme.toLowerCase() != 'nexus';
  }

  /// 按批次分发，空批次直接丢弃（例如整批都不是可分享内容）。
  void _emitBatch(List<String> values) {
    final shareable = values
        .where((value) => value.trim().isNotEmpty && isShareableText(value))
        .toList();
    if (shareable.isEmpty) return;
    final sink = _entrySink;
    if (sink != null) {
      sink(List.unmodifiable(shareable));
    } else if (!_shares.hasListener) {
      _pending.add(List.unmodifiable(shareable));
    }
    if (_shares.hasListener) _shares.add(List.unmodifiable(shareable));
  }

  /// 取出并清空冷启动阶段缓冲的分享内容。
  List<String> drainPending() {
    final result = _pending.expand((batch) => batch).toList();
    _pending.clear();
    return result;
  }

  Future<void> init() => _initialization ??= _init();
  Future<void> _init() async {
    if (kIsWeb) return;
    var initialLoading = true;
    final hot = <List<SharedMediaFile>>[];
    // Subscribe first. Buffer warm intents until the initial batch is queued,
    // keeping batch boundaries across slow image reads and cold initialization.
    try {
      ReceiveSharingIntent.instance.getMediaStream().listen((files) {
        if (initialLoading) {
          if (hot.length < 8) {
            hot.add(List.of(files));
          } else {
            _onFailure?.call('分享初始化队列已满，请重新分享');
          }
        } else {
          unawaited(_emitMedia(List.of(files)));
        }
      }, onError: (Object _) => _onFailure?.call('系统分享暂不可用，请重新分享'));
    } catch (_) {/* Unsupported platforms keep the initial-media fallback. */}
    try {
      final media = await ReceiveSharingIntent.instance.getInitialMedia();
      await _emitMedia(media);
    } catch (_) {
      // Web 或平台不支持：静默降级。
    }
    initialLoading = false;
    for (final batch in hot) {
      unawaited(_emitMedia(batch));
    }
  }

  /// 同一批次内保持顺序，避免多个异步转码交错打乱「图 1、图 2」的先后。
  Future<void> _emitMedia(List<SharedMediaFile> files) {
    if (files.length > 12) {
      _onFailure?.call('单次最多接收12项分享，请减少内容后重新分享');
      return Future.value();
    }
    return _intake.append(() async {
      final converted = <String>[];
      for (final file in files) {
        converted.add(await _mediaToText(file));
      }
      return converted;
    });
  }

  Future<String> _mediaToText(SharedMediaFile m) async {
    if (m.type == SharedMediaType.image) {
      return await sharedImageToPromptText(m.path) ?? '[图片] ${m.path}';
    }
    return m.path;
  }
}
