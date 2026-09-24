import 'package:flutter/widgets.dart';
import '../motion/motion_preferences.dart';
import 'app_appearance_controller.dart';

/// Above the Navigator so already-open routes and dialogs see preference changes.
class AppPresentationPreferences extends StatelessWidget {
  const AppPresentationPreferences({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: AppAppearanceController.effects,
    builder: (context, effects, child) => ValueListenableBuilder<double>(
      valueListenable: AppAppearanceController.fontScale,
      builder: (context, fontScale, child) {
        final media = MediaQuery.of(context);
        final level = MotionPreferences.parse(effects);
        return NexusMotionScope(level: level, child: MediaQuery(
          data: media.copyWith(
            disableAnimations: media.disableAnimations || level == MotionLevel.off,
            textScaler: AppTextScaler(media.textScaler, fontScale),
          ),
          child: child!,
        ));
      },
      child: child,
    ),
    child: child,
  );
}

/// Preserve the platform's non-linear scaling curve instead of sampling at 1sp.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.multiplier) : assert(multiplier > 0);
  final TextScaler system;
  final double multiplier;
  @override
  double scale(double fontSize) => system.scale(fontSize) * multiplier;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) => other is AppTextScaler &&
      other.system == system && other.multiplier == multiplier;
  @override
  int get hashCode => Object.hash(system, multiplier);
}
