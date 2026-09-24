import 'package:flutter/animation.dart';

enum SurfaceLevel { ultraThin, thin, regular, thick, ultraThick }

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

  /// 首页输入区专用圆角：更克制利落的 20px（去掉软糖感）
  static const radiusComposer = 20.0;

  // 字号阶 Token（双轨制：Display 轨 + Content 轨）
  static const fontSizeDisplay1 = 34.0;
  static const fontSizeDisplay2 = 28.0;
  static const fontSizeHeadline = 22.0;
  static const fontSizeTitle = 17.0;
  static const fontSizeHeading = 18.0;
  static const fontSizeSection = 19.0;
  static const fontSizeMetric = 20.0;
  static const fontSizeBodyLarge = 16.0;
  static const fontSizeBody = 15.0;
  static const fontSizeSubhead = 14.0;
  static const fontSizeBodySmall = 13.5;
  static const fontSizeCaption = 13.0;
  static const fontSizeMeta = 12.5;
  static const fontSizeFootnote = 12.0;
  static const fontSizeSubcaption = 11.5;
  static const fontSizeBadge = 11.0;
  static const fontSizeMetricSmall = 10.5;

  /// 统一等宽字体（消除各处裸写 'monospace' 或未打包的 'JetBrains Mono'）
  static const fontFamilyMono = 'monospace';

  // 统一响应式断点常量 (P1-11)
  static const bpCompact = 320.0;
  static const bpMedium = 420.0;
  static const bpWide = 700.0;
  static const kContentMaxWidth = 700.0;

  // 微环境光遮蔽阴影 Token（Ambient Occlusion，防内容穿透）
  static const shadowFloatingBlur = 20.0;
  static const shadowFloatingOffset = Offset(0, 4);

  /// 首页输入区内部控件尺寸
  static const composerChipHeight = 30.0;
  static const composerCircleButton = 26.0;

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
  static const kMinTouchTarget = 48.0;
  static const kChipHeight = 32.0;
  static const kSearchBoxHeight = 36.0;
  @Deprecated('请改用 kTopBarHeight')
  static const kCapsuleTopBarHeight = kTopBarHeight;

  // 动效时长 Token：按交互范围分层，而不是让所有动效共享同一时长。
  // HarmonyOS 动效指南给出的可感知基准是：短动效约 150ms、局部布局约
  // 200~250ms、全屏/复杂转场不超过 350ms。
  static const _durationInstantMs = 100;
  static const _durationPageMs = 250;
  static const _durationPageSpringMs = 350;
  static const _durationPageExitMs = 180;
  static const _durationSheetMs = 300;
  static const _durationToastMs = 220;
  static const _durationImeSettleMs = 400;
  static const _durationEntranceMs = 260;
  static const _durationListItemMs = 220;
  static const _listStaggerMs = 30;
  static const _entranceStaggerMs = 40;
  static const _durationReducedEntranceMs = 120;
  static const Duration durationInstant =
      Duration(milliseconds: _durationInstantMs);
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationBase = Duration(milliseconds: 220);
  static const Duration durationExpand = Duration(milliseconds: 300);
  static const Duration durationPage = Duration(milliseconds: _durationPageMs);

  /// 整屏层级转场（上层进入）：HarmonyOS 全屏动效上限 350ms。
  static const Duration durationPageSpring =
      Duration(milliseconds: _durationPageSpringMs);
  static const Duration durationPageExit =
      Duration(milliseconds: _durationPageExitMs);
  static const Duration durationSheet =
      Duration(milliseconds: _durationSheetMs);
  static const Duration durationToast =
      Duration(milliseconds: _durationToastMs);

  /// 输入法收起动画的最长可接受时长：输入框失焦后，键盘 inset 超过这个时长
  /// 仍未归零，就视为系统残留的过期 inset（见 KeyboardInsetScope）。
  static const Duration durationImeSettle =
      Duration(milliseconds: _durationImeSettleMs);

  /// 首屏入场：单个元素时长 / 槽位错开 / 减少动效时的淡入时长。
  static const Duration durationEntrance =
      Duration(milliseconds: _durationEntranceMs);
  static const Duration entranceStagger =
      Duration(milliseconds: _entranceStaggerMs);
  static const Duration durationReducedEntrance =
      Duration(milliseconds: _durationReducedEntranceMs);

  /// 列表错开入场：单项时长 / 相邻两项错开 / 参与入场的最大项数。
  static const Duration durationListItem =
      Duration(milliseconds: _durationListItemMs);
  static const Duration listStagger = Duration(milliseconds: _listStaggerMs);
  static const int listStaggerMaxItems = 8;
  @Deprecated('请改用 durationExpand (300ms)')
  static const Duration durationModal = durationExpand;
  @Deprecated('请改用 durationExpand (300ms)')
  static const Duration durationSlow = durationExpand;

  // 动效曲线 Token：对应 HarmonyOS 的标准 / 减速 / 加速曲线。
  // 标准曲线用于同屏状态变化；减速曲线用于新元素进场；加速曲线用于退场。
  static const Curve curveStandard = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Curve curveDecelerate = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Curve curveAccelerate = Cubic(0.0, 0.0, 0.0, 1.0);
  @Deprecated('请改用 curveDecelerate')
  static const Curve curveEnter = curveDecelerate;
  @Deprecated('请改用 curveStandard')
  static const Curve curveExpand = curveStandard;
}
