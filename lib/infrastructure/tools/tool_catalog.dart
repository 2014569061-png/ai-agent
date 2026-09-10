import '../../domain/models.dart';

/// 工具声明的运行时条件。
///
/// 目录只负责“模型能看到什么”，不负责真正执行；执行时仍由
/// [ToolRegistry] 再次检查并返回结构化错误。
class ToolRequirement {
  const ToolRequirement({
    this.requiresRoot = false,
    this.permissions = const <String>{},
    this.platforms = const <String>{},
  });

  final bool requiresRoot;
  final Set<String> permissions;
  final Set<String> platforms;
}

class ToolCapabilitySnapshot {
  const ToolCapabilitySnapshot({
    this.hasRoot = false,
    this.grantedPermissions = const <String>{},
    this.platform = 'android',
    this.linuxAvailable = false,
  });

  final bool hasRoot;
  final Set<String> grantedPermissions;
  final String platform;
  final bool linuxAvailable;
}

/// 纯 schema 目录，可按回合复制、投影和冻结。
class ToolCatalog {
  ToolCatalog({
    Map<String, UnifiedTool>? manifests,
    Map<String, ToolRequirement>? requirements,
  })  : _manifests = manifests?.map(
              (key, value) => MapEntry(key, value.copyWith()),
            ) ??
            {},
        _requirements = {...?requirements};

  final Map<String, UnifiedTool> _manifests;
  final Map<String, ToolRequirement> _requirements;

  void register(UnifiedTool manifest,
      {ToolRequirement requirement = const ToolRequirement()}) {
    _manifests[manifest.name] = manifest.copyWith();
    _requirements[manifest.name] = requirement;
  }

  void remove(String name) {
    _manifests.remove(name);
    _requirements.remove(name);
  }

  UnifiedTool? find(String name) => _manifests[name]?.copyWith();

  ToolRequirement requirementFor(String name) =>
      _requirements[name] ?? const ToolRequirement();

  List<UnifiedTool> get manifests => List<UnifiedTool>.unmodifiable(
      _manifests.values.map((manifest) => manifest.copyWith()));

  ToolCatalog copy() => ToolCatalog(
        manifests: _manifests,
        requirements: _requirements,
      );

  /// 根据本轮设备快照生成模型可见目录。
  ///
  /// Root、权限和平台条件均在这里收窄；未登记需求的工具默认
  /// 视为无额外条件，避免历史内置工具在升级后突然消失。
  ToolCatalog project(ToolCapabilitySnapshot snapshot) {
    final result = ToolCatalog();
    for (final entry in _manifests.entries) {
      final requirement = requirementFor(entry.key);
      if (requirement.requiresRoot && !snapshot.hasRoot) continue;
      if (requirement.platforms.isNotEmpty &&
          !requirement.platforms.contains(snapshot.platform)) {
        continue;
      }
      if (!snapshot.grantedPermissions.containsAll(requirement.permissions)) {
        continue;
      }
      if (entry.key == 'terminal' && !snapshot.linuxAvailable) continue;
      result.register(_projectManifest(entry.value, snapshot),
          requirement: requirement);
    }
    return result;
  }

  UnifiedTool _projectManifest(
      UnifiedTool manifest, ToolCapabilitySnapshot snapshot) {
    final schema = deepCopyJsonMap(manifest.parametersSchema);
    final properties = schema['properties'];
    if (properties is Map) {
      final copiedProperties = Map<String, dynamic>.fromEntries(
        properties.entries.map((entry) => MapEntry(
              entry.key.toString(),
              deepCopyJsonValue(entry.value),
            )),
      );
      final identity = copiedProperties['identity'];
      if (!snapshot.hasRoot && identity is Map) {
        final identitySchema = Map<String, dynamic>.from(identity);
        final enumValues = identitySchema['enum'];
        if (enumValues is List && enumValues.contains('root')) {
          identitySchema['enum'] = enumValues
              .where((value) => value.toString() != 'root')
              .toList(growable: true);
          copiedProperties['identity'] = identitySchema;
        }
      }
      schema['properties'] = copiedProperties;
    }
    var description = manifest.description;
    if (manifest.name == 'terminal' && !snapshot.linuxAvailable) {
      description = '$description 当前设备没有可用 Linux Runtime。';
    }
    return manifest.copyWith(
        description: description, parametersSchema: schema);
  }
}
