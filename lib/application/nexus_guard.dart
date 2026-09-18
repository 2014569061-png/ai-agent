import 'dart:async';

import 'package:flutter/foundation.dart';

import '../infrastructure/observability/sentry_service.dart';

/// 静默失败的分层策略。
///
/// 项目里存在大量 `catch (_) {}`。其中一部分是**有意的降级**（例如「任务登记
/// 失败不阻断执行」），一部分是**真正的错误吞没**。两者在代码上无法区分，
/// 于是辅助链路失效时既没有日志也没有遥测，失败与成功在数据上不可区分。
///
/// [NexusGuard] 的作用是：**保留原有控制流，只补可观测性**。它不改变业务
/// 行为（该吞的仍然吞），但让「有意的降级」与「意外失败」在日志和遥测里
/// 可区分、可统计。
///
/// 三类处置：
/// - [silently]：真正可忽略。保留吞掉语义，仅按需上报，不写库。
/// - [degrade]：可降级。写一条结构化 warning，记录分类与 error type。
/// - [report]：影响用户。写 error 并上报，由调用方决定是否改变状态。
///
/// 安全约束：detail 只允许记录 error type、phase、runId 等**安全字段**。
/// 不要传 prompt、文件路径、命令、API key 或完整异常文本——这些内容会经由
/// 诊断日志导出，属于敏感面。
abstract final class NexusGuard {
  /// 上限：单次会话内同类降级只记一条 warning，避免噪声淹没真正的问题。
  static final Set<String> _reportedKeys = <String>{};

  /// 仅供测试重置去重状态。
  @visibleForTesting
  static void resetReportedKeys() => _reportedKeys.clear();

  /// 真正可忽略的失败：保留原控制流，不写诊断日志。
  ///
  /// 适用于「失败不影响任何用户可见行为」的场景（如预取、可选缓存）。
  /// 仍会转发给 Sentry（若用户已授权崩溃上报），以便统计发生率。
  static T? silently<T>(
    String phase,
    T Function() action, {
    Map<String, dynamic>? detail,
  }) {
    try {
      return action();
    } catch (error, stackTrace) {
      unawaited(SentryService.reportException(error, stackTrace));
      return null;
    }
  }

  /// 异步版 [silently]。
  static Future<T?> silentlyAsync<T>(
    String phase,
    Future<T> Function() action, {
    Map<String, dynamic>? detail,
  }) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      unawaited(SentryService.reportException(error, stackTrace));
      return null;
    }
  }

  /// 可降级的失败：写一条结构化 warning，然后继续。
  ///
  /// [phase] 是稳定的分类标识（不要拼接动态内容），[logger] 用于注入
  /// `LogService.warning`，避免本文件依赖 application 层的具体实现。
  static T? degrade<T>(
    String phase,
    T Function() action, {
    required void Function(String message, {Map<String, dynamic>? detail})
        logger,
    String? runId,
    Map<String, dynamic>? detail,
  }) {
    try {
      return action();
    } catch (error, stackTrace) {
      _logDegrade(phase, error, stackTrace, logger: logger, runId: runId, detail: detail);
      return null;
    }
  }

  /// 异步版 [degrade]。
  static Future<T?> degradeAsync<T>(
    String phase,
    Future<T> Function() action, {
    required void Function(String message, {Map<String, dynamic>? detail})
        logger,
    String? runId,
    Map<String, dynamic>? detail,
  }) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      _logDegrade(phase, error, stackTrace, logger: logger, runId: runId, detail: detail);
      return null;
    }
  }

  /// 影响用户的失败：写 error 并上报，随后**重新抛出**。
  ///
  /// 调用方拿到异常后负责设置 error state 或显示提示。
  /// 若调用方确实需要「记录但不抛」，用 [degrade]。
  static T report<T>(
    String phase,
    T Function() action, {
    required void Function(
      String message, {
      Object? error,
      StackTrace? stackTrace,
      String? runId,
      Map<String, dynamic>? detail,
    }) logger,
    String? runId,
    Map<String, dynamic>? detail,
  }) {
    try {
      return action();
    } catch (error, stackTrace) {
      logger(
        '操作失败：$phase',
        error: error,
        stackTrace: stackTrace,
        runId: runId,
        detail: _safeDetail(phase, error, runId, detail),
      );
      rethrow;
    }
  }

  static void _logDegrade(
    String phase,
    Object error,
    StackTrace stackTrace, {
    required void Function(String message, {Map<String, dynamic>? detail})
        logger,
    String? runId,
    Map<String, dynamic>? detail,
  }) {
    // 同一 phase 只记一次：降级通常是幂等的重复失败，全记会淹没诊断日志。
    if (!_reportedKeys.add('$phase|${error.runtimeType}')) return;
    logger(
      '已降级：$phase',
      detail: _safeDetail(phase, error, runId, detail),
    );
  }

  /// 只保留安全字段。**不要**把异常文本整体写入——它可能包含 prompt、
  /// 路径、命令或 API key。
  static Map<String, dynamic> _safeDetail(
    String phase,
    Object error,
    String? runId,
    Map<String, dynamic>? detail,
  ) {
    return <String, dynamic>{
      'phase': phase,
      'errorType': error.runtimeType.toString(),
      'stackTop': _safeStackTop(error),
      if (runId != null) 'runId': runId,
      ...?detail,
    };
  }

  /// 堆栈只保留首个非 NexusGuard 帧的位置，用于定位而不泄露内容。
  static String? _safeStackTop(Object error) {
    if (error is! Error) return null;
    final line = error.stackTrace?.toString().split('\n').firstOrNull;
    if (line == null || line.length > 200) return null;
    return line.trim();
  }
}
