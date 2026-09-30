import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/presentation/settings/provider_detail_page.dart';

Future<void> _pump(WidgetTester tester, ProviderConfig config) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(home: ProviderDetailPage(config: config)),
  ));
  await tester.pump();
  await tester.tap(find.text('调整思考程度与上下文窗口'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default context shows as auto with the inferred window',
      (tester) async {
    await _pump(
      tester,
      const ProviderConfig(
        baseUrl: 'https://api.stepfun.com/v1',
        model: 'step-5-preview',
        apiKey: 'k',
      ),
    );
    final field = find.byKey(const ValueKey('provider-context-tokens'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.textContaining('自动：按模型推断为 128K'), findsOneWidget);
    expect(find.textContaining('模型支持 1M'), findsOneWidget);

    await tester.enterText(field, '64000');
    await tester.pump();
    expect(find.text('手动设置；清空即恢复自动'), findsOneWidget);
  });

  testWidgets('explicit context value is shown as manual', (tester) async {
    await _pump(
      tester,
      const ProviderConfig(
        baseUrl: 'https://api.stepfun.com/v1',
        model: 'step-5-preview',
        apiKey: 'k',
        contextTokens: 256000,
      ),
    );
    final field = find.byKey(const ValueKey('provider-context-tokens'));
    expect(tester.widget<TextField>(field).controller!.text, '256000');
    expect(find.text('手动设置；清空即恢复自动'), findsOneWidget);
  });
}
