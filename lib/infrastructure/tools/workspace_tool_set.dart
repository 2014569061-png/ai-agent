import 'apply_patch_tool.dart';
import 'command_tool.dart';
import 'repo_map_tool.dart';
import 'tool_registry.dart';
import 'workspace_tools.dart';

/// One shared read-before-write sandbox for every tool in a run. Callers retain
/// their own allowlist and approval policy when registering this capability set.
List<AgentTool> workspaceToolSet({
  required String workspacePath,
  bool allowWrites = true,
  bool terminalEnabled = true,
}) {
  final sandbox = WorkspaceSandbox(workspacePath, requireReadBeforeWrite: true);
  return [
    ReadFileTool(sandbox: sandbox),
    RepoMapTool(sandbox: sandbox),
    ListDirectoryTool(sandbox: sandbox),
    SearchFilesTool(sandbox: sandbox),
    if (allowWrites) ...[
      WriteFileTool(sandbox: sandbox),
      EditFileTool(sandbox: sandbox),
      ApplyPatchTool(sandbox: sandbox),
      DeleteFileTool(sandbox: sandbox),
      MoveFileTool(sandbox: sandbox),
      if (terminalEnabled)
        TerminalCommandTool(
          service: TerminalCommandService(workspacePath: workspacePath),
        ),
    ],
  ];
}
