import 'package:flutter/material.dart';

import '../motion/motion_preferences.dart';
import '../motion/motion_tier.dart';
import '../theme/app_appearance_controller.dart';
import '../widgets/liquid_glass.dart';
import 'settings_components.dart';

/// 由 `build-apk.bat` 通过 `--dart-define` 注入；手动 `flutter build` 时为空。
const String _buildSha = String.fromEnvironment('NEXUS_BUILD_SHA');
const String _buildTime = String.fromEnvironment('NEXUS_BUILD_TIME');

/// 动效诊断：只读展示当前是哪一个开关在影响动效，以及装的是哪一次构建。
class MotionDiagnosticsCard extends StatelessWidget {
  const MotionDiagnosticsCard({super.key});

  static String get buildStamp => _buildSha.isEmpty
      ? '未注入（不是用一键构建脚本打的包）'
      : _buildTime.isEmpty
          ? _buildSha
          : '$_buildSha · $_buildTime';

  /// 结论文案：按优先级给出第一个生效的限制。
  @visibleForTesting
  static String verdict({
    required bool systemDisabled,
    required MotionLevel level,
    required MotionTier? tier,
    required bool glassCapped,
  }) {
    if (systemDisabled) {
      return '系统已关闭动画（开发者选项动画缩放为 0、省电模式或「移除动画」），全部动效已关闭';
    }
    if (level == MotionLevel.off) return 'App 内选择了「关闭动效」';
    if (level == MotionLevel.reduced) return 'App 内选择了「减弱动效」，装饰动效已关闭';
    if (tier == MotionTier.low) {
      return glassCapped
          ? '玻璃材质为纯扁平，装饰动效（光晕、粒子、视差、光感）已关闭'
          : '设备档位为 low，装饰动效（光晕、粒子、视差、光感）已关闭';
    }
    return '动效全部生效';
  }

  @override
  Widget build(BuildContext context) {
    final systemDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final level = MotionPreferences.levelOf(context);
    final tier = MotionTierScope.maybeOf(context);
    final controller = MotionTierController.app;
    final glassCapped =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;
    final rows = <(String, String)>[
      ('构建', buildStamp),
      ('系统移除动画', systemDisabled ? '是' : '否'),
      ('App 动效设置', AppAppearanceController.effects.value),
      ('生效等级', level.name),
      (
        '设备档位',
        '${tier?.name ?? '无'}（运行时 ${controller.value.name}，'
            '${controller.refreshRate.round()}Hz）'
      ),
      ('玻璃限档', glassCapped ? '是（纯扁平）' : '否'),
    ];
    final theme = Theme.of(context);
    final labelStyle =
        theme.textTheme.bodySmall?.copyWith(color: settingsMutedColor(context));
    final valueStyle = theme.textTheme.bodySmall;
    return SettingsGroupCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            verdict(
              systemDisabled: systemDisabled,
              level: level,
              tier: tier,
              glassCapped: glassCapped,
            ),
            key: const ValueKey('motion-diagnostics-verdict'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 96, child: Text(label, style: labelStyle)),
                Expanded(child: SelectableText(value, style: valueStyle)),
              ],
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}
