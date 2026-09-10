import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import 'tool_catalog.dart';

export 'tool_catalog.dart';

/// 纯执行契约。它不携带 schema，便于把同一个执行器挂到不同的能力投影上。
abstract interface class ToolExecutor {
  Future<ToolResult> execute(Map<String, dynamic> arguments);
}

/// 一次注册中 schema 与执行器的配对。
///
/// 目录投影只会替换 [spec]，不会复制或修改执行器，确保能力收窄不丢失
/// 工具内部状态（例如终端会话、MCP 客户端或文件变更元数据）。
class ToolRegistration {
  const ToolRegistration({required this.spec, required this.executor});

  final ToolSpec spec;
  final ToolExecutor executor;
}

/// 工具的声明部分。目录只保存这一层，不持有任何运行时状态。
class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    required this.parametersSchema,
    required this.risk,
    this.sensitive = false,
    this.requirement = const ToolRequirement(),
    this.timeout = UnifiedTool.defaultTimeout,
  });

  ToolSpec.fromManifest(
    UnifiedTool manifest, {
    ToolRequirement requirement = const ToolRequirement(),
  }) : this(
          name: manifest.name,
          description: manifest.description,
          parametersSchema: manifest.parametersSchema,
          risk: manifest.risk,
          sensitive: manifest.sensitive,
          requirement: requirement,
          timeout: manifest.timeout,
        );

  final String name;
  final String description;
  final Map<String, dynamic> parametersSchema;
  final ToolRisk risk;
  final bool sensitive;
  final ToolRequirement requirement;

  /// 单次执行的超时上限，随 manifest 声明；由 AgentExecutor 统一包装。
  final Duration timeout;

  UnifiedTool get manifest => toManifest();

  UnifiedTool toManifest() => UnifiedTool(
        name: name,
        description: description,
        parametersSchema: deepCopyJsonMap(parametersSchema),
        risk: risk,
        sensitive: sensitive,
        timeout: timeout,
      );

  ToolSpec copyWith({
    String? name,
    String? description,
    Map<String, dynamic>? parametersSchema,
    ToolRisk? risk,
    bool? sensitive,
    ToolRequirement? requirement,
    Duration? timeout,
  }) =>
      ToolSpec(
        name: name ?? this.name,
        description: description ?? this.description,
        parametersSchema:
            deepCopyJsonMap(parametersSchema ?? this.parametersSchema),
        risk: risk ?? this.risk,
        sensitive: sensitive ?? this.sensitive,
        requirement: requirement ?? this.requirement,
        timeout: timeout ?? this.timeout,
      );
}

abstract interface class AgentTool implements ToolExecutor {
  UnifiedTool get manifest;

  /// 执行工具并返回结构化信封。
  ///
  /// 约定：**不得返回自然语言句子代替失败标记**。失败必须带 [ToolCodes] 中的
  /// 错误码，并如实声明 [ToolEffect]——判定不了副作用时用
  /// [ToolEffect.unknown]，让模型先去读取确认而不是盲目重试。
  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments);
}

abstract interface class ToolExecutionMetadata {
  Map<String, dynamic> get lastMetadata;
}

class ToolRegistry {
  ToolRegistry({ToolCatalog? catalog}) : catalog = catalog ?? ToolCatalog();

  final ToolCatalog catalog;
  final Map<String, ToolRegistration> _registrations = {};

  void register(AgentTool tool,
      {ToolRequirement requirement = const ToolRequirement()}) {
    registerPair(
      spec: ToolSpec.fromManifest(
        tool.manifest,
        requirement: requirement,
      ),
      executor: tool,
    );
  }

  /// 注册独立 schema 与执行器。内置工具仍可使用 [register]，插件和能力投影
  /// 则可以只替换声明而不复制执行器状态。
  void registerPair({
    required ToolSpec spec,
    required ToolExecutor executor,
  }) {
    _registrations[spec.name] = ToolRegistration(
      spec: spec.copyWith(),
      executor: executor,
    );
    catalog.register(spec.toManifest(), requirement: spec.requirement);
  }

  void registerManifest(UnifiedTool manifest,
      {ToolRequirement requirement = const ToolRequirement()}) {
    catalog.register(manifest, requirement: requirement);
  }

  /// 兼容旧调用方：只有同时实现了旧 [AgentTool] 接口的工具才能通过这里取到。
  /// 新代码应使用 [findRegistration]，以支持独立的 schema 与 executor。
  AgentTool? find(String name) {
    final executor = _registrations[name]?.executor;
    return executor is AgentTool ? executor : null;
  }

  ToolExecutor? findExecutor(String name) => _registrations[name]?.executor;

  ToolRegistration? findRegistration(String name) => _registrations[name];

  List<UnifiedTool> get manifests => catalog.manifests;

  ToolRegistry project(ToolCapabilitySnapshot snapshot) {
    final projectedCatalog = catalog.project(snapshot);
    final projected = ToolRegistry(catalog: projectedCatalog);
    for (final entry in _registrations.entries) {
      final projectedManifest = projectedCatalog.find(entry.key);
      if (projectedManifest != null) {
        projected._registrations[entry.key] = ToolRegistration(
          spec: ToolSpec.fromManifest(
            projectedManifest,
            requirement: projectedCatalog.requirementFor(entry.key),
          ),
          executor: entry.value.executor,
        );
      }
    }
    return projected;
  }
}

class CalculatorTool implements AgentTool {
  @override
  final manifest = const UnifiedTool(
    name: 'calculator',
    description: '计算两个数字的加法。',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'a': {'type': 'number'},
        'b': {'type': 'number'},
      },
      'required': ['a', 'b'],
    },
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final a = (arguments['a'] as num?)?.toDouble();
    final b = (arguments['b'] as num?)?.toDouble();
    if (a == null || b == null) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: '参数 a 和 b 必须是数字',
      );
    }
    return ToolResult.text('${a + b}');
  }
}
