/// 工具影响的范围（ToolSpec v2）。
enum ToolEffectScope {
  /// 读写当前工作区的文件。
  workspace,

  /// 启动进程（终端命令等）。
  process,

  /// 操作设备本身（系统设置、应用、通知等）。
  device,

  /// 访问外部网络服务。
  network,
}

/// 工具在声明中给出的行为特征（ToolSpec v2）。
///
/// 管线和审计优先读这里，不再各自维护工具名单。未声明的工具（MCP、插件、旧工具）
/// 按 [ToolTraits.undeclared] 处理：不假定只读，使用方退回旧的名称规则。
///
/// 与「敏感操作」（`UnifiedTool.sensitive`）和「持久化脱敏」（`SensitiveToolPolicy`）
/// 无关，三者各管一件事，不要互相推导。
class ToolTraits {
  const ToolTraits({
    required this.readOnly,
    this.scopes = const {},
    this.pathArguments = const [],
    this.fileOperation = false,
  }) : declared = true;

  const ToolTraits._undeclared()
      : readOnly = false,
        scopes = const {},
        pathArguments = const [],
        fileOperation = false,
        declared = false;

  static const undeclared = ToolTraits._undeclared();

  /// 只读取工作区文件。
  static const workspaceRead = ToolTraits(
    readOnly: true,
    scopes: {ToolEffectScope.workspace},
    pathArguments: ['path'],
    fileOperation: true,
  );

  /// 修改 `path` 指向的工作区文件。
  static const workspaceWrite = ToolTraits(
    readOnly: false,
    scopes: {ToolEffectScope.workspace},
    pathArguments: ['path'],
    fileOperation: true,
  );

  /// 纯计算或只改运行内状态，不触及外部世界。
  static const pure = ToolTraits(readOnly: true);

  /// 是否由工具本身声明；false 时其余字段都是保守默认值。
  final bool declared;

  /// 不产生任何外部副作用。
  final bool readOnly;

  final Set<ToolEffectScope> scopes;

  /// 取值为工作区相对路径的参数名；写工具据此在执行前保存原始文件。
  final List<String> pathArguments;

  /// 审计中按「文件操作」而不是一般工具调用记录。
  final bool fileOperation;

  /// 会修改工作区中可由 [pathArguments] 确定的文件。
  bool get writesWorkspace =>
      declared &&
      !readOnly &&
      scopes.contains(ToolEffectScope.workspace) &&
      pathArguments.isNotEmpty;
}
