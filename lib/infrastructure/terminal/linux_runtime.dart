/// Linux 执行环境的统一接口。
///
/// 上层只关心命令请求、结果和运行时能力，不直接依赖 Termux、PTY 或
/// PRoot 的实现细节。未来接入内置 Linux 用户空间时，只需新增一个 Adapter。
enum LinuxRuntimeKind { hostProcess, termux, builtinProot, androidShell }

class LinuxRuntimeInfo {
  const LinuxRuntimeInfo({
    required this.kind,
    required this.label,
    required this.available,
    required this.detail,
    this.supportsInteractive = false,
    this.supportsShellSyntax = false,
    this.requiresExternalApp = false,
  });

  final LinuxRuntimeKind kind;
  final String label;
  final bool available;
  final String detail;
  final bool supportsInteractive;
  final bool supportsShellSyntax;
  final bool requiresExternalApp;
}

class LinuxCommandRequest {
  const LinuxCommandRequest({
    required this.commandLine,
    required this.executable,
    required this.normalizedCommand,
    required this.arguments,
    this.shell = 'bash',
  });

  final String commandLine;
  final String executable;
  final String normalizedCommand;
  final List<String> arguments;

  /// 用户在「Linux 工具环境」中选择的 Shell（bash / zsh / sh）。
  /// 仅在支持完整 shell 语法的运行时（Android 侧）生效；桌面受限进程 Adapter
  /// 不理会该字段，仍走命令白名单。
  final String shell;
}

class CommandResult {
  const CommandResult({
    required this.output,
    required this.exitCode,
    this.timedOut = false,
  });

  final String output;
  final int exitCode;
  final bool timedOut;

  bool get succeeded => exitCode == 0 && !timedOut;
}

/// 终端执行的 seam。
///
/// 实现必须保证：工作目录由调用方预先限制在工作区内；超时返回退出码
/// 124；无法启动或运行时不可用时返回非 0 退出码，不抛出影响 Agent 主流程的
/// 未处理异常。
abstract interface class LinuxRuntimeAdapter {
  LinuxRuntimeKind get kind;

  /// 该运行时是否可以安全地接收完整 shell 命令行。
  bool get supportsShellSyntax;

  /// 是否允许解释器的内联求值参数，例如 python -c、node -e。
  bool get supportsInterpreterEvaluation;

  bool get isRunning;

  Future<LinuxRuntimeInfo> inspect();

  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  });

  void stop();
}
