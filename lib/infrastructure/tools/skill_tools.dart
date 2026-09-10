import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import 'package:path/path.dart' as p;
import '../database/app_database.dart';
import '../skills/skill_store.dart';
import 'tool_registry.dart';

class SkillsReadTool implements AgentTool {
  SkillsReadTool({required this.database});
  final AppDatabase database;

  @override
  final manifest = const UnifiedTool(
    name: 'skills_read',
    description: '按 Skill id 或名称读取 SKILL.md 正文，默认最多 16000 字符',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'skill': {'type': 'string'},
        'maxChars': {'type': 'integer', 'minimum': 512, 'maximum': 64000},
      },
      'required': ['skill'],
    },
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final key = arguments['skill']?.toString().trim() ?? '';
    if (key.isEmpty) {
      return ToolResult.failure(
          code: ToolCodes.invalidArguments, message: '缺少 skill id 或名称');
    }
    final maxChars = ((arguments['maxChars'] as num?)?.toInt() ?? 16000)
        .clamp(512, 64000)
        .toInt();
    final packs = await database.enabledSkillPacks();
    SkillPack? pack;
    for (final item in packs) {
      if (item.id == key || item.name == key) {
        pack = item;
        break;
      }
    }
    if (pack == null) {
      return ToolResult.failure(
          code: ToolCodes.notFound, message: 'Skill 不存在：$key');
    }
    final store = SkillStore();
    if (store.isFrozen(pack)) {
      return ToolResult.failure(
        code: ToolCodes.nextTurnRequired,
        message: 'Skill 安装状态无法确认，本轮冻结读取；请在下一轮重新安装或更新后再试',
      );
    }
    final body = store.readBody(pack, maxChars: maxChars);
    if (body == null) {
      return ToolResult.failure(
          code: ToolCodes.notFound, message: 'Skill 正文不存在或无法读取：$key');
    }
    return ToolResult.text(body,
        extra: {'skill': pack.id, 'name': pack.name, 'maxChars': maxChars});
  }
}

class SkillsReadResourceTool implements AgentTool {
  SkillsReadResourceTool({required this.database});
  final AppDatabase database;

  @override
  final manifest = const UnifiedTool(
    name: 'skills_read_resource',
    description: '读取已安装 Skill 目录中的白名单资源文件',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'skill': {'type': 'string'},
        'path': {'type': 'string'},
        'maxChars': {'type': 'integer', 'minimum': 512, 'maximum': 64000},
      },
      'required': ['skill', 'path'],
    },
    risk: ToolRisk.safe,
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final key = arguments['skill']?.toString().trim() ?? '';
    final path = arguments['path']?.toString().trim() ?? '';
    if (key.isEmpty || path.isEmpty) {
      return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: '缺少 skill 或 resource path');
    }
    final normalizedPath = p.normalize(path.replaceAll('\\', p.separator));
    if (p.isAbsolute(normalizedPath) ||
        normalizedPath == '.' ||
        normalizedPath.split(p.separator).contains('..')) {
      return ToolResult.failure(
        code: ToolCodes.sandboxViolation,
        message: 'Skill 资源路径越出安装目录，本次未读取',
      );
    }
    final maxChars = ((arguments['maxChars'] as num?)?.toInt() ?? 16000)
        .clamp(512, 64000)
        .toInt();
    final packs = await database.enabledSkillPacks();
    SkillPack? pack;
    for (final item in packs) {
      if (item.id == key || item.name == key) {
        pack = item;
        break;
      }
    }
    if (pack == null) {
      return ToolResult.failure(
          code: ToolCodes.notFound, message: 'Skill 不存在：$key');
    }
    final store = SkillStore();
    if (store.isFrozen(pack)) {
      return ToolResult.failure(
        code: ToolCodes.nextTurnRequired,
        message: 'Skill 安装状态无法确认，本轮冻结读取；请在下一轮重新安装或更新后再试',
      );
    }
    final body = store.readResource(pack, normalizedPath, maxChars: maxChars);
    if (body == null) {
      return ToolResult.failure(
          code: ToolCodes.notFound, message: 'Skill 资源不存在或路径非法：$path');
    }
    return ToolResult.text(body, extra: {
      'skill': pack.id,
      'path': normalizedPath,
      'maxChars': maxChars
    });
  }
}
