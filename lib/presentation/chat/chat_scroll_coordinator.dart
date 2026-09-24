import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models.dart';
import '../motion/nexus_motion.dart';

/// Owns tail-following and unread state for one visible conversation.
/// A missing/unlaid-out list is not evidence that the user scrolled away.
class ChatScrollCoordinator extends ChangeNotifier {
  ChatScrollCoordinator(this.controller,
      {required this.isRunning, this.adjustDuration}) {
    controller.addListener(_onScroll);
  }

  final ScrollController controller;
  final bool Function() isRunning;

  /// Resolve at the moment of scrolling, including queued post-frame work.
  final Duration Function(Duration)? adjustDuration;

  void _scrollTo(double target, Duration base) {
    final duration = adjustDuration?.call(base) ?? base;
    if (duration == Duration.zero) {
      controller.jumpTo(target);
    } else {
      controller.animateTo(target,
          duration: duration, curve: NexusMotion.curveScroll);
    }
  }

  static const _nearBottomDistance = 120.0;
  bool showScrollToBottom = false;
  int unreadCount = 0;
  bool _userDragging = false;
  bool _scheduled = false;
  bool _animate = false;
  bool _disposed = false;
  int _epoch = 0;
  int _userScrollRevision = 0;

  bool get isNearBottom =>
      !controller.hasClients ||
      !controller.position.hasContentDimensions ||
      controller.position.extentAfter <= _nearBottomDistance;

  void _setIndicator(bool show, int count) {
    if (_disposed || (showScrollToBottom == show && unreadCount == count)) {
      return;
    }
    showScrollToBottom = show;
    unreadCount = count;
    notifyListeners();
  }

  void _onScroll() {
    if (!controller.hasClients) return;
    final near = isNearBottom;
    _setIndicator(!near, near ? 0 : unreadCount);
  }

  bool handleNotification(Notification notification) {
    if (notification is ScrollMetricsNotification &&
        notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical) {
      // First layout and viewport resizing need not produce a scroll event.
      _onScroll();
    } else if (notification is ScrollNotification &&
        notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical) {
      if (notification is ScrollStartNotification) {
        _userDragging = notification.dragDetails != null;
        if (_userDragging) _userScrollRevision++;
      } else if (notification is ScrollUpdateNotification) {
        if (notification.dragDetails != null) {
          _userDragging = true;
          _userScrollRevision++;
        }
      } else if (notification is ScrollEndNotification) {
        _userDragging = false;
      }
    }
    return false;
  }

  void reset() {
    _epoch++;
    _scheduled = false;
    _animate = false;
    _userDragging = false;
    _setIndicator(false, 0);
    _scheduleFollowTail(animate: false, force: true);
  }

  void messagesChanged({
    required List<ChatMessage> previous,
    required List<ChatMessage> next,
    required bool resetSession,
    required bool running,
    required bool completed,
  }) {
    if (resetSession || next.isEmpty) {
      reset();
      return;
    }
    final added = appendedCount(previous, next);
    if (!isNearBottom && added > 0) {
      _setIndicator(true, unreadCount + added);
    }
    if (running || added > 0 || completed) {
      _scheduleFollowTail(animate: (added > 0 || completed) && !running);
    }
  }

  /// Prepending a history page or replacing a range is not a live append.
  static int appendedCount(List<ChatMessage> previous, List<ChatMessage> next) {
    final delta = next.length - previous.length;
    if (delta <= 0) return 0;
    if (previous.isEmpty) return delta;
    final oldTail = previous.last;
    final retainedTail = next[previous.length - 1];
    final retained = oldTail.id != null
        ? oldTail.id == retainedTail.id
        : identical(oldTail, retainedTail);
    return retained ? delta : 0;
  }

  void scrollToBottom() {
    HapticFeedback.lightImpact();
    _setIndicator(false, 0);
    if (!controller.hasClients) return;
    _scrollTo(controller.position.maxScrollExtent, NexusMotion.scrollToTarget);
  }

  void _scheduleFollowTail({required bool animate, bool force = false}) {
    if (_userDragging || (!force && !isNearBottom)) return;
    _animate = _animate || animate;
    if (_scheduled) return;
    _scheduled = true;
    final epoch = _epoch;
    final userScrollRevision = _userScrollRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || epoch != _epoch) return;
      _scheduled = false;
      final animateNow = _animate && !isRunning();
      _animate = false;
      if (!controller.hasClients ||
          _userDragging ||
          userScrollRevision != _userScrollRevision) {
        return;
      }
      // Follow the pre-layout tail. A newly appended large bubble may have
      // increased extentAfter; that is not a user scroll away from the tail.
      final target = controller.position.maxScrollExtent;
      if ((target - controller.position.pixels).abs() < 2) {
        _onScroll();
        return;
      }
      if (animateNow) {
        _scrollTo(target, NexusMotion.tailFollow);
      } else {
        controller.jumpTo(target);
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_onScroll);
    super.dispose();
  }
}
