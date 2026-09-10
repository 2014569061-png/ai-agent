import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/sensitive_tool_policy.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';
import 'package:mobile_agent/infrastructure/tools/core_tools.dart';
import 'package:mobile_agent/infrastructure/tools/image_gen_tool.dart';
import 'package:mobile_agent/infrastructure/tools/plan_tool.dart';
import 'package:mobile_agent/infrastructure/tools/skill_tools.dart';
import 'package:mobile_agent/infrastructure/tools/sub_agent_tool.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';

/// 用真实的工具实例组装一份完整注册表（镜像 ChatController._buildRegistry），
/// 让守护测试直接对**真实存在**的工具名取交集，而不是对一份手写清单取信。
ToolRegistry _buildFullRegistry(AppDatabase db) {
  final registry = ToolRegistry();
  registry.register(CalculatorTool());
  registry.register(GetTimeTool());
  registry.register(JsonQueryTool());
  registry.register(HttpRequestTool());
  registry.register(WebSearchTool(apiKey: 'test-key'));
  registry.register(ImageGenTool(
    config: const ProviderConfig(
      baseUrl: 'https://example.invalid',
      model: 'test-model',
      apiKey: 'test-key',
    ),
  ));
  registry.register(RememberTool(
    onRemember: (content) async {},
    onRememberWithRevision: (content, expectedRevision) async =>
        ToolResult.text('ok'),
  ));
  registry.register(MemoryGetTool(
    onGet: (query, offset, limit) async => ToolResult.text('[]'),
  ));
  registry.register(MemoryWriteTool(
    onWrite: ({
      required String? id,
      required String content,
      required String mode,
      required int? startLine,
      required int? endLine,
      required String? expectedRevision,
    }) async =>
        ToolResult.text('ok'),
  ));
  registry.register(SkillsReadTool(database: db));
  registry.register(SkillsReadResourceTool(database: db));
  registry.register(SubAgentTool(onRun: (agentId, prompt, budget) async => 'ok'));
  registry.register(ManagePlanTool(onPlanUpdated: (steps) async {}));

  const workspace = '/tmp/nexus-sensitive-policy-test';
  final sandbox = WorkspaceSandbox(workspace);
  registry.register(ReadFileTool(sandbox: sandbox));
  registry.register(WriteFileTool(sandbox: sandbox));
  registry.register(EditFileTool(sandbox: sandbox));
  registry.register(ListDirectoryTool(sandbox: sandbox));
  registry.register(SearchFilesTool(sandbox: sandbox));
  registry.register(DeleteFileTool(sandbox: sandbox));
  registry.register(MoveFileTool(sandbox: sandbox));
  registry.register(TerminalCommandTool(
    service: TerminalCommandService(workspacePath: workspace),
  ));
  return registry;
}

void main() {
  late AppDatabase db;
  late Set<String> realToolNames;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    realToolNames =
        _buildFullRegistry(db).manifests.map((m) => m.name).toSet();
  });

  tearDown(() async {
    await db.close();
  });

  test('真实工具目录非空，守护测试本身是有效的', () {
    // 若装配方式失效（例如漏注册），下面的用例会变成"空集断言"而失去意义，
    // 因此这里先固定住基线规模。
    expect(realToolNames.length, greaterThanOrEqualTo(20));
    expect(
      realToolNames,
      containsAll(<String>[
        'http_request',
        'terminal',
        'write_file',
        'edit_file',
        'read_file',
        'memory_get',
        'memory_write',
        'remember',
        'sub_agent',
        'generate_image',
      ]),
    );
  });

  test('脱敏名单里的每个名字都真实存在（防死条目回归）', () {
    final deadArguments = SensitiveToolPolicy.argumentRedactedTools
        .difference(realToolNames);
    final deadResults =
        SensitiveToolPolicy.resultRedactedTools.difference(realToolNames);

    expect(deadArguments, isEmpty,
        reason: '参数脱敏名单包含不存在的工具：$deadArguments');
    expect(deadResults, isEmpty,
        reason: '结果脱敏名单包含不存在的工具：$deadResults');
  });

  test('凡 manifest.sensitive == true 的工具都被结果脱敏覆盖（防漏配）', () {
    final sensitiveManifests = _buildFullRegistry(db)
        .manifests
        .where((m) => m.sensitive)
        .map((m) => m.name)
        .toList(growable: false);
    expect(sensitiveManifests, isNotEmpty,
        reason: '当前存在 sensitive 工具，覆盖断言应非空');

    for (final name in sensitiveManifests) {
      expect(SensitiveToolPolicy.isResultSensitive(name), isTrue,
          reason: '强制审批的敏感工具 $name 未纳入结果脱敏名单');
    }
  });

  test('高敏工具的原始参数不会明文落库（回归用例）', () {
    // http_request 的参数可含 Authorization 头，必须整体占位。
    final redacted = SensitiveToolPolicy.redactArguments('http_request', {
      'url': 'https://api.example.com',
      'headers': {'Authorization': 'Bearer sk-super-secret'},
    });
    expect(redacted, {'redacted': true});

    // terminal 的命令行可能含 token / 私有路径。
    expect(
      SensitiveToolPolicy.redactArguments(
          'terminal', {'command': 'export TOKEN=abc'}),
      {'redacted': true},
    );
    // write_file / edit_file 的写入内容可能含密钥。
    expect(
      SensitiveToolPolicy.redactArguments('write_file', {'content': 'k=1'}),
      {'redacted': true},
    );
    expect(
      SensitiveToolPolicy.redactArguments('edit_file', {'newText': 'k=1'}),
      {'redacted': true},
    );
    // 旧命名的 MCP 工具沿用远端口径，参数同样脱敏。
    expect(
      SensitiveToolPolicy.redactArguments(
          'remoteserver.echo', {'secret': 'value'}),
      {'redacted': true},
    );
    expect(
      SensitiveToolPolicy.redactArguments('mcp_private', {'secret': 'value'}),
      {'redacted': true},
    );
  });

  test('terminal 结果脱敏，read_file 结果保持原样（回归用例）', () {
    final terminalResult = ToolResult.text('token=abc123\n/home/user/.ssh');

    final redactedTerminal =
        SensitiveToolPolicy.redactResult('terminal', terminalResult);
    expect(redactedTerminal.data, {'redacted': true});
    expect(redactedTerminal.ok, isTrue);
    expect(redactedTerminal.message, contains('脱敏'));
    expect(
      SensitiveToolPolicy.redactResultText('terminal', terminalResult.display),
      '[敏感工具内容已脱敏]',
    );

    // read_file 是用户自己的工作区文件：参数与结果都必须原样保留。
    final fileResult = ToolResult.text('文件内容：hello world');
    expect(
      SensitiveToolPolicy.redactResult('read_file', fileResult),
      same(fileResult),
    );
    expect(
      SensitiveToolPolicy.redactArguments('read_file', {'path': 'a.txt'}),
      {'path': 'a.txt'},
    );
    expect(
      SensitiveToolPolicy.redactResultText('read_file', fileResult.display),
      fileResult.display,
    );
  });

  test('参数语境与结果语境使用不同判定（意图不可互换）', () {
    // write_file：参数敏感、结果不敏感。
    expect(SensitiveToolPolicy.isArgumentSensitive('write_file'), isTrue);
    expect(SensitiveToolPolicy.isResultSensitive('write_file'), isFalse);
    // memory_get：结果敏感、参数不敏感。
    expect(SensitiveToolPolicy.isArgumentSensitive('memory_get'), isFalse);
    expect(SensitiveToolPolicy.isResultSensitive('memory_get'), isTrue);
    // read_file：两者都不敏感。
    expect(SensitiveToolPolicy.isArgumentSensitive('read_file'), isFalse);
    expect(SensitiveToolPolicy.isResultSensitive('read_file'), isFalse);
    // 粗粒度并集只用于单一开关的出口。
    expect(SensitiveToolPolicy.isSensitive('write_file'), isTrue);
    expect(SensitiveToolPolicy.isSensitive('memory_get'), isTrue);
  });
}
