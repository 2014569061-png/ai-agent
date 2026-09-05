import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/mcp/mcp_server_config.dart';
import 'package:mobile_agent/infrastructure/mcp/mcp_tool_provider.dart';

void main() {
  group('McpServerConfig', () {
    test('JSON 序列化往返', () {
      const config = McpServerConfig(
        id: 'mcp-1',
        name: 'weather',
        kind: McpServerKind.http,
        url: 'http://localhost:3000/mcp',
        enabled: false,
      );
      final restored = McpServerConfig.fromJson(config.toJson());
      expect(restored.id, 'mcp-1');
      expect(restored.name, 'weather');
      expect(restored.kind, McpServerKind.http);
      expect(restored.url, 'http://localhost:3000/mcp');
      expect(restored.enabled, isFalse);
    });

    test('stdio 配置序列化', () {
      const config = McpServerConfig(
        id: 'mcp-2',
        name: 'filesystem',
        kind: McpServerKind.stdio,
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-filesystem'],
      );
      final restored = McpServerConfig.fromJson(config.toJson());
      expect(restored.kind, McpServerKind.stdio);
      expect(restored.command, 'npx');
      expect(restored.args, ['-y', '@modelcontextprotocol/server-filesystem']);
    });

    test('store 持久化（SharedPreferences mock）', () async {
      SharedPreferences.setMockInitialValues({});
      const server = McpServerConfig(
        id: 'mcp-3',
        name: 'demo',
        kind: McpServerKind.http,
        url: 'http://example.com/mcp',
      );
      final store = McpServerStore();
      await store.save(server);

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'mcp-3');
      expect(loaded.first.url, 'http://example.com/mcp');

      // enabled 过滤
      await store.save(server.copyWith(enabled: false));
      final enabled = await store.loadEnabled();
      expect(enabled, isEmpty);

      // 删除
      await store.delete('mcp-3');
      expect(await store.loadAll(), isEmpty);
    });
  });

  group('McpTool 映射', () {
    test('manifest 带服务器前缀且默认需确认', () {
      final client = mcp.McpClient(
        mcp.Implementation(name: 'nexus-agent', version: '0.1.0'),
      );
      final tool = mcp.Tool(
        name: 'get_weather',
        description: '查询天气',
        inputSchema: mcp.JsonSchema.fromJsonValue({
          'type': 'object',
          'properties': {
            'city': {'type': 'string'}
          },
          'required': ['city'],
        }),
      );
      final wrapper = McpTool(
        client: client,
        server: const McpServerConfig(
          id: 'mcp-9',
          name: 'weather',
          kind: McpServerKind.http,
          url: 'http://x/mcp',
        ),
        tool: tool,
      );

      expect(wrapper.qualifiedName, 'weather.get_weather');
      expect(wrapper.manifest.name, 'weather.get_weather');
      expect(wrapper.manifest.description, '查询天气');
      expect(wrapper.manifest.risk, ToolRisk.requiresConfirmation);
      expect(wrapper.manifest.parametersSchema['type'], 'object');
      final properties = wrapper.manifest.parametersSchema['properties'] as Map;
      expect(properties.containsKey('city'), isTrue);
    });
  });
}
