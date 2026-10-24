import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/application/usage_cost_estimator.dart';

ProviderConfig _config(String model, {int? input, int? output, int? cached}) =>
    ProviderConfig(
      baseUrl: 'https://example.invalid',
      model: model,
      apiKey: 'test',
      inputPricePerMillionCents: input,
      outputPricePerMillionCents: output,
      cachedPricePerMillionCents: cached,
    );

void main() {
  test('uses local price table and rounds up with cache savings', () {
    final r = estimateUsageCostCents(
      _config('gpt-4o-mini'),
      const Usage(promptTokens: 1000, cachedTokens: 200, completionTokens: 500),
    );
    // fresh 800*2 + cached 200*0 + completion 500*9 = 6100 / 1e6 -> ceil 1
    // saved 200*(2-0) / 1e6 -> ceil 1
    expect(r.costCents, 1);
    expect(r.savedCostCents, 1);
  });

  test('million-token prompt on gpt-4o costs exactly its input rate', () {
    final r = estimateUsageCostCents(
      _config('gpt-4o'),
      const Usage(promptTokens: 1000000, completionTokens: 0),
    );
    expect(r.costCents, 35);
    expect(r.savedCostCents, 0);
  });

  test('custom provider prices override the table', () {
    final r = estimateUsageCostCents(
      _config('gpt-4o', input: 100, output: 100, cached: 10),
      const Usage(promptTokens: 1000000, completionTokens: 1000000),
    );
    expect(r.costCents, 200);
  });

  test('unknown model without custom prices yields null', () {
    final r = estimateUsageCostCents(
      _config('unknown-model'),
      const Usage(promptTokens: 10, completionTokens: 10),
    );
    expect(r.costCents, isNull);
    expect(r.savedCostCents, isNull);
  });

  test('zero usage yields null', () {
    final r = estimateUsageCostCents(_config('gpt-4o'), const Usage());
    expect(r.costCents, isNull);
  });
}
