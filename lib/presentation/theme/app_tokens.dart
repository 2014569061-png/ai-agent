import 'package:flutter/animation.dart';

@Deprecated('视觉规范已改为平面，该材质层级枚举已废弃')
enum ImmersiveMaterialLevel { ultraThin, thin, regular, thick, ultraThick }

abstract final class AppTokens {
  // 4px 基栅间距 Token (锁定 4 / 8 / 12 / 16 / 24 / 32 / 48 / 64)
  static const sp1 = 4.0;
  static const sp2 = 8.0;
  static const sp3 = 12.0;
  static const sp4 = 16.0;
  static const sp6 = 24.0;
  static const sp8 = 32.0;
  static const sp12 = 48.0;
  static const sp16 = 64.0;

  // 兼容历史间距别名
  @Deprecated('请改用 sp1')
  static const spacingXs = sp1;
  @Deprecated('请改用 sp2')
  static const spacingSm = sp2;
  @Deprecated('请改用 sp3')
  static const spacingMd = sp3;
  @Deprecated('请改用 sp4')
  static const spacingLg = sp4;
  @Deprecated('请改用 sp6')
  static const spacingXl = sp6;

  // 几何圆角 Token (收敛为 4 档)
  static const radiusControl = 8.0;
  static const radiusCard = 12.0;
  static const radiusModal = 16.0;
  static const radiusPill = 999.0;

  /// 首页输入区专用圆角：对标 DeepSeek 的大圆角输入框，比常规弹层更圆。
  static const radiusComposer = 24.0;

  /// 首页输入区内部控件尺寸
  static const composerChipHeight = 30.0;
  static const composerCircleButton = 30.0;

  // 兼容历史别名
  @Deprecated('请改用 radiusControl')
  static const smallControlRadius = radiusControl;
  @Deprecated('请改用 radiusPill')
  static const radiusCapsule = radiusPill;
  @Deprecated('请改用 radiusPill')
  static const capsuleRadius = radiusPill;
  @Deprecated('请改用 radiusCard')
  static const cardRadius = radiusCard;
  @Deprecated('请改用 radiusModal')
  static const modalRadius = radiusModal;
  @Deprecated('气泡已采用 16 16 8 16 圆角，无需此常量')
  static const radiusBubble = 16.0;
  @Deprecated('已删除尖角尾巴')
  static const radiusBubbleTail = 4.0;

  // 结构高度常量
  static const kTopBarHeight = 56.0;
  static const kListRowHeight = 52.0;
  static const kControlHeight = 44.0;
  static const kChipHeight = 32.0;
  static const kSearchBoxHeight = 36.0;
  @Deprecated('请改用 kTopBarHeight')
  static const kCapsuleTopBarHeight = kTopBarHeight;

  // 动效时长 Token (90 / 150 / 220 / 300ms)
  static const Duration durationInstant = Duration(milliseconds: 90);
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationBase = Duration(milliseconds: 220);
  static const Duration durationExpand = Duration(milliseconds: 300);
  @Deprecated('请改用 durationExpand (300ms)')
  static const Duration durationModal = Duration(milliseconds: 300);
  @Deprecated('请改用 durationExpand (300ms)')
  static const Duration durationSlow = Duration(milliseconds: 300);

  // 动效曲线 Token (统一 Curves.easeOutCubic)
  static const Curve curveStandard = Curves.easeOutCubic;
  @Deprecated('回弹曲线已废弃，统一为 easeOutCubic')
  static const Curve curveEnter = Curves.easeOutCubic;
  @Deprecated('统一为 easeOutCubic')
  static const Curve curveExpand = Curves.easeOutCubic;
  @Deprecated('统一为 easeOutCubic')
  static const Curve curveDecelerate = Curves.easeOutCubic;
}
