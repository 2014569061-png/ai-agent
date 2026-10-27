import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// 本机能力（插件通道 / 权限 / 文件 / 网络）异常的人话化包装。
///
/// 与 [humanizeError] 的分工：后者面向模型服务调用，会推断服务状态；
/// 本类只处理「这台设备能不能做这件事」，不猜测远端服务。
///
/// 界面只使用 [summary] 或 [headline]；[detail] 保留原始异常，供折叠展示或日志。
class LocalErrorCopy {
  const LocalErrorCopy({
    required this.summary,
    required this.detail,
    required this.code,
    this.action = '操作',
  });

  /// 一句话结论，可直接显示给用户，不含技术术语。
  final String summary;

  /// 原始异常文本，仅用于可展开的技术细节。
  final String detail;

  /// 稳定标识，便于测试断言与后续埋点。
  final String code;

  /// 触发动作（如「创建任务」），用于组装 SnackBar 文案。
  final String action;

  /// SnackBar / 状态行用的一句话，形如「执行失败：当前设备没有提供该能力的通道」。
  /// 传入 [verb] 可覆盖构造时的动作名。
  String headline([String? verb]) => '${verb ?? action}失败：$summary';

  factory LocalErrorCopy.of(Object error, {String action = '操作'}) {
    final detail = _clip(error.toString());

    if (error is MissingPluginException) {
      return LocalErrorCopy(
        // 设置页副标题被右侧失败徽标挤窄，摘要必须是能单行放下的短句。
        summary: '此设备未提供该能力',
        detail: detail,
        code: 'channel_unavailable',
        action: action,
      );
    }
    if (error is PlatformException) {
      final denied = error.code.toUpperCase().contains('PERMISSION');
      return LocalErrorCopy(
        summary: denied
            ? '系统未授予所需权限，请在系统设置中允许后重试'
            : '系统拒绝了这次$action',
        detail: detail,
        code: denied ? 'permission_denied' : 'platform_error',
        action: action,
      );
    }
    if (error is TimeoutException) {
      return LocalErrorCopy(
        summary: '等待超时，可稍后重试',
        detail: detail,
        code: 'timeout',
        action: action,
      );
    }
    if (error is FileSystemException) {
      return LocalErrorCopy(
        summary: '文件读写失败，请检查存储权限与可用空间',
        detail: detail,
        code: 'filesystem',
        action: action,
      );
    }
    if (error is FormatException) {
      return LocalErrorCopy(
        summary: '返回的数据格式异常，可重试或更新到最新版本',
        detail: detail,
        code: 'format',
        action: action,
      );
    }
    final text = detail.toLowerCase();
    if (text.contains('socketexception') || text.contains('connection refused')) {
      return LocalErrorCopy(
        summary: '网络连接不可用，请检查网络后重试',
        detail: detail,
        code: 'network',
        action: action,
      );
    }
    return LocalErrorCopy(
      summary: '遇到未预期的错误，可重试；仍失败请在反馈中附上技术细节',
      detail: detail,
      code: 'unexpected',
      action: action,
    );
  }

  static String _clip(String raw) {
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 300 ? text : '${text.substring(0, 300)}…';
  }
}
