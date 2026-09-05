import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 沉浸光感动效等级：full / reduced / off。
///
/// full：启用实时模糊与完整动效。
/// reduced：关闭实时模糊、缩短动画。
/// off：关闭模糊、阴影与动画，走最省资源的平面表现。
enum ImmersiveEffectMode { full, reduced, off }

/// 根据系统「减少动效」开关、平台和可选的应用级设置，决定当前的动效等级。
/// 纯函数式助手，便于各沉浸组件在 build 时同步判断降级路径；
/// 不作为 InheritedWidget，读取系统开关即可满足全局降级需求。
abstract final class ImmersiveEffectsController {
  static const kPlatformTablet = !kIsWeb;
  static const _lowPowerPlatforms = {
    TargetPlatform.android,
    TargetPlatform.iOS
  };

  /// 由调用方传入的当前 BuilderContext。可选 [override] 用于在设置里强制指定等级，
  /// 例如「低性能降级」开关；为空则按系统开关 + 平台推导。
  static ImmersiveEffectMode resolve(
    BuildContext context, {
    ImmersiveEffectMode? override,
  }) {
    if (override != null) return override;
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) return ImmersiveEffectMode.reduced;

    // 桌面端默认 full；移动端平滑降级为 reduced 更稳。
    final platform = defaultTargetPlatform;
    if (!_lowPowerPlatforms.contains(platform)) {
      return ImmersiveEffectMode.full;
    }
    return ImmersiveEffectMode.reduced;
  }

  /// 是否应关闭实时 BackdropFilter 模糊。
  static bool blurEnabled(ImmersiveEffectMode mode) =>
      mode == ImmersiveEffectMode.full;

  /// 是否应保留光晕阴影。
  static bool glowEnabled(ImmersiveEffectMode mode) =>
      mode != ImmersiveEffectMode.off;

  /// 是否应播放（或缩短）动画。
  static bool animate(ImmersiveEffectMode mode) =>
      mode != ImmersiveEffectMode.off;

  /// 动画时长缩放系数，reduced 下缩短到约六成。
  static Duration scaled({
    required Duration base,
    required ImmersiveEffectMode mode,
  }) {
    if (mode == ImmersiveEffectMode.off) return Duration.zero;
    if (mode == ImmersiveEffectMode.reduced) {
      return Duration(milliseconds: (base.inMilliseconds * .6).round());
    }
    return base;
  }
}
