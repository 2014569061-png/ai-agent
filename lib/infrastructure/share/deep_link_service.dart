import 'package:flutter/foundation.dart';

/// 深度链接路由（E4）：`nexus://new-chat?prompt=xx` / `nexus://memory`。
/// 冷启动捕获 + 热链监听，均异步不阻塞启动。
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  /// 待处理的新会话预填提示词。
  String? pendingPrompt;

  /// 待打开的记忆页标记。
  bool pendingMemory = false;

  void handleUri(Uri uri) {
    if (uri.scheme != 'nexus') return;
    switch (uri.host) {
      case 'new-chat':
        pendingPrompt = uri.queryParameters['prompt'];
      case 'memory':
        pendingMemory = true;
      default:
        pendingPrompt = uri.queryParameters['prompt'];
    }
  }

  String? drainPrompt() {
    final p = pendingPrompt;
    pendingPrompt = null;
    return p;
  }

  bool drainMemory() {
    final m = pendingMemory;
    pendingMemory = false;
    return m;
  }

  @visibleForTesting
  void reset() {
    pendingPrompt = null;
    pendingMemory = false;
  }
}
