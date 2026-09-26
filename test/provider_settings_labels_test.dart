import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/presentation/settings/model_list_page.dart';
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
}
