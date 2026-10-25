import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../../domain/system_connector_request.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';

/// Adapter only: approval ownership remains in AndroidDeviceTool's ledger.
class AndroidSystemEditorActions {
  static const action = 'system_editor';
  static const _channel = MethodChannel('nexus/device_control');

  static Future<List<Map<String, String>>> handlers(
      SystemConnectorId id) async {
    if (id != SystemConnectorId.calendar && id != SystemConnectorId.contacts) {
      throw const FormatException('该连接器不是系统编辑器');
    }
    final rows = await _channel.invokeListMethod<dynamic>(
        'listSystemEditorHandlers', {'kind': id.name});
    return [
      for (final row in rows ?? const [])
        if (row is Map) Map<String, String>.from(row),
    ];
  }

  static SystemConnectorRequest _request(Map<String, dynamic> args) {
    final raw = args['connectorRequest'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('需要连接器请求对象');
    }
    final request = SystemConnectorRequest.fromJson(raw);
    if (!request.requiresSystemConfirmation) {
      throw const FormatException('该操作不支持系统编辑器交接');
    }
    if (request.connector == SystemConnectorId.calendar) {
      for (final key in ['start', 'end']) {
        if (DateTime.parse(request.arguments[key] as String)
                    .microsecondsSinceEpoch %
                1000 !=
            0) {
          throw const FormatException('系统日历仅支持毫秒精度');
        }
      }
    }
    return request;
  }

  static String? validate(Map<String, dynamic> args) {
    try {
      _request(args);
      final package = args['packageName'];
      final activity = args['receiverActivity'];
      final version = args['receiverVersion'];
      if (package is! String ||
          package.length > 255 ||
          !RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')
              .hasMatch(package) ||
          activity is! String ||
          activity.length > 512 ||
          !RegExp(r'^[A-Za-z_][A-Za-z0-9_.$]*$').hasMatch(activity) ||
          version is! String ||
          !RegExp(r'^\d{1,19}$').hasMatch(version)) {
        return '请先选择真实系统编辑器及其版本';
      }
      return null;
    } on FormatException catch (error) {
      return error.message.toString();
    }
  }

  static Map<String, dynamic> preview(Map<String, dynamic> args) {
    final request = _request(args);
    return {
      'preview': true,
      'action': action,
      'target':
          '${args['packageName']}/${args['receiverActivity']}（版本 ${args['receiverVersion']}）',
      'scope': jsonEncode(request.toJson()),
      'impact': '把上列内容交给指定系统编辑器；最终是否保存、保存到哪个账号由你确认。NEXUS 不读取通讯录/日历，也不会报告保存成功。',
      'riskClass': 'requiresConfirmation',
      'executionPlan': '核对接收方组件与版本 → 请求打开系统编辑器 → 等待用户完成；不自动重试',
      'reversible': false,
      'rollback': '打开编辑器后可在系统界面取消；一旦自行保存，需在对应应用中手动处理。不能保证撤销。',
      'requiresConfirmation': true,
      'mustWaitForUser': true,
    };
  }

  static Future<ToolResult> execute(Map<String, dynamic> args) async {
    final invalid = validate(args);
    if (invalid != null) {
      return ToolResult.failure(
          code: ToolCodes.invalidArguments, message: invalid);
    }
    final request = _request(args);
    final fields = Map<String, dynamic>.from(request.arguments);
    if (request.connector == SystemConnectorId.calendar) {
      for (final key in ['start', 'end']) {
        fields['${key}Millis'] =
            DateTime.parse(fields.remove(key) as String).millisecondsSinceEpoch;
      }
    }
    try {
      final response =
          await _channel.invokeMapMethod<String, dynamic>('openSystemEditor', {
        'kind': request.connector.name,
        'fields': fields,
        'packageName': args['packageName'],
        'activityName': args['receiverActivity'],
        'receiverVersion': args['receiverVersion'],
        'deadlineMs': DateTime.now()
            .add(const Duration(seconds: 5))
            .millisecondsSinceEpoch,
      }).timeout(const Duration(seconds: 10));
      if (response?['handoffRequested'] != true ||
          response?['businessCompleted'] != false) {
        return ToolResult.failure(
            code: ToolCodes.toolError,
            message: '系统交接状态未证实，请先检查系统界面，不要自动重试',
            effect: ToolEffect.unknown);
      }
      return ToolResult.success(
        message: '已请求系统打开编辑器；请在系统界面确认，尚未核实保存',
        data: {
          'handoffRequested': true,
          'businessCompleted': false,
          'needsUserCompletion': true,
          'automaticRetryAllowed': false
        },
        effect: ToolEffect.applied,
      );
    } on MissingPluginException {
      return ToolResult.failure(
          code: ToolCodes.toolError, message: '当前安装包未包含系统编辑器接点，需要重新构建安装');
    } on PlatformException catch (error) {
      final known = const {
        'INVALID_ARGS',
        'RECEIVER_CHANGED',
        'PERMISSION_DENIED',
        'STALE_HANDOFF'
      }.contains(error.code);
      return ToolResult.failure(
          code: ToolCodes.toolError,
          message: known
              ? '接收方已变化、权限不足或交接过期；未交接，请重新选择并预览'
              : '交接状态未知，请先检查系统界面，不要自动重试',
          effect: known ? ToolEffect.none : ToolEffect.unknown);
    } on TimeoutException {
      return ToolResult.failure(
          code: ToolCodes.toolError,
          message: '交接响应超时，可能已打开编辑器，请先检查系统界面，不要自动重试',
          effect: ToolEffect.unknown);
    }
  }
}
