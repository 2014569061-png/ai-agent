import 'package:flutter/animation.dart';

enum ImmersiveMaterialLevel { ultraThin, thin, regular, thick, ultraThick }

abstract final class AppTokens {
  static const spacingXs = 4.0;
  static const spacingSm = 8.0;
  static const spacingMd = 12.0;
  static const spacingLg = 16.0;
  static const spacingXl = 24.0;

  // 几何圆角 Token
  static const radiusControl = 14.0;
  static const radiusCapsule = 24.0;
  static const radiusCard = 20.0;
  static const radiusModal = 20.0;
  static const radiusBubble = 16.0;
  static const radiusBubbleTail = 4.0;

  // 兼容历史别名
  static const smallControlRadius = radiusControl;
  static const capsuleRadius = radiusCapsule;
  static const cardRadius = radiusCard;
  static const modalRadius = radiusModal;

  // 顶栏高度常量
  static const kCapsuleTopBarHeight = 56.0;

  static double blurSigma(ImmersiveMaterialLevel level) => switch (level) {
        ImmersiveMaterialLevel.ultraThin => 8,
        ImmersiveMaterialLevel.thin => 12,
        ImmersiveMaterialLevel.regular => 16,
        ImmersiveMaterialLevel.thick => 22,
        ImmersiveMaterialLevel.ultraThick => 30,
      };

  static double surfaceOpacity(ImmersiveMaterialLevel level, bool isDark) =>
      switch (level) {
        ImmersiveMaterialLevel.ultraThin => isDark ? .12 : .15,
        ImmersiveMaterialLevel.thin => isDark ? .20 : .25,
        ImmersiveMaterialLevel.regular => isDark ? .30 : .35,
        ImmersiveMaterialLevel.thick => isDark ? .46 : .50,
        ImmersiveMaterialLevel.ultraThick => isDark ? .60 : .65,
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
