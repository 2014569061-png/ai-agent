import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 圆角 token 守卫。
///
/// 页面层（`lib/presentation` 下 `theme/` 之外）不应该再出现页面级圆角字面量：
/// 要么用 `MobileTheme.insetRadius` / `contentRadius` / `sheetRadius`，
/// 要么用 `AppTokens.radiusControl` / `radiusCard` / `radiusModal` / `radiusPill`。
///
/// 会失败的写法：
///   `BorderRadius.circular(16)`
///   `Radius.circular(24)`
///
/// 允许的写法：
///   `BorderRadius.circular(MobileTheme.insetRadius)`
///   `BorderRadius.circular(AppTokens.radiusPill)`
///   `BorderRadius.circular(4)`   // 发丝级装饰，复用 token 没有意义
void main() {
  test('页面层不应出现新的页面级圆角字面量', () {
    // 有意为之的一次性设计。往这里加条目前先回答：
    // 「为什么这个圆角不能被现有的 token 表达？」
    final allowed = <String, Set<double>>{
      // 抽屉顶部圆角，抽屉有自己的高度体系，不跟着卡片走。
      'lib/presentation/chat/widgets/attachment_drawer_panel.dart': {24},
      // 气泡专用圆角：形状由气泡排版决定，不是卡片。
      'lib/presentation/chat/widgets/message_bubble.dart': {20},
      // 飞行动画的起终点形状，纯动效用途。
      'lib/presentation/motion/send_flight.dart': {20},
      // 以下三处是别的分支正在改的页面，登记为棘轮基线：
      // 他们提交后应改用 radiusPill，届时删掉这三行。
      'lib/presentation/chat/widgets/chat_catalog_drawer.dart': {16, 999},
      'lib/presentation/chat/widgets/chat_empty_state.dart': {999},
      'lib/presentation/workbench/session_workbench_page.dart': {999},
    };

    final pattern = RegExp(r'circular\(\s*(\d+(?:\.\d+)?)\s*\)');
    final violations = <String>[];

    for (final entity in Directory('lib/presentation').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.contains('/theme/')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final match in pattern.allMatches(lines[i])) {
          final value = double.parse(match.group(1)!);
          // 发丝级装饰圆角（进度条、小徽标、细描边）不需要 token。
          if (value <= 11) continue;
          if (allowed[path]?.contains(value) ?? false) continue;
          violations.add('$path:${i + 1}  ${match.group(0)}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '发现未走 token 的页面级圆角：\n${violations.join('\n')}\n'
          '请改用 MobileTheme.insetRadius / contentRadius / sheetRadius，'
          '或 AppTokens.radiusControl / radiusCard / radiusModal / radiusPill；'
          '确实是一次性设计就往测试顶部的 allowed 里加一条并说明原因。',
    );
  });
}
