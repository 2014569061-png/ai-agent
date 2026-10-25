import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/providers/provider_config.dart';
import '../infrastructure/tools/android_device_tool.dart';
import '../infrastructure/tools/core_tools.dart';
import '../infrastructure/tools/image_gen_tool.dart';
import '../infrastructure/tools/isolated_sub_agent_tool.dart';
import '../infrastructure/tools/parallel_sub_agents_tool.dart';
import '../infrastructure/tools/plan_tool.dart';
import '../infrastructure/tools/skill_tools.dart';
import '../infrastructure/tools/sub_agent_tool.dart';
import '../infrastructure/tools/tool_registry.dart';
import '../infrastructure/tools/workspace_tool_set.dart';
import 'android_automation_tool.dart';
import 'android_accessibility_observe_tool.dart';
import 'android_accessibility_session_service.dart';
import 'browser_agent_tool.dart';
import 'browser_session_service.dart';
import 'device_automation_service.dart';
import 'run_tool_settings.dart';
import 'scoped_memory_access.dart';

/// Builds capabilities from a frozen run scope and injected callbacks. It does
/// not read Riverpod state or own the chat UI, run lifecycle or external clients.
Future<ToolRegistry> buildChatToolRegistry({
  required Set<String> enabledTools,
  required String tavilyKey,
  required ProviderConfig config,
  required ToolRisk subAgentRisk,
  required ToolSettings settings,
  required Future<AppDatabase> Function() database,
  required Future<String> Function(String?, String, int?) onRunSubAgent,
  required Future<void> Function(List<PlanStep>) onPlanUpdated,
  DeviceAutomationService Function()? automation,
  BrowserSessionService? browser,
  AndroidAccessibilitySessionService? accessibility,
  String? projectId,
  String? conversationId,
  String? workspacePath,
  Future<Map<String, dynamic>> Function(String, int)? onRunIsolated,
}) async {
  final memory = ScopedMemoryAccess(
    database: database,
    projectId: projectId,
    sourceConversationId: conversationId,
  );
  final registry = ToolRegistry();
  for (final tool in <AgentTool>[
    if (enabledTools.contains('calculator')) CalculatorTool(),
    if (enabledTools.contains('get_time')) GetTimeTool(),
    if (enabledTools.contains('json_query')) JsonQueryTool(),
    if (enabledTools.contains('http_request')) HttpRequestTool(),
    if (settings.webBrowsing && enabledTools.contains('web_search'))
      WebSearchTool(apiKey: tavilyKey),
    if (enabledTools.contains('generate_image')) ImageGenTool(config: config),
  ]) {
    registry.register(tool);
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (conversationId != null &&
        browser?.availableFor(conversationId) == true) {
      registry.register(BrowserAgentTool(browser!, conversationId));
    }
    if (conversationId != null &&
        accessibility?.availableFor(conversationId) == true) {
      registry.register(
        AndroidAccessibilityObserveTool(accessibility!, conversationId),
      );
    }
    registry.register(AndroidDevicePreviewTool());
    registry.register(AndroidDeviceTool());
    registry.register(AndroidAppPrivateDataPreviewTool());
    registry.register(AndroidAppPrivateDataTool());
    registry.register(AndroidAutomationTool(service: automation?.call()));
  }
  registry.register(RememberTool(
    onRemember: (content) async {
      final result = await memory.remember(content, null);
      if (!result.ok) throw StateError('Memory save not confirmed');
    },
    onRememberWithRevision: memory.remember,
  ));
  registry.register(MemoryGetTool(onGet: memory.get));
  registry.register(MemoryWriteTool(onWrite: memory.write));
  if (enabledTools.contains('skills_read') ||
      enabledTools.contains('skills_read_resource')) {
    try {
      final db = await database();
      if (enabledTools.contains('skills_read')) {
        registry.register(SkillsReadTool(database: db));
      }
      if (enabledTools.contains('skills_read_resource')) {
        registry.register(SkillsReadResourceTool(database: db));
      }
    } catch (_) {
      // Database availability must not block the remaining capabilities.
    }
  }
  registry.register(SubAgentTool(onRun: onRunSubAgent, risk: subAgentRisk));
  registry.register(
      ParallelSubAgentsTool(onRun: onRunSubAgent, risk: subAgentRisk));
  registry.register(ManagePlanTool(onPlanUpdated: onPlanUpdated));
  if (settings.workspaceFiles &&
      workspacePath != null &&
      workspacePath.isNotEmpty) {
    final desktop = !kIsWeb &&
        {
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform);
    if (desktop && onRunIsolated != null) {
      registry.register(IsolatedSubAgentTool(onRun: onRunIsolated));
    }
    for (final tool in workspaceToolSet(
      workspacePath: workspacePath,
      terminalEnabled: settings.terminal && !kIsWeb,
    )) {
      registry.register(tool);
    }
  }
  return registry;
}
