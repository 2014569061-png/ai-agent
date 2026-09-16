import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;

import '../domain/agent_draft.dart';
import '../domain/models.dart';
import '../infrastructure/providers/llm_provider.dart';
import '../infrastructure/providers/provider_config.dart';
import '../infrastructure/providers/provider_factory.dart';

/// 把用户的一句话目标转成一份 Agent 草稿。
///
/// 四条设计约束（与「手机是指挥台、人在环路」的定位对齐）：
///
/// 1. **生成即建议，绝不落库、绝不授予运行时权限。** 草稿只是编辑器的预填内容，
///    写库仍由用户在编辑器里显式保存触发。
/// 2. **最小权限作默认值。** 只默认勾选安全级工具；需确认与高风险工具列出来让
///    用户自己决定——「少授权」用户补勾很便宜，「多授权」是安全边界问题而用户
///    不一定会注意到。
/// 3. **可离线退化。** 未配置模型、调用失败或输出无法解析时，回退到本地确定性
///    草稿并如实说明原因，不让入口变成死路。
/// 4. **解析是纯函数**，可脱离网络单测。
class AgentDraftService {
  const AgentDraftService();

  /// 生成提示词。与网络无关的纯函数，便于单测覆盖。
  String buildPrompt({
    required String goal,
    required List<AgentToolSpec> tools,
  }) {
    final buffer = StringBuffer()
      ..writeln('请根据用户目标，为一个移动端 AI Agent 平台设计一个可复用的智能体。')
      ..writeln()
      ..writeln('用户目标：${goal.trim()}')
      ..writeln()
      ..writeln('当前设备实际可用的工具（只能从中选择，不要虚构不存在的工具）：');
    if (tools.isEmpty) {
      buffer.writeln('- （当前没有可用工具）');
    } else {
      for (final tool in tools) {
        buffer.writeln(
            '- ${tool.name}（${_riskLabel(tool.risk)}）：${_shorten(tool.description, 80)}');
      }
    }
    buffer
      ..writeln()
      ..writeln('输出要求：')
      ..writeln('1. 只输出一个 JSON 对象，不要输出解释文字，不要使用 Markdown 代码围栏。')
      ..writeln('2. JSON 字段如下：')
      ..writeln('   name：中文短名，4-12 字，一眼能看出职责')
      ..writeln('   role：一句话角色定位')
      ..writeln('   systemPrompt：系统指令正文，用第二人称「你」，写清职责、输入与输出要求')
      ..writeln('   workflow：字符串数组，3-6 条可执行的工作步骤')
      ..writeln('   constraints：字符串数组，3-5 条约束与边界，说明不做什么、必须遵守什么')
      ..writeln('   acceptance：字符串数组，2-4 条「怎样算完成」的验收条件')
      ..writeln('   tools：字符串数组，只从上面的工具清单里挑真正需要的；宁少勿多')
      ..writeln('   maxSteps：整数，1-32')
      ..writeln('   temperature：小数，0-2')
      ..writeln('3. constraints 必须包含「只使用已授权工具、需要额外权限先说明、不绕过审批」这类边界。')
      ..writeln('4. 你只是在设计智能体，不要声称已经执行过任何操作。');
    return buffer.toString();
  }

  /// 把模型返回的一段文本解析成草稿。
  ///
  /// 任何异常都不向上抛：解析失败会退化为本地确定性草稿，并在 `notes` 里说明原因。
  AgentDraft parseDraft({
    required String raw,
    required String goal,
    required List<AgentToolSpec> tools,
  }) {
    final notes = <String>[];
    final decoded = _decodeJsonObject(raw);
    if (decoded == null) {
      notes.add(raw.trim().isEmpty
          ? '模型没有返回内容，已用本地草稿预填'
          : '模型输出不是可解析的 JSON，已用本地草稿预填');
      return _fallbackDraft(goal: goal, tools: tools, notes: notes);
    }

    final name = _string(decoded['name']).trim();
    final role = _string(decoded['role']).trim();
    final body = _string(decoded['systemPrompt']).trim();
    final workflow = _stringList(decoded['workflow']);
    final constraints = _stringList(decoded['constraints']);
    final acceptance = _stringList(decoded['acceptance']);

    final prompt = _composePrompt(
      name: name,
      role: role,
      body: body,
      workflow: workflow,
      constraints: constraints,
      acceptance: acceptance,
    );
    if (name.isEmpty && prompt.isEmpty) {
      notes.add('模型输出缺少名称与系统指令，已用本地草稿预填');
      return _fallbackDraft(goal: goal, tools: tools, notes: notes);
    }

    // 工具归属：先按当前目录校验（不存在的剔除），再按风险分级决定是否默认勾选。
    final byName = {for (final tool in tools) tool.name: tool};
    final granted = <String>{};
    final pending = <String>[];
    final unknown = <String>[];
    for (final requested in _stringList(decoded['tools'])) {
      final tool = byName[requested];
      if (tool == null) {
        unknown.add(requested);
      } else if (tool.risk == ToolRisk.safe) {
        granted.add(tool.name);
      } else if (!pending.contains(tool.name)) {
        pending.add(tool.name);
      }
    }
    if (unknown.isNotEmpty) {
      notes.add('已剔除当前不可用的工具：${unknown.join('、')}');
    }
    if (pending.isNotEmpty) {
      notes.add('以下工具高于安全级，未默认勾选，请自行确认：${pending.join('、')}');
    }

    return AgentDraft(
      goal: goal,
      name: name.isEmpty ? _fallbackName(goal) : name,
      systemPrompt: prompt.isEmpty ? _fallbackPrompt() : prompt,
      grantedTools: granted,
      pendingTools: pending,
      unknownTools: unknown,
      maxSteps: _intInRange(decoded['maxSteps'],
          min: 1, max: 32, fallback: AgentDraft.defaultMaxSteps),
      temperature: _doubleInRange(decoded['temperature'],
          min: 0, max: 2, fallback: AgentDraft.defaultTemperature),
      maxTokens: _intInRange(decoded['maxTokens'],
          min: 256, max: 8192, fallback: AgentDraft.defaultMaxTokens),
      topP: _doubleInRange(decoded['topP'],
          min: 0, max: 1, fallback: AgentDraft.defaultTopP),
      notes: notes,
      fromModel: true,
    );
  }

  /// 调用模型生成草稿。`provider` 可注入，便于测试与复用既有连接。
  Future<AgentDraft> generate({
    required ProviderConfig config,
    required String goal,
    required List<AgentToolSpec> tools,
    LlmProvider? provider,
    CancelToken? cancelToken,
  }) async {
    final trimmed = goal.trim();
    if (trimmed.isEmpty) {
      return _fallbackDraft(
          goal: goal, tools: tools, notes: const ['请先描述这个智能体要做什么']);
    }

    final client =
        provider ?? (config.isConfigured ? createLlmProvider(config) : null);
    if (client == null) {
      return _fallbackDraft(
          goal: goal, tools: tools, notes: const ['尚未配置可用的模型，已用本地草稿预填']);
    }

    final buffer = StringBuffer();
    try {
      final stream = client.stream(
        UnifiedRequest(
          model: config.model,
          messages: [
            ChatMessage(
              role: MessageRole.user,
              parts: [MessagePart.text(buildPrompt(goal: trimmed, tools: tools))],
            ),
          ],
          // 结构化输出任务：低温更稳，且不需要长回答。
          temperature: 0.3,
          maxTokens: 1600,
          reasoningEffort: ReasoningEffort.off,
        ),
        cancelToken: cancelToken,
      );
      await for (final event in stream) {
        if (event is TextDeltaEvent) buffer.write(event.text);
      }
    } catch (error) {
      return _fallbackDraft(
          goal: goal, tools: tools, notes: ['调用模型失败（$error），已用本地草稿预填']);
    }
    return parseDraft(raw: buffer.toString(), goal: trimmed, tools: tools);
  }

  // --- 解析与组装 ---

  String _composePrompt({
    required String name,
    required String role,
    required String body,
    required List<String> workflow,
    required List<String> constraints,
    required List<String> acceptance,
  }) {
    final buffer = StringBuffer();
    if (role.isNotEmpty) {
      buffer.writeln(name.isEmpty ? role : '你是「$name」。$role');
    } else if (name.isNotEmpty) {
      buffer.writeln('你是「$name」。');
    }
    if (body.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(body);
      buffer.writeln();
    }
    _appendSection(buffer, '工作步骤', workflow, ordered: true);
    _appendSection(buffer, '约束与边界', constraints);
    _appendSection(buffer, '验收条件', acceptance);
    return buffer.toString().trim();
  }

  void _appendSection(StringBuffer buffer, String title, List<String> items,
      {bool ordered = false}) {
    if (items.isEmpty) return;
    buffer.writeln();
    buffer.writeln('## $title');
    for (var i = 0; i < items.length; i++) {
      buffer.writeln(ordered ? '${i + 1}. ${items[i]}' : '- ${items[i]}');
    }
  }

  AgentDraft _fallbackDraft({
    required String goal,
    required List<AgentToolSpec> tools,
    required List<String> notes,
  }) {
    return AgentDraft(
      goal: goal,
      name: _fallbackName(goal),
      systemPrompt: _fallbackPrompt(),
      grantedTools: {
        for (final tool in tools)
          if (tool.risk == ToolRisk.safe) tool.name,
      },
      pendingTools: [
        for (final tool in tools)
          if (tool.risk != ToolRisk.safe) tool.name,
      ],
      maxSteps: AgentDraft.defaultMaxSteps,
      temperature: AgentDraft.defaultTemperature,
      maxTokens: AgentDraft.defaultMaxTokens,
      topP: AgentDraft.defaultTopP,
      notes: notes,
      fromModel: false,
    );
  }

  String _fallbackPrompt() => '你是一个目标明确的 AI 助手。\n\n'
      '## 工作步骤\n'
      '1. 先复述你要完成的目标，确认理解无误后再动手。\n'
      '2. 只使用已授权的工具推进；缺少必要工具时说明需要什么，不要绕过审批。\n'
      '3. 完成后说明做了什么、依据是什么、还有哪些不确定。\n\n'
      '## 约束与边界\n'
      '- 只使用已授权的工具；需要额外权限时先说明理由，不要自行绕过审批。\n'
      '- 信息不足时先澄清，不要臆测。\n'
      '- 不声称执行过尚未执行的操作。';

  String _fallbackName(String goal) {
    final trimmed = goal.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return 'AI 助手';
    // 截断后要再 trim 一次：目标里常有空格，否则名称会以空格结尾。
    final cut =
        trimmed.length <= 12 ? trimmed : trimmed.substring(0, 12).trim();
    return cut.isEmpty ? 'AI 助手' : cut;
  }

  /// 容忍 Markdown 代码围栏与前后解释文字，取最外层 JSON 对象。
  Map<String, dynamic>? _decodeJsonObject(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    text = text.replaceAll(RegExp(r'```[a-zA-Z]*'), '').trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _string(Object? value) => value is String ? value : '';

  /// 宽容解析字符串数组：同时接受单个字符串（按逗号/换行切分）。
  List<String> _stringList(Object? value) {
    if (value is String) {
      return value
          .split(RegExp(r'[,，\n]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is! List) return const [];
    final result = <String>[];
    for (final item in value) {
      if (item is! String) continue;
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) result.add(trimmed);
    }
    return result;
  }

  int _intInRange(Object? value,
      {required int min, required int max, required int fallback}) {
    final parsed =
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    if (parsed == null) return fallback;
    return parsed.clamp(min, max);
  }

  double _doubleInRange(Object? value,
      {required double min, required double max, required double fallback}) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return fallback;
    return parsed.clamp(min, max);
  }

  String _shorten(String value, int max) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed.length <= max ? trimmed : '${trimmed.substring(0, max)}…';
  }

  String _riskLabel(ToolRisk risk) => switch (risk) {
        ToolRisk.safe => '安全',
        ToolRisk.requiresConfirmation => '需逐次确认',
        ToolRisk.dangerous => '高风险',
      };
}
