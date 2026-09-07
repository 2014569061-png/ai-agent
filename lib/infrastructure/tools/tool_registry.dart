import '../../domain/models.dart';

abstract interface class AgentTool {
  UnifiedTool get manifest;
  Future<String> execute(Map<String, dynamic> arguments);
}

abstract interface class ToolExecutionMetadata {
  Map<String, dynamic> get lastMetadata;
}

class ToolRegistry {
  final Map<String, AgentTool> _tools = {};

  void register(AgentTool tool) => _tools[tool.manifest.name] = tool;

  AgentTool? find(String name) => _tools[name];

  List<UnifiedTool> get manifests =>
      _tools.values.map((tool) => tool.manifest).toList(growable: false);
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
  Future<String> execute(Map<String, dynamic> arguments) async {
    final a = (arguments['a'] as num?)?.toDouble();
    final b = (arguments['b'] as num?)?.toDouble();
    if (a == null || b == null) return '参数 a 和 b 必须是数字';
    return '${a + b}';
  }
}
