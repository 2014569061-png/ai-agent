import 'package:flutter/animation.dart';

enum ImmersiveMaterialLevel { ultraThin, thin, regular, thick, ultraThick }

abstract final class AppTokens {
  static const spacingXs = 4.0;
  static const spacingSm = 8.0;
  static const spacingMd = 12.0;
  static const spacingLg = 16.0;
  static const spacingXl = 24.0;

  static const smallControlRadius = 14.0;
  static const capsuleRadius = 24.0;
  static const cardRadius = 20.0;
  static const modalRadius = 30.0;

  static double blurSigma(ImmersiveMaterialLevel level) => switch (level) {
        ImmersiveMaterialLevel.ultraThin => 8,
        ImmersiveMaterialLevel.thin => 12,
        ImmersiveMaterialLevel.regular => 16,
        ImmersiveMaterialLevel.thick => 22,
        ImmersiveMaterialLevel.ultraThick => 30,
      };

  static double surfaceOpacity(ImmersiveMaterialLevel level, bool isDark) =>
      switch (level) {
        ImmersiveMaterialLevel.ultraThin => isDark ? .20 : .35,
        ImmersiveMaterialLevel.thin => isDark ? .35 : .45,
        ImmersiveMaterialLevel.regular => isDark ? .50 : .60,
        ImmersiveMaterialLevel.thick => isDark ? .65 : .75,
        ImmersiveMaterialLevel.ultraThick => isDark ? .80 : .85,
      };

  // 动画时长 token
  static const Duration durationInstant = Duration(milliseconds: 90);
  static const Duration durationFast = Duration(milliseconds: 160);
  static const Duration durationBase = Duration(milliseconds: 220);
  static const Duration durationExpand = Duration(milliseconds: 300);
  static const Duration durationModal = Duration(milliseconds: 320);
  static const Duration durationSlow = Duration(milliseconds: 420);

  // 动效曲线 token
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEnter = Curves.easeOutBack;
  static const Curve curveExpand = Curves.easeInOutCubic;
  static const Curve curveDecelerate = Curves.decelerate;
}
