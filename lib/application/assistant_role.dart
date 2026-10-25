import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AssistantRoleStatus {
  const AssistantRoleStatus(
      {this.supported = false,
      this.roleAvailable = false,
      this.roleRequired = true,
      this.roleHeld = false,
      this.selected = false,
      this.active = false,
      this.ready = false,
      this.locked = false});

  factory AssistantRoleStatus.fromMap(Map<Object?, Object?> data) =>
      AssistantRoleStatus(
          supported: data['supported'] == true,
          roleRequired: data['roleRequired'] != false,
          roleAvailable: data['roleAvailable'] == true,
          roleHeld: data['roleHeld'] == true,
          selected: data['selected'] == true,
          active: data['active'] == true,
          ready: data['ready'] == true,
          locked: data['locked'] == true);

  final bool supported,
      roleRequired,
      roleAvailable,
      roleHeld,
      selected,
      active,
      ready,
      locked;
  bool get connected =>
      supported &&
      selected &&
      active &&
      ready &&
      (!roleRequired || (roleAvailable && roleHeld));
  String get label {
    if (!supported) return '此平台暂不支持系统助手';
    if (connected) return '系统助手已激活';
    if (selected || roleHeld) return '已选择，等待系统服务激活';
    return '尚未选择 NEXUS';
  }
}

abstract interface class AssistantRoleSource {
  Future<AssistantRoleStatus> status();
  Future<bool> requestRole();
  Future<bool> openSettings();
  Future<bool> showSession();
}

class PlatformAssistantRoleSource implements AssistantRoleSource {
  const PlatformAssistantRoleSource();
  static const _channel = MethodChannel('nexus/assistant_role');
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<AssistantRoleStatus> status() async {
    if (!_android) return const AssistantRoleStatus();
    final data = await _channel.invokeMapMethod<Object?, Object?>('status');
    if (data == null) throw StateError('No system assistant status');
    return AssistantRoleStatus.fromMap(data);
  }

  @override
  Future<bool> requestRole() async =>
      _android &&
      (await _channel
              .invokeMapMethod<String, Object?>('requestRole'))?['opened'] ==
          true;
  @override
  Future<bool> openSettings() async =>
      _android &&
      (await _channel
              .invokeMapMethod<String, Object?>('openSettings'))?['opened'] ==
          true;
  @override
  Future<bool> showSession() async =>
      _android &&
      (await _channel
              .invokeMapMethod<String, Object?>('showSession'))?['requested'] ==
          true;
}
