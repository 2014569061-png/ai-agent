import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/presentation/settings/model_list_page.dart';
import 'package:mobile_agent/presentation/settings/provider_detail_page.dart';
import 'package:mobile_agent/presentation/settings/provider_list_page.dart';

void main() {
  test('protocol labels are localized for every provider type', () {
    expect(providerProtocolLabel(ProviderType.openaiCompatible), 'OpenAI 兼容');
    expect(providerProtocolLabel(ProviderType.anthropic), 'Anthropic');
    expect(providerProtocolLabel(ProviderType.gemini), 'Gemini');
    for (final type in ProviderType.values) {
      expect(providerProtocolLabel(type), isNot(type.name));
    }
  });

  test('context tokens use compact K / M notation', () {
    expect(formatContextTokens(800), '800');
    expect(formatContextTokens(8000), '8K');
    expect(formatContextTokens(128000), '128K');
    expect(formatContextTokens(1000000), '1M');
    expect(formatContextTokens(1048576), '1M');
    expect(formatContextTokens(1500000), '1.5M');
    expect(formatContextTokens(2000000), '2M');
  });

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 360, child: child)),
      );

  testWidgets('connection failure keeps the full reason selectable',
      (tester) async {
    const reason = 'HTTP 401 Unauthorized: invalid api key, please check the '
        'key in the provider settings and try again';
    await tester.pumpWidget(host(const ProviderConnectionStatus(
      status: '连接失败：$reason',
      testing: false,
    )));
    expect(find.text('连接失败'), findsOneWidget);
    final detail = tester.widget<SelectableText>(
        find.byKey(const ValueKey('provider-connection-detail')));
    expect(detail.data, reason);
    expect(detail.maxLines, 3);
    expect(find.byIcon(Icons.error_rounded), findsOneWidget);
  });

  testWidgets(
      'connection status uses neutral icon while testing and check on '
      'success', (tester) async {
    await tester.pumpWidget(host(const ProviderConnectionStatus(
      status: '正在测试连接…',
      testing: true,
    )));
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_rounded), findsNothing);
    expect(
        find.byKey(const ValueKey('provider-connection-detail')), findsNothing);

    await tester.pumpWidget(host(const ProviderConnectionStatus(
      status: '连接测试成功',
      testing: false,
    )));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });
}
