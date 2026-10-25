import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/browser_payload_budget.dart';
import 'package:mobile_agent/domain/tool_result.dart';

void main() {
  int bytes(ToolResult result) => utf8.encode(result.encode()).length;
  String repeat(String value, int count) => List.filled(count, value).join();

  test('small envelopes are preserved without mutation or false truncation',
      () {
    final input =
        ToolResult.success(data: {'text': 'hello', 'truncated': false});
    expect(BrowserPayloadBudget.limit(input), same(input));
    expect(input.data!['truncated'], isFalse);
  });

  for (final text in ['中', '😀', '"\n\\', 'a']) {
    test('bounds the complete encoded envelope for $text', () {
      final input = ToolResult.success(data: {
        'snapshotId': 'same-snapshot',
        'epoch': 7,
        'text': repeat(text, 40000),
        'nodes': <dynamic>[],
        'untrustedContent': true,
        'scope': 'open roots',
      });
      final result = BrowserPayloadBudget.limit(input);
      expect(result.ok, isTrue);
      expect(bytes(result), lessThanOrEqualTo(BrowserPayloadBudget.maxBytes));
      expect(jsonDecode(result.encode()), isA<Map>());
      expect(result.data!['snapshotId'], 'same-snapshot');
      expect(result.data!['epoch'], 7);
      expect(result.data!['untrustedContent'], isTrue);
      expect(result.data!['payloadTruncated'], isTrue);
      expect(result.data!['textTruncated'], isTrue);
      expect(result.data!['continuationAvailable'], isFalse);
      final returned = result.data!['text'] as String;
      expect(returned, isNotEmpty);
      expect(utf8.decode(utf8.encode(returned)), returned);
      expect(input.data!['text'], repeat(text, 40000));
      expect(input.data!.containsKey('payloadTruncated'), isFalse);
    });
  }

  test('long links and labels drop only tail nodes with explicit flags', () {
    final nodes = List.generate(
        120,
        (i) => {
              'id': 'n$i',
              'label': repeat('中', 180),
              'href': 'https://example.invalid/${repeat('x', 1024)}',
            });
    final input = ToolResult.success(data: {
      'snapshotId': 's',
      'text': 'keep body',
      'nodes': nodes,
      'url': 'https://example.invalid',
    });
    final result = BrowserPayloadBudget.limit(input);
    final returned = result.data!['nodes'] as List;
    expect(bytes(result), lessThanOrEqualTo(BrowserPayloadBudget.maxBytes));
    expect(returned, isNotEmpty);
    expect(returned.length, lessThan(nodes.length));
    expect(returned, nodes.take(returned.length).toList());
    expect(result.data!['text'], 'keep body');
    expect(result.data!['nodesTruncated'], isTrue);
    expect(result.data!['textTruncated'], isFalse);
    expect(nodes.length, 120);
  });

  test('oversized identity metadata fails closed and preserves each effect',
      () {
    for (final effect in ToolEffect.values) {
      final input = ToolResult.success(effect: effect, data: {
        'state': {'url': repeat('x', 40000)},
        'snapshotId': 's',
        'text': 'body',
        'nodes': [
          {'id': 'n1'}
        ],
      });
      final result = BrowserPayloadBudget.limit(input);
      expect(result.ok, isFalse);
      expect(result.code, 'BROWSER_PAYLOAD_TOO_LARGE');
      expect(result.effect, effect);
      expect(result.data!.containsKey('snapshotId'), isFalse);
      expect(bytes(result), lessThanOrEqualTo(BrowserPayloadBudget.maxBytes));
    }
  });

  test('budget includes message and effect overhead', () {
    final input = ToolResult.success(
        message: repeat('中', 30),
        effect: ToolEffect.applied,
        data: {'text': repeat('😀', 500)});
    final result = BrowserPayloadBudget.limit(input, budget: 512);
    expect(bytes(result), lessThanOrEqualTo(512));
    expect(result.effect, ToolEffect.applied);
  });

  test('preserves source truncation and rejects unsupported budgets', () {
    final input = ToolResult.success(data: {'text': 'ok', 'truncated': true});
    expect(BrowserPayloadBudget.limit(input).data!['truncated'], isTrue);
    expect(() => BrowserPayloadBudget.limit(input, budget: 511),
        throwsArgumentError);
    expect(() => BrowserPayloadBudget.limit(input, budget: 32769),
        throwsArgumentError);
  });
}
