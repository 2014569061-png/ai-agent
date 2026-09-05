import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';

/// 主屏幕 Widget（E2）：展示快捷数据，点击唤起 App 对应页面。
/// Android 优先；iOS 需 WidgetKit Extension，当前降级为空操作。
class NexusWidget {
  static const _androidProvider = 'NexusWidgetProvider';
  static const _providerName = 'NexusWidgetProvider';

  /// 更新 Widget 内容（最近会话标题 + 记忆 top3）。
  static Future<void> updateWidget({required List<String> items}) async {
    if (kIsWeb) return;
    try {
      await HomeWidget.saveWidgetData<String>('items', jsonEncode(items));
      await HomeWidget.updateWidget(
          name: _providerName, androidName: _androidProvider);
    } catch (_) {
      // Widget 更新失败静默降级。
    }
  }

  /// 监听 Widget 点击（携带 nexus:// URI，由 main.dart 统一路由）。
  static void onWidgetClicked(void Function(Uri uri) handler) {
    if (kIsWeb) return;
    HomeWidget.widgetClicked.listen((uri) {
      if (uri != null) handler(uri);
    });
  }
}
