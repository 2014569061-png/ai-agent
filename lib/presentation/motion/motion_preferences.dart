import 'package:flutter/widgets.dart';

enum MotionLevel { full, reduced, off }

/// One inherited policy for the app preference, including routes and overlays.
class NexusMotionScope extends InheritedWidget {
  const NexusMotionScope({super.key, required this.level, required super.child});
  final MotionLevel level;
  @override
  bool updateShouldNotify(NexusMotionScope oldWidget) => level != oldWidget.level;
}

abstract final class MotionPreferences {
  static MotionLevel parse(String value) => switch (value) {
        'off' => MotionLevel.off,
        'reduced' => MotionLevel.reduced,
        _ => MotionLevel.full,
      };

  /// Non-listening reads are for Navigator/gesture callbacks, not widget builds.
  static MotionLevel levelOf(BuildContext context, {bool listen = true}) {
    final media = listen
        ? MediaQuery.maybeOf(context)
        : context.getInheritedWidgetOfExactType<MediaQuery>()?.data;
    if (media?.disableAnimations ?? false) return MotionLevel.off;
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<NexusMotionScope>()
        : context.getInheritedWidgetOfExactType<NexusMotionScope>();
    return scope?.level ?? MotionLevel.full;
  }

  static bool shouldReduceMotion(BuildContext context) =>
      levelOf(context) != MotionLevel.full;

  static bool animationsDisabled(BuildContext context) =>
      levelOf(context) == MotionLevel.off;

  static bool allowDecorativeMotion(BuildContext context) =>
      levelOf(context) == MotionLevel.full;

  static Duration adjustDuration(BuildContext context, Duration duration, {
    Duration reducedDuration = const Duration(milliseconds: 120),
    bool listen = true,
  }) {
    return switch (levelOf(context, listen: listen)) {
      MotionLevel.off => Duration.zero,
      MotionLevel.reduced => duration < reducedDuration ? duration : reducedDuration,
      MotionLevel.full => duration,
    };
  }
}
