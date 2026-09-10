import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/tools/tool_catalog.dart';

void main() {
  const manifest = UnifiedTool(
    name: 'identity_tool',
    description: '测试工具',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'identity': {
          'type': 'string',
          'enum': ['app', 'root'],
        },
      },
    },
    risk: ToolRisk.safe,
  );

  test('project returns isolated schema copies and narrows root enum', () {
    final catalog = ToolCatalog()..register(manifest);
    final projected = catalog.project(const ToolCapabilitySnapshot());
    final first = projected.find('identity_tool')!;
    final enumValues = ((first.parametersSchema['properties']
        as Map)['identity'] as Map)['enum'] as List;
    expect(enumValues, ['app']);

    enumValues.add('mutated');
    final original = catalog.find('identity_tool')!;
    final originalEnum = ((original.parametersSchema['properties']
        as Map)['identity'] as Map)['enum'] as List;
    expect(originalEnum, ['app', 'root']);

    final second =
        catalog.project(const ToolCapabilitySnapshot()).find('identity_tool')!;
    final secondEnum = ((second.parametersSchema['properties']
        as Map)['identity'] as Map)['enum'] as List;
    expect(secondEnum, ['app']);
  });

  test('project filters platform requirements and empty catalog stays empty',
      () {
    final catalog = ToolCatalog()
      ..register(
        manifest,
        requirement: const ToolRequirement(platforms: {'android'}),
      );
    expect(
      catalog
          .project(const ToolCapabilitySnapshot(platform: 'android'))
          .manifests,
      hasLength(1),
    );
    expect(
      catalog.project(const ToolCapabilitySnapshot(platform: 'ios')).manifests,
      isEmpty,
    );
    expect(ToolCatalog().project(const ToolCapabilitySnapshot()).manifests,
        isEmpty);
  });
}
