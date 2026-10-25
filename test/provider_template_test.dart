import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/provider_template.dart';

void main() {
  Map<String, Object> valid() => {
        'schemaVersion': 1,
        'name': '测试',
        'baseUrl': 'https://example.com/v1',
        'model': 'test-model',
        'protocol': 'openaiCompatible'
      };
  ProviderTemplate parse(Map<String, Object> data) =>
      ProviderTemplate.parse(jsonEncode(data));
  test('safe template round trips without secrets', () {
    final value = parse(valid());
    expect(value.contextTokens, 32000);
    expect(parse(value.toJson()).baseUrl, value.baseUrl);
    expect(value.toJson().containsKey('apiKey'), isFalse);
  });
  for (final field in [
    'apiKey',
    'headers',
    'authorization',
    'command',
    'permissions'
  ]) {
    test('rejects untrusted field $field', () {
      expect(() => parse({...valid(), field: 'secret'}), throwsFormatException);
    });
  }
  for (final url in [
    'file:///tmp/a',
    'javascript:alert(1)',
    'https://user:pass@example.com/v1',
    'https://example.com/v1?key=secret',
    'https://example.com/#secret',
    'http://example.com/v1',
    'http://172.40.0.1/v1',
    'http://192.168.attacker.com/v1'
  ]) {
    test('rejects unsafe endpoint $url', () {
      expect(() => parse({...valid(), 'baseUrl': url}), throwsFormatException);
    });
  }
  for (final url in [
    'http://localhost:11434/v1',
    'http://127.0.0.1:11434/v1',
    'http://192.168.1.2:11434/v1',
    'http://172.16.0.1/v1',
    'http://[::1]:11434/v1'
  ]) {
    test('supports explicit local endpoint $url', () {
      expect(parse({...valid(), 'baseUrl': url}).baseUrl.scheme, 'http');
    });
  }
  test('validates schema, protocol, types and budgets', () {
    for (final entry in <Map<String, Object>>[
      {'schemaVersion': 2},
      {'schemaVersion': '1'},
      {'protocol': 'shell'},
      {'contextTokens': 3999},
      {'contextTokens': 2000001},
      {'contextTokens': 32000.5},
      {'model': ''},
      {'name': 'a\nb'},
    ]) {
      expect(() => parse({...valid(), ...entry}), throwsFormatException);
    }
    expect(() => ProviderTemplate.parse('[]'), throwsFormatException);
    expect(() => ProviderTemplate.parse('{'), throwsFormatException);
    expect(() => ProviderTemplate.parse('x' * 16385), throwsFormatException);
  });
}
