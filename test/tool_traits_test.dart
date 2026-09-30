// 阶段 6a：ToolSpec v2——工具在声明中给出行为特征，管线与审计据此判断。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/file_baseline_store.dart';
import 'package:mobile_agent/application/tool_pipeline/file_baseline_interceptor.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_invocation.dart';
import 'package:mobile_agent/application/tool_pipeline/tool_run_context.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;
import 'package:mobile_agent/infrastructure/mcp/mcp_tool_provider.dart';
import 'package:mobile_agent/infrastructure/plugins/plugin_store.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';

class _RecordingStore extends FileBaselineStore {
  _RecordingStore() : super(taskId: 't', workspacePath: Directory.systemTemp.path);
  final preserved = <List<String>>[];

  @override
  Future<void> preserve(Iterable<String> paths) async =>
      preserved.add(paths.toList());
}

class _FakeTool implements AgentTool {
  _FakeTool(this.manifest);

  @override
  final UnifiedTool manifest;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      ToolResult.text('ok');
}

UnifiedTool _manifest(String name, ToolTraits traits) => UnifiedTool(
      name: name,
      description: name,
      parametersSchema: const {'type': 'object'},
      risk: ToolRisk.safe,
      traits: traits,
    );

void main() {
  final sandbox = WorkspaceSandbox(Directory.systemTemp.path);
  final fileTools = <AgentTool>[
    ReadFileTool(sandbox: sandbox),
    ListDirectoryTool(sandbox: sandbox),
    SearchFilesTool(sandbox: sandbox),
    WriteFileTool(sandbox: sandbox),
    EditFileTool(sandbox: sandbox),
    DeleteFileTool(sandbox: sandbox),
    MoveFileTool(sandbox: sandbox),
  ];

  test('built-in workspace tools declare their traits', () {
    final byName = {for (final t in fileTools) t.manifest.name: t.manifest.traits};
    for (final traits in byName.values) {
      expect(traits.declared, isTrue);
      expect(traits.fileOperation, isTrue);
      expect(traits.scopes, {ToolEffectScope.workspace});
    }
    for (final name in ['read_file', 'list_directory', 'search_files']) {
      expect(byName[name]!.readOnly, isTrue, reason: name);
      expect(byName[name]!.writesWorkspace, isFalse, reason: name);
    }
    for (final name in ['write_file', 'edit_file', 'delete_file']) {
      expect(byName[name]!.pathArguments, ['path'], reason: name);
      expect(byName[name]!.writesWorkspace, isTrue, reason: name);
    }
    expect(byName['move_file']!.pathArguments, ['path', 'newPath']);
  });

  test('the legacy baseline table agrees with the declarations', () {
    for (final tool in fileTools) {
      final traits = tool.manifest.traits;
      expect(
        FileBaselineInterceptor.mutatingTools[tool.manifest.name],
        traits.writesWorkspace ? traits.pathArguments : isNull,
        reason: tool.manifest.name,
      );
    }
  });

  test('terminal declares process effects and is not a file operation', () {
    final terminal = TerminalCommandTool(
            service: TerminalCommandService(workspacePath: sandbox.rootPath))
        .manifest
        .traits;
    expect(terminal.readOnly, isFalse);
    expect(terminal.scopes, contains(ToolEffectScope.process));
    expect(terminal.writesWorkspace, isFalse, reason: '路径无法从参数确定');
    expect(terminal.fileOperation, isFalse);
  });

  test('traits survive registration, catalog copies and projection', () {
    final registry = ToolRegistry()..register(WriteFileTool(sandbox: sandbox));
    final spec = registry.findRegistration('write_file')!.spec;
    expect(spec.traits.writesWorkspace, isTrue);
    expect(spec.toManifest().traits.pathArguments, ['path']);
    expect(spec.copyWith(description: 'x').traits.fileOperation, isTrue);

    final projected = registry.project(const ToolCapabilitySnapshot());
    expect(projected.findRegistration('write_file')!.spec.traits.writesWorkspace,
        isTrue);
  });

  test('undeclared tools keep the legacy name rules', () {
    expect(ToolTraits.undeclared.declared, isFalse);
    expect(ToolTraits.undeclared.readOnly, isFalse, reason: '不假定只读');
    expect(isFileOperation(null, 'mcp_read_file'), isTrue);
    expect(isFileOperation(null, 'search_files'), isTrue);
    expect(isFileOperation(null, 'weather'), isFalse);
  });

  test('declared traits override name rules for file operations', () {
    final notAFile = ToolSpec.fromManifest(
        _manifest('export_file', const ToolTraits(readOnly: false,
            scopes: {ToolEffectScope.network})));
    expect(isFileOperation(notAFile, 'export_file'), isFalse);
    final custom = ToolSpec.fromManifest(
        _manifest('save_note', ToolTraits.workspaceWrite));
    expect(isFileOperation(custom, 'save_note'), isTrue);
  });

  test('MCP annotations map to advisory traits', () {
    final readOnly = McpTool.traitsFor(const mcp.ToolAnnotations(readOnlyHint: true));
    expect(readOnly.declared, isTrue);
    expect(readOnly.readOnly, isTrue);
    expect(readOnly.scopes, {ToolEffectScope.network});
    expect(McpTool.traitsFor(null).readOnly, isFalse, reason: '缺省按有副作用处理');
    // 远端服务器上的 *_file 工具不是本机工作区的文件操作。
    final spec = ToolSpec.fromManifest(_manifest('mcp_fs.write_file', readOnly));
    expect(isFileOperation(spec, 'mcp_fs.write_file'), isFalse);
    expect(readOnly.writesWorkspace, isFalse);
  });

  test('plugin tools derive traits from their HTTP method', () {
    ToolTraits traits(Map<String, dynamic>? request) =>
        DeclarativeTool.fromManifest({
          'name': 'p',
          if (request != null) 'request': request,
        }).manifest.traits;
    expect(traits(null).readOnly, isTrue, reason: '缺省 GET');
    expect(traits({'method': 'head'}).readOnly, isTrue);
    expect(traits({'method': 'POST'}).readOnly, isFalse);
    expect(traits({'method': 'PUT'}).scopes, {ToolEffectScope.network});
  });

  group('FileBaselineInterceptor', () {
    Future<List<List<String>>> run(
        UnifiedTool? manifest, String name, Map<String, dynamic> args) async {
      final store = _RecordingStore();
      await FileBaselineInterceptor(store).intercept(
        ToolInvocation(
          call: ToolCall(id: 'c1', name: name, arguments: args),
          registration: manifest == null
              ? null
              : ToolRegistration(
                  spec: ToolSpec.fromManifest(manifest),
                  executor: _FakeTool(manifest)),
          context: ToolRunContext.detached(),
        ),
        (_) async => ToolResult.text('ok'),
      );
      return store.preserved;
    }

    test('a declared writer is preserved by its path arguments', () async {
      expect(
        await run(_manifest('save_note', ToolTraits.workspaceWrite),
            'save_note', {'path': 'notes/a.md'}),
        [
          ['notes/a.md']
        ],
      );
    });

    test('a declared non-writer is skipped even with a legacy name', () async {
      expect(
        await run(_manifest('edit_file', ToolTraits.pure), 'edit_file',
            {'path': 'a.txt'}),
        isEmpty,
      );
    });

    test('undeclared tools fall back to the legacy table', () async {
      expect(
        await run(_manifest('edit_file', ToolTraits.undeclared), 'edit_file',
            {'path': 'a.txt'}),
        [
          ['a.txt']
        ],
      );
      expect(await run(null, 'move_file', {'path': 'a', 'newPath': 'b'}), [
        ['a', 'b']
      ]);
    });
  });
}
