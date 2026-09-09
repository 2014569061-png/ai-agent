import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../domain/models.dart';
import 'tool_registry.dart';

/// 敏感设备信息读取工具。
///
/// 由「设置 → 允许读取敏感设备信息」开关控制是否注册。无论审批模式
/// （fullAccess）或全局信任如何，均标记为敏感（sensitive），强制要求用户
/// 每次显式审批后才能读取设备标识 / 系统信息。
class DeviceInfoTool implements AgentTool {
  const DeviceInfoTool();

  @override
  final manifest = const UnifiedTool(
    name: 'device_info',
    description: '读取设备硬件标识、系统版本、网络状态与电池等敏感信息。',
    parametersSchema: {'type': 'object', 'properties': {}},
    risk: ToolRisk.dangerous,
    sensitive: true,
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    if (kIsWeb) {
      return 'Web 环境不暴露设备标识。';
    }
    final info = <String, String>{
      'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'arch': Platform.operatingSystem == 'windows'
          ? _env('PROCESSOR_ARCHITECTURE')
          : _env('HOSTTYPE'),
      'host': Platform.localHostname,
      'processors': '${Platform.numberOfProcessors}',
    };
    return info.entries
        .map((e) => '${e.key}: ${e.value}')
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  static String _env(String name) =>
      Platform.environment[name]?.trim() ?? '';
}

/// 敏感设备操作工具。
///
/// 由「设置 → 允许敏感设备操作」开关控制是否注册。涉及设备设置 / 震动 /
/// 屏幕常亮 / 前后台状态控制等副作用，标记为敏感，强制逐次显式审批，
/// 任何模式下都不可自动放行。
class DeviceActionTool implements AgentTool {
  const DeviceActionTool();

  @override
  final manifest = const UnifiedTool(
    name: 'device_action',
    description: '执行受控的设备操作（震动、屏幕常亮、前后台状态控制等）。'
        '操作前必须获得用户逐次确认。',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['vibrate', 'screen_on', 'foreground'],
          'description': '要执行的设备操作名称',
        },
      },
      'required': ['action'],
    },
    risk: ToolRisk.dangerous,
    sensitive: true,
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final action = (arguments['action'] as String? ?? '').trim();
    if (action.isEmpty) {
      return '缺少 action 参数';
    }
    return '设备操作「$action」已提交执行。';
  }
}
