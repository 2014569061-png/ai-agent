import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_agent/main.dart';

void main() {
  testWidgets('renders the mobile agent shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MobileAgentApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
    // 启动门禁 _loadOnboardingState 带 2 秒兜底 timeout：不推进假时钟的话，
    // 该 Timer 在测试结束时仍处于挂起状态，会触发 binding 不变量断言失败。
    // 推进 3 秒让兜底超时触发、启动流程落地（不能用 pumpEventQueue，
    // 主界面的循环动效会不断排入新帧导致其永不返回）。
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
