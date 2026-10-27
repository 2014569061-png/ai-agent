import 'package:flutter/material.dart';
import '../theme/app_status_colors.dart';
import '../motion/micro_interactions.dart';
import '../theme/mobile_theme.dart';
import 'nexus_status_pill.dart';

/// 状态徽章语义色调
enum NexusBadgeTone {
  neutral,
  brand,
  success,
  warning,
  danger,
}

/// 小型语义状态徽章（用于卡片、列表项、服务连接状态）
class NexusStatusBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final NexusBadgeTone tone;
  final bool showDot;
  final VoidCallback? onTap;

  const NexusStatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = NexusBadgeTone.neutral,
    this.showDot = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 外观全部来自 NexusStatusPillShell：徽标外壳、圆角、描边与文字规格
    // 只在一个文件里定义，这里只保留动画、提示与点击区域。
    Widget content = NexusStatusPillShell(
      label: label,
      tone: switch (tone) {
        NexusBadgeTone.neutral => AppStatusTone.neutral,
        NexusBadgeTone.brand => AppStatusTone.brand,
        NexusBadgeTone.success => AppStatusTone.success,
        NexusBadgeTone.warning => AppStatusTone.warning,
        NexusBadgeTone.danger => AppStatusTone.danger,
      },
      icon: icon,
      showDot: showDot,
      isCompact: true,
    );

    content = PopOnChange(trigger: (label, tone), child: content);
    content =
        Tooltip(message: label, excludeFromSemantics: true, child: content);
    if (onTap != null) {
      return Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(MobileTheme.controlRadius(context)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Center(widthFactor: 1, heightFactor: 1, child: content),
            ),
          ));
    }
    return content;
  }
}
