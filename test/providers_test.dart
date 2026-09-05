import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/anthropic_provider.dart';
import 'package:mobile_agent/infrastructure/providers/gemini_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';

void main() {
  const config =
      ProviderConfig(baseUrl: 'https://example.com', model: 'm', apiKey: 'k');

  group('AnthropicProvider', () {
    test('converts a user text message into content blocks', () {
      final provider = AnthropicProvider(config: config);
      final result = provider.toAnthropicMessage(ChatMessage(
        role: MessageRole.user,
        parts: const [MessagePart.text('你好')],
      ));
      expect(result['role'], 'user');
      expect(result['content'], [
        {'type': 'text', 'text': '你好'},
      ]);
    });

    test('converts assistant tool calls into tool_use blocks', () {
      final provider = AnthropicProvider(config: config);
      final result = provider.toAnthropicMessage(ChatMessage(
        role: MessageRole.assistant,
        parts: const [],
        toolCalls: [
          ToolCall(id: 'call-1', name: 'calculator', arguments: {'a': 1})
        ],
      ));
      expect(result['role'], 'assistant');
      expect(result['content'], [
        {
          'type': 'tool_use',
          'id': 'call-1',
          'name': 'calculator',
          'input': {'a': 1}
        },
      ]);
    });

    test('converts tool results into tool_result blocks', () {
      final provider = AnthropicProvider(config: config);
      final result = provider.toAnthropicMessage(ChatMessage(
        role: MessageRole.tool,
        toolCallId: 'call-1',
        parts: const [MessagePart.text('3')],
      ));
      expect(result['role'], 'user');
      expect(result['content'], [
        {'type': 'tool_result', 'tool_use_id': 'call-1', 'content': '3'},
      ]);
    });

    test('maps tool schema to input_schema', () {
      final provider = AnthropicProvider(config: config);
      final result = provider.toAnthropicTool(const UnifiedTool(
        name: 'get_time',
        description: 'time',
        parametersSchema: {'type': 'object', 'properties': {}},
        risk: ToolRisk.safe,
      ));
      expect(result['name'], 'get_time');
      expect(result['input_schema'], {'type': 'object', 'properties': {}});
    });
  });

  group('GeminiProvider', () {
    test('converts a user message into parts', () {
      final provider = GeminiProvider(config: config);
      final result = provider.toGeminiMessage(
          ChatMessage(
            role: MessageRole.user,
            parts: const [MessagePart.text('你好')],
          ),
          const {});
      expect(result['role'], 'user');
      expect(result['parts'], [
        {'text': '你好'},
      ]);
    });

    test('converts assistant tool calls into functionCall parts', () {
      final provider = GeminiProvider(config: config);
      final result = provider.toGeminiMessage(
          ChatMessage(
            role: MessageRole.assistant,
            parts: const [],
            toolCalls: [
              ToolCall(id: 'call-1', name: 'calculator', arguments: {'a': 1})
            ],
          ),
          const {});
      expect(result['role'], 'model');
      expect(result['parts'], [
        {
          'functionCall': {
            'name': 'calculator',
            'args': {'a': 1}
          },
        },
      ]);
    });

    test('converts tool results into functionResponse parts with resolved name',
        () {
      final provider = GeminiProvider(config: config);
      final result = provider.toGeminiMessage(
        ChatMessage(
            role: MessageRole.tool,
            toolCallId: 'call-1',
            parts: const [MessagePart.text('3')]),
        const {'call-1': 'calculator'},
      );
      expect(result['role'], 'function');
      expect(result['parts'], [
        {
          'functionResponse': {
            'name': 'calculator',
            'response': {'result': '3'}
          },
        },
      ]);
    });

    test('maps tool schema to functionDeclarations parameter', () {
      final provider = GeminiProvider(config: config);
      final result = provider.toGeminiTool(const UnifiedTool(
        name: 'json_query',
        description: 'query',
        parametersSchema: {'type': 'object'},
        risk: ToolRisk.safe,
      ));
      expect(result['name'], 'json_query');
      expect(result['parameters'], {'type': 'object'});
    });
  });

  group('ProviderConfig.isConfigured', () {
    test('local model without api key is considered configured', () {
      const local = ProviderConfig(
          baseUrl: 'http://localhost:11434/v1', model: 'llama3.2', apiKey: '');
      expect(local.isConfigured, isTrue);
    });

    test('cloud provider without api key is not configured', () {
      const cloud = ProviderConfig(
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          apiKey: '');
      expect(cloud.isConfigured, isFalse);
    });

    test('empty model is never configured', () {
      const empty = ProviderConfig(
          baseUrl: 'http://localhost:11434/v1', model: '', apiKey: '');
      expect(empty.isConfigured, isFalse);
    });
  });
}
