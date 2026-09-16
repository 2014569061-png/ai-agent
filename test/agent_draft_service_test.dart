import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/agent_draft_service.dart';
import 'package:mobile_agent/domain/agent_draft.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/providers/llm_provider.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';

/// 覆盖三个风险等级，用来验证「默认最小权限」的分级规则。
const _tools = <AgentToolSpec>[
  AgentToolSpec(name: 'read_file', description: '读取工作区文件', risk: ToolRisk.safe),
  AgentToolSpec(name: 'calculator', description: '计算表达式', risk: ToolRisk.safe),
  AgentToolSpec(
      name: 'terminal',
      description: '执行终端命令',
      risk: ToolRisk.requiresConfirmation),
  AgentToolSpec(
      name: 'delete_file', description: '删除工作区文件', risk: ToolRisk.dangerous),
];

const _modelJson = '{"name":"代码审查员","role":"你负责审查代码质量。",'
    '"systemPrompt":"关注空指针与边界条件，输出问题清单。",'
    '"workflow":["读取改动","定位风险","给出结论"],'
    '"constraints":["只使用已授权工具","不绕过审批"],'
    '"acceptance":["每个问题都有定位与依据"],'
    '"tools":["read_file","terminal","ghost_tool"],'
    '"maxSteps":12,"temperature":0.4}';

const _configured = ProviderConfig(
  baseUrl: 'https://api.openai.com/v1',
  model: 'gpt-4o-mini',
  apiKey: 'sk-test',
);

/// 云端地址但缺少 Key：`isConfigured` 为 false。
const _unconfigured = ProviderConfig(
  baseUrl: 'https://api.openai.com/v1',
  model: 'gpt-4o-mini',
  apiKey: '',
);

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.chunks);

  final List<String> chunks;
  final requests = <UnifiedRequest>[];

  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    requests.add(request);
    for (final chunk in chunks) {
      yield TextDeltaEvent(chunk);
    }
    yield const CompletedEvent();
  }
}

class _FailingProvider implements LlmProvider {
  @override
  Stream<UnifiedEvent> stream(UnifiedRequest request,
      {CancelToken? cancelToken}) async* {
    throw StateError('boom');
  }
}

void main() {
  const service = AgentDraftService();

  test('生成提示词只列出给定工具并写明输出契约', () {
    final prompt = service.buildPrompt(goal: '帮我审代码', tools: _tools);

    expect(prompt, contains('帮我审代码'));
    expect(prompt, contains('read_file'));
    expect(prompt, contains('delete_file'));
    // 风险标签要让模型看见，否则它会把高风险工具当成普通工具来规划。
    expect(prompt, contains('高风险'));
    expect(prompt, contains('只输出一个 JSON 对象'));
    expect(prompt, isNot(contains('ghost_tool')));

    expect(service.buildPrompt(goal: 'x', tools: const []),
        contains('当前没有可用工具'));
  });

  test('解析模型输出并把步骤、约束、验收折进系统指令', () {
    final draft =
        service.parseDraft(raw: _modelJson, goal: '帮我审代码', tools: _tools);

    expect(draft.fromModel, isTrue);
    expect(draft.name, '代码审查员');
    expect(draft.systemPrompt, contains('你是「代码审查员」。你负责审查代码质量。'));
    expect(draft.systemPrompt, contains('## 工作步骤'));
    expect(draft.systemPrompt, contains('1. 读取改动'));
    expect(draft.systemPrompt, contains('## 约束与边界'));
    expect(draft.systemPrompt, contains('## 验收条件'));
    expect(draft.maxSteps, 12);
    expect(draft.temperature, closeTo(0.4, 1e-9));
  });

  test('只默认授予安全级工具，其余列为待确认，未知工具被剔除', () {
    final draft =
        service.parseDraft(raw: _modelJson, goal: '帮我审代码', tools: _tools);

    expect(draft.grantedTools, {'read_file'});
    expect(draft.pendingTools, ['terminal']);
    expect(draft.unknownTools, ['ghost_tool']);
    expect(draft.notes.any((note) => note.contains('ghost_tool')), isTrue);
    expect(draft.notes.any((note) => note.contains('terminal')), isTrue);
  });

  test('高风险工具即使被模型选中也不默认授予', () {
    final draft = service.parseDraft(
      raw: '{"name":"删除助手","systemPrompt":"你负责清理文件。",'
          '"tools":["delete_file","calculator"]}',
      goal: '清理临时文件',
      tools: _tools,
    );

    expect(draft.grantedTools, {'calculator'});
    expect(draft.pendingTools, ['delete_file']);
  });

  test('容忍 Markdown 代码围栏与前后解释文字', () {
    final draft = service.parseDraft(
      raw: '好的，结果如下：\n```json\n$_modelJson\n```\n希望有帮助。',
      goal: '帮我审代码',
      tools: _tools,
    );

    expect(draft.fromModel, isTrue);
    expect(draft.name, '代码审查员');
  });

  test('非 JSON 输出回退为本地草稿并说明原因', () {
    final draft =
        service.parseDraft(raw: '我建议你这样做…', goal: '帮我审代码', tools: _tools);

    expect(draft.fromModel, isFalse);
    expect(draft.systemPrompt, isNotEmpty);
    expect(draft.notes.single, contains('不是可解析的 JSON'));
    // 回退路径同样遵守最小权限：只给安全级，其余列为待确认。
    expect(draft.grantedTools, {'read_file', 'calculator'});
    expect(draft.pendingTools, ['terminal', 'delete_file']);
  });

  test('空输出回退为本地草稿', () {
    final draft = service.parseDraft(raw: '   ', goal: '帮我审代码', tools: _tools);

    expect(draft.fromModel, isFalse);
    expect(draft.notes.single, contains('没有返回内容'));
  });

  test('越界或非数字参数被夹到编辑器允许的范围', () {
    final draft = service.parseDraft(
      raw: '{"name":"a","systemPrompt":"b","maxSteps":999,"temperature":9,'
          '"maxTokens":10,"topP":-1}',
      goal: 'g',
      tools: _tools,
    );

    expect(draft.maxSteps, 32);
    expect(draft.temperature, 2.0);
    expect(draft.maxTokens, 256);
    expect(draft.topP, 0.0);

    final nonNumeric = service.parseDraft(
      raw: '{"name":"a","systemPrompt":"b","maxSteps":"很多","temperature":"高"}',
      goal: 'g',
      tools: _tools,
    );
    expect(nonNumeric.maxSteps, AgentDraft.defaultMaxSteps);
    expect(nonNumeric.temperature, AgentDraft.defaultTemperature);
  });

  test('缺少名称时用目标前 12 字兜底且不留尾部空格', () {
    final draft = service.parseDraft(
      raw: '{"systemPrompt":"你是助手。"}',
      goal: '帮我审查所有 Java 代码的空指针问题',
      tools: _tools,
    );

    expect(draft.name, startsWith('帮我审查'));
    expect(draft.name.length, lessThanOrEqualTo(12));
    expect(draft.name.trim(), draft.name);
  });

  test('宽容解析以字符串形式给出的工具清单', () {
    final draft = service.parseDraft(
      raw: '{"name":"a","systemPrompt":"b","tools":"read_file, calculator"}',
      goal: 'g',
      tools: _tools,
    );

    expect(draft.grantedTools, {'read_file', 'calculator'});
  });

  test('未配置模型时直接回退且说明原因', () async {
    final draft = await service.generate(
        config: _unconfigured, goal: '帮我审代码', tools: _tools);

    expect(draft.fromModel, isFalse);
    expect(draft.notes.single, contains('尚未配置可用的模型'));
  });

  test('空目标不调用模型', () async {
    final provider = _ScriptedProvider(['{}']);
    final draft = await service.generate(
        config: _configured, goal: '   ', tools: _tools, provider: provider);

    expect(provider.requests, isEmpty);
    expect(draft.notes.single, contains('先描述'));
  });

  test('模型正常返回时拼接增量文本并解析成草稿', () async {
    final provider = _ScriptedProvider(['```json\n', _modelJson, '\n```']);
    final draft = await service.generate(
        config: _configured, goal: '帮我审代码', tools: _tools, provider: provider);

    expect(provider.requests, hasLength(1));
    expect(provider.requests.single.model, 'gpt-4o-mini');
    // 草稿生成是纯文本任务：不能顺手把工具挂上去，否则模型可能真的去调用。
    expect(provider.requests.single.tools, isEmpty);
    expect(draft.fromModel, isTrue);
    expect(draft.name, '代码审查员');
  });

  test('模型调用抛错时回退且不向调用方抛异常', () async {
    final draft = await service.generate(
        config: _configured,
        goal: '帮我审代码',
        tools: _tools,
        provider: _FailingProvider());

    expect(draft.fromModel, isFalse);
    expect(draft.notes.single, contains('调用模型失败'));
  });
}
