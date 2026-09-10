import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import '../database/app_database.dart';
import '../tools/tool_registry.dart';

/// 插件市场（C6）：声明式工具包 / Agent 预设包。
/// 包格式（JSON manifest）：`{name, version, kind, tools:[{name,description,schema,request}], agents:[...]}`。
/// V1 只支持「声明式工具」与「Agent 预设」，不支持任意本地代码（安全边界）。
class PluginStore {
  static const _maxToolsPerPlugin = 20;

  bool validateManifest(String manifestJson) {
    try {
      final map = jsonDecode(manifestJson);
      if (map is! Map<String, dynamic>) return false;
      final name = map['name'];
      final kind = map['kind'];
      if (name is! String || name.trim().isEmpty) return false;
      if (kind is! String ||
          !const {'tool', 'agent', 'bundle'}.contains(kind)) {
        return false;
      }
      final tools = map['tools'];
      if (tools is List && tools.length > _maxToolsPerPlugin) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Plugin> importPlugin({
    required AppDatabase db,
    required String name,
    required String kind,
    required String manifestJson,
  }) async {
    final now = DateTime.now();
    final plugin = Plugin(
      id: 'plugin-${now.microsecondsSinceEpoch}',
      name: name,
      kind: kind,
      manifestJson: manifestJson,
      version: '1.0.0',
      enabled: true,
      createdAt: now,
    );
    await db.savePlugin(plugin);
    return plugin;
  }

  /// 把已启用插件里的声明式工具实例化（HTTP 模板请求）。
  Future<List<AgentTool>> loadDeclarativeTools(AppDatabase db) async {
    final plugins = await db.allPlugins();
    final tools = <AgentTool>[];
    for (final plugin in plugins.where((p) => p.enabled)) {
      try {
        final map = jsonDecode(plugin.manifestJson) as Map<String, dynamic>;
        final defs = (map['tools'] as List? ?? const [])
            .whereType<Map<String, dynamic>>();
        for (final def in defs) {
          tools.add(DeclarativeTool.fromManifest(def));
        }
      } catch (_) {
        // 单个插件解析失败不影响其余。
      }
    }
    return tools;
  }

  /// 把已启用插件里的 Agent 预设导入 Agents 表。
  Future<void> importAgents(AppDatabase db) async {
    final plugins = await db.allPlugins();
    for (final plugin in plugins.where((p) => p.enabled)) {
      try {
        final map = jsonDecode(plugin.manifestJson) as Map<String, dynamic>;
        final agents = (map['agents'] as List? ?? const [])
            .whereType<Map<String, dynamic>>();
        for (final a in agents) {
          final name = (a['name'] as String?)?.trim();
          if (name == null || name.isEmpty) continue;
          final now = DateTime.now();
          await db.saveAgent(Agent(
            id: 'agent-plugin-${plugin.id}-${now.microsecondsSinceEpoch}',
            name: name,
            systemPrompt: a['systemPrompt'] as String? ?? '你是一个有帮助的 AI Agent。',
            modelProfileId: a['modelProfileId'] as String? ?? 'default',
            enabledToolsJson:
                jsonEncode(a['enabledTools'] as List? ?? const []),
            temperature: (a['temperature'] as num?)?.toDouble() ?? 0.7,
            maxTokens: (a['maxTokens'] as num?)?.toInt() ?? 2048,
            maxSteps: (a['maxSteps'] as num?)?.toInt() ?? 8,
            topP: (a['topP'] as num?)?.toDouble() ?? 1.0,
            updatedAt: now,
          ));
        }
      } catch (_) {
        // 忽略。
      }
    }
  }
}

/// 声明式工具：按 manifest 里的 request 模板发起 HTTP 请求（危险操作仍需审批）。
class DeclarativeTool implements AgentTool {
  DeclarativeTool.fromManifest(Map<String, dynamic> map)
      : _request = (map['request'] as Map<String, dynamic>?) ?? const {},
        manifest = UnifiedTool(
          name: (map['name'] as String? ?? 'plugin_tool').trim(),
          description: map['description'] as String? ?? '',
          parametersSchema: (map['schema'] as Map<String, dynamic>?) ??
              const {'type': 'object', 'properties': {}},
          risk: ToolRisk.requiresConfirmation,
        );

  final Map<String, dynamic> _request;

  @override
  final UnifiedTool manifest;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final url = (_request['url'] as String? ?? '').trim();
    if (url.isEmpty || !url.startsWith('http')) {
      return ToolResult.failure(
        code: ToolCodes.notConfigured,
        message: '插件工具未配置有效 URL',
      );
    }
    final method = (_request['method'] as String? ?? 'GET').toUpperCase();
    // 只读方法可确定没有改动外部世界；其余方法一旦发出就可能已生效。
    final readOnly = method == 'GET' || method == 'HEAD';
    try {
      final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20)));
      final response = method == 'POST'
          ? await dio.post<dynamic>(url, data: arguments)
          : await dio.get<dynamic>(url, queryParameters: arguments);
      return ToolResult.text(
        jsonEncode({'status': response.statusCode, 'data': response.data}),
        effect: readOnly ? ToolEffect.none : ToolEffect.applied,
      );
    } catch (error) {
      return ToolResult.failure(
        code: ToolCodes.networkUnavailable,
        message: '插件工具执行失败：$error'
            '${readOnly ? '' : '；请求可能已送达，请先确认对方状态再决定是否重试'}',
        effect: readOnly ? ToolEffect.none : ToolEffect.unknown,
      );
    }
  }
}
