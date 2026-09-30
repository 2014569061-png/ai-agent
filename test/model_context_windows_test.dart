import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/infrastructure/providers/provider_config.dart';

ProviderConfig _cfg(String model,
        {int contextTokens = ProviderConfig.defaultContextTokens,
        String baseUrl = 'https://api.stepfun.com/v1'}) =>
    ProviderConfig(
      baseUrl: baseUrl,
      model: model,
      apiKey: 'k',
      contextTokens: contextTokens,
    );

void main() {
  test('known models get an auto window capped for cost', () {
    expect(_cfg('step-5-preview').effectiveContextTokens,
        ModelContextWindows.autoCap);
    expect(_cfg('step-3.7-flash').effectiveContextTokens, 128000);
    expect(_cfg('stepfun/step-3.5-flash').effectiveContextTokens, 128000);
    expect(_cfg('deepseek-chat').effectiveContextTokens, 128000);
    expect(ModelContextWindows.knownFor('step-5-preview'), 1000000);
  });

  test('size suffix in the model name is honoured', () {
    expect(_cfg('step-1-8k').effectiveContextTokens, 8000);
    expect(_cfg('moonshot-v1-128k').effectiveContextTokens, 128000);
  });

  test('explicit values, unknown models and local servers are untouched',
      () {
    expect(_cfg('step-5-preview', contextTokens: 64000).effectiveContextTokens,
        64000);
    expect(_cfg('my-custom-model').effectiveContextTokens,
        ProviderConfig.defaultContextTokens);
    expect(
      _cfg('qwen3:8b', baseUrl: 'http://192.168.1.5:11434/v1')
          .effectiveContextTokens,
      ProviderConfig.defaultContextTokens,
    );
  });
}
