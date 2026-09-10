import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/tools/sub_agent_tool.dart';
import 'package:mobile_agent/application/autonomous_delegation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubAgentTool', () {
    test('默认采用自主安全策略（risk = safe），并支持配置风险等级', () {
      final autonomous = SubAgentTool(onRun: (a, p, b) async => '');
      expect(autonomous.manifest.risk, ToolRisk.safe);

      final gated = SubAgentTool(
        onRun: (a, p, b) async => '',
        risk: ToolRisk.requiresConfirmation,
      );
      expect(gated.manifest.risk, ToolRisk.requiresConfirmation);
    });

    test('schema 暴露可选的受限预算字段 maxTokens', () {
      final tool = SubAgentTool(onRun: (a, p, b) async => '');
      final schema = tool.manifest.parametersSchema;
      final props = (schema['properties'] as Map)['maxTokens'] as Map;
      expect(props['type'], 'integer');
      expect(props['minimum'], SubAgentTool.minBudget);
      expect(props['maximum'], SubAgentTool.maxBudget);
    });

    test('clampBudget 把越界/缺省预算钳制到 [500, 8000]', () {
      expect(SubAgentTool.clampBudget(null), SubAgentTool.maxBudget);
      expect(SubAgentTool.clampBudget(100), SubAgentTool.minBudget);
      expect(SubAgentTool.clampBudget(100000), SubAgentTool.maxBudget);
      expect(SubAgentTool.clampBudget(2000), 2000);
      expect(SubAgentTool.clampBudget(500), SubAgentTool.minBudget);
      expect(SubAgentTool.clampBudget(8000), SubAgentTool.maxBudget);
    });

    test('execute 透传 maxTokens 预算给回调，并解析 agentId/prompt', () async {
      String? receivedAgent;
      String? receivedPrompt;
      int? receivedBudget;
      final tool = SubAgentTool(onRun: (a, p, b) async {
        receivedAgent = a;
        receivedPrompt = p;
        receivedBudget = b;
        return 'ok';
      });

      final result = await tool.execute({
        'agentId': 'planner',
        'prompt': '  分析模块依赖  ',
        'maxTokens': 3000,
      });
      expect(result.ok, isTrue);
      expect(result.data?['text'], 'ok');
      expect(receivedAgent, 'planner');
      expect(receivedPrompt, '分析模块依赖');
      expect(receivedBudget, 3000);
    });

    test('prompt 为空时提示错误且不调用回调', () async {
      var called = false;
      final tool = SubAgentTool(onRun: (a, p, b) async {
        called = true;
        return 'x';
      });
      final result = await tool.execute({'prompt': '   '});
      expect(result.ok, isFalse);
      expect(result.code, ToolCodes.invalidArguments);
      expect(result.message, contains('请提供子任务描述'));
      expect(called, isFalse);
    });
  });

  group('AutonomousDelegationService', () {
    late AutonomousDelegationService service;

    setUp(() {
      service = AutonomousDelegationService();
    });

    test('未配置时默认开启（自主）', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await service.isEnabled(), isTrue);
    });

    test('关闭后可持久化，再次读取保持关闭', () async {
      SharedPreferences.setMockInitialValues({});
      await service.setEnabled(false);
      expect(await service.isEnabled(), isFalse);
    });

    test('重新开启后恢复自主', () async {
      SharedPreferences.setMockInitialValues({});
      await service.setEnabled(false);
      await service.setEnabled(true);
      expect(await service.isEnabled(), isTrue);
    });
  });
}
