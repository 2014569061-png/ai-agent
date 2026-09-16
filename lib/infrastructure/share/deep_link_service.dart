import 'package:flutter/foundation.dart';

/// 深度链接路由（E4）：
/// `nexus://new-chat?prompt=xx` / `nexus://new-agent` / `nexus://memory`。
/// 冷启动捕获 + 热链监听，均异步不阻塞启动。
///
/// 这三个 host 同时被「长按图标的应用快捷方式」使用（见
/// android/app/src/main/res/xml/shortcuts.xml），因此改这里等于改系统级入口的行为。
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  /// 待处理的新会话预填提示词。
  String? pendingPrompt;

  /// 待打开「描述目标创建 Agent」标记。
  bool pendingNewAgent = false;

  /// 待打开的记忆页标记。
  bool pendingMemory = false;

  void handleUri(Uri uri) {
    if (uri.scheme != 'nexus') return;
    switch (uri.host) {
      case 'new-chat':
        pendingPrompt = uri.queryParameters['prompt'];
      case 'new-agent':
        pendingNewAgent = true;
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

  bool drainNewAgent() {
    final a = pendingNewAgent;
    pendingNewAgent = false;
    return a;
  }

  bool drainMemory() {
    final m = pendingMemory;
    pendingMemory = false;
    return m;
  }

  @visibleForTesting
  void reset() {
    pendingPrompt = null;
    pendingNewAgent = false;
    pendingMemory = false;
  }
}
