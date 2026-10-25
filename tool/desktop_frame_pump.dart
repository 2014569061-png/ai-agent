import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'frame_timing_window.dart';

/// Always waits for a newly requested frame, including when called from a
/// previous frame's post-frame callback. endOfFrame may refer to that old frame.
Future<DesktopFrameBoundary> nextRenderedFrame() {
  final complete = Completer<DesktopFrameBoundary>();
  SchedulerBinding.instance.scheduleFrameCallback((_) {
    final frameNumber =
        SchedulerBinding.instance.platformDispatcher.frameData.frameNumber;
    final timestamp =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
    SchedulerBinding.instance.addPostFrameCallback(
        (_) => complete.complete(DesktopFrameBoundary(frameNumber, timestamp)));
  });
  return complete.future.timeout(const Duration(seconds: 5));
}
