import 'dart:async';

import 'package:flutter/foundation.dart';

/// 通知点击意图的种类。
///
/// payload 契约由 [NotificationService] 的调用方写入，形如
/// `conversation:<id>` / `task:<id>` / `approval:<requestId>`。
enum NotificationIntentKind {
  /// 打开某个会话。
  conversation,

  /// 打开某个任务详情。
  task,

  /// 审批提醒。裁决本身由 `handleApprovalNotificationAction` 在独立 isolate 里
  /// 写入数据库完成，这里只负责把用户带回应用。
  approval,

  /// 设备自动化触发（`automation:<fireId>`）：打开预览确认面板，用户确认后才执行。
  automation,
  reminder,
}

/// 一条「用户点了通知」的意图。
@immutable
class NotificationIntent {
  const NotificationIntent(this.kind, this.id);

  final NotificationIntentKind kind;
  final String id;

  /// 解析通知 payload，无法识别时返回 null。
  ///
  /// 通知点击是「尽力而为」的入口，收到未知 payload 只应被忽略，绝不能抛异常
  /// 打断启动路径或回调链路。
  static NotificationIntent? parse(String? payload) {
    if (payload == null) return null;
    final separator = payload.indexOf(':');
    if (separator <= 0) return null;
    final kind = switch (payload.substring(0, separator)) {
      'conversation' => NotificationIntentKind.conversation,
      'task' => NotificationIntentKind.task,
      'approval' => NotificationIntentKind.approval,
      'automation' => NotificationIntentKind.automation,
      'reminder' => NotificationIntentKind.reminder,
      _ => null,
    };
    if (kind == null) return null;
    final id = payload.substring(separator + 1);
    if (id.isEmpty ||
        id.length > 256 ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(id)) {
      return null;
    }
    return NotificationIntent(kind, id);
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationIntent && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'NotificationIntent(${kind.name}, $id)';
}

/// 通知点击意图的缓冲与分发。
///
/// 与 [SharingService] 同一套语义：冷启动时通知点击发生在 ChatPage 订阅之前，
/// broadcast stream 会丢事件，因此没有订阅者时先入缓冲，由 ChatPage 挂载后
/// `drainPending()` 消费；运行中则直接投递给订阅者实时导航。
///
/// 不在这里直接导航：点击可能发生在启动早期或任意页面之上，导航必须由持有
/// `Navigator` / Riverpod 容器的页面统一处理。
abstract final class NotificationIntentRouter {
  static final StreamController<NotificationIntent> _controller =
      StreamController<NotificationIntent>.broadcast();
  static final List<NotificationIntent> _pending = <NotificationIntent>[];
  static void Function(NotificationIntent)? _entrySink;

  /// Production binds before plugin initialization. Legacy observers remain
  /// available, but only the shared entry surface is allowed to navigate.
  static void bindEntrySink(void Function(NotificationIntent) sink) {
    _entrySink = sink;
    for (final intent in drainPending()) {
      sink(intent);
    }
  }

  static Stream<NotificationIntent> get intents => _controller.stream;

  /// 由通知回调（可能处于启动早期）投递一条意图。
  static void dispatch(NotificationIntent intent) {
    final sink = _entrySink;
    if (sink != null) {
      sink(intent);
      if (_controller.hasListener) _controller.add(intent);
      return;
    }
    if (_controller.hasListener) {
      _controller.add(intent);
    } else {
      _pending.add(intent);
    }
  }

  /// 取出并清空启动阶段缓冲的意图。
  static List<NotificationIntent> drainPending() {
    final drained = List<NotificationIntent>.of(_pending);
    _pending.clear();
    return drained;
  }

  @visibleForTesting
  static void reset() {
    _pending.clear();
    _entrySink = null;
  }
}
