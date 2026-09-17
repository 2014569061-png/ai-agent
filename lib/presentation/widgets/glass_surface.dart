import 'package:flutter/material.dart';

import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import 'liquid_glass.dart';

export 'liquid_glass.dart' show GlassIntensity;

/// The semantic role of a glass surface in the interface hierarchy.
enum GlassRole {
  navigation,
  control,
  overlay,
  prominent,
  content,
}

/// The optical treatment applied to a glass surface.
enum GlassVariant {
  /// Stable contrast for text-heavy surfaces and overlays.
  regular,

  /// More transparent treatment for visually rich backgrounds.
  clear,

  /// Brand-tinted treatment reserved for the most important action.
  prominent,
}

/// A semantic glass surface with one implementation for all callers.
///
/// The interface intentionally exposes design intent rather than shader
/// numbers. The implementation owns tint, edge, shadow, interaction and
/// accessibility behavior so pages stay consistent.
class GlassSurface extends StatefulWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.role = GlassRole.content,
    this.variant = GlassVariant.regular,
    this.intensity,
    this.borderRadius,
    this.padding,
    this.margin,
    this.outlined = true,
    this.borderWidth = 1.0,
    this.onTap,
    this.interactive = false,
    this.tint,
    this.borderColor,
    this.boxShadow,
    this.blurSigma,
    this.refraction,
    this.edgeWidth,
    this.gloss,
    this.chromaticAberration,
  });

  final Widget child;
  final GlassRole role;
  final GlassVariant variant;
  final GlassIntensity? intensity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool outlined;
  final double borderWidth;
  final VoidCallback? onTap;
  final bool interactive;
  final Color? tint;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final double? blurSigma;
  final double? refraction;
  final double? edgeWidth;
  final double? gloss;
  final double? chromaticAberration;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  late final ValueNotifier<bool> _pressed;

  @override
  void initState() {
    super.initState();
    _pressed = ValueNotifier(false);
  }

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (!widget.interactive || _pressed.value == value) return;
    // Keep the press animation out of GlassSurface.build. Rebuilding that
    // method recreates the BackdropFilter and makes every glass control pay
    // the full rasterization cost for a simple pointer-state change.
    _pressed.value = value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final highContrast = media?.highContrast ?? false;
    final intensity =
        widget.intensity ?? AppAppearanceController.resolvedGlassIntensity;
    final radius = widget.borderRadius ?? BorderRadius.circular(20);
    final useGlass = intensity != GlassIntensity.flat;
    final effectiveTint = widget.tint ??
        _defaultTint(
          isDark: isDark,
          highContrast: highContrast,
          variant: widget.variant,
        );
    final effectiveBorder = widget.borderColor ??
        (intensity == GlassIntensity.flat
            ? (isDark ? AppPalette.darkHairline : AppPalette.lightHairline)
            : _defaultBorder(isDark: isDark, highContrast: highContrast));
    final effectiveShadow = intensity == GlassIntensity.flat
        ? const <BoxShadow>[]
        : (widget.boxShadow ??
            _defaultShadow(isDark: isDark, role: widget.role));

    Widget surface;
    if (useGlass) {
      surface = LiquidGlass(
        intensity: intensity,
        borderRadius: radius,
        padding: widget.padding,
        margin: widget.margin,
        blurSigma: widget.blurSigma ?? _blurFor(widget.role),
        refraction: widget.refraction ?? _refractionFor(widget.role),
        edgeWidth: widget.edgeWidth ?? _edgeFor(widget.role),
        gloss: widget.gloss ?? _glossFor(widget.role),
        chromaticAberration:
            widget.chromaticAberration ?? _chromaticFor(widget.role),
        tint: effectiveTint,
        outlined: widget.outlined,
        borderWidth: widget.borderWidth,
        borderColor: effectiveBorder,
        boxShadow: effectiveShadow,
        child: _interactiveChild(radius, reduceMotion: reduceMotion),
      );
    } else {
      surface = Container(
        margin: widget.margin,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: isDark ? AppPalette.darkSurface : AppPalette.lightCanvas,
          borderRadius: radius,
          border: widget.outlined
              ? Border.all(
                  color: effectiveBorder,
                  width: highContrast
                      ? (widget.borderWidth < 1.2 ? 1.2 : widget.borderWidth)
                      : widget.borderWidth,
                )
              : null,
          boxShadow: effectiveShadow,
        ),
        child: _interactiveChild(radius, reduceMotion: reduceMotion),
      );
    }

    return surface;
  }

  Widget _interactiveChild(
    BorderRadius radius, {
    required bool reduceMotion,
  }) {
    Widget child = widget.child;
    if (widget.interactive) {
      child = ValueListenableBuilder<bool>(
        valueListenable: _pressed,
        child: child,
        builder: (context, pressed, child) => AnimatedScale(
          scale: reduceMotion ? 1.0 : (pressed ? 0.985 : 1.0),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        ),
      );
    }
    if (widget.onTap != null) {
      child = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          borderRadius: radius,
          child: child,
        ),
      );
    }

    return child;
  }

  Color _defaultTint({
    required bool isDark,
    required bool highContrast,
    required GlassVariant variant,
  }) {
    if (variant == GlassVariant.prominent) {
      return AppPalette.brand.withValues(alpha: isDark ? 0.32 : 0.16);
    }

    final alpha = highContrast
        ? (isDark ? 0.78 : 0.82)
        : switch (variant) {
            GlassVariant.regular => isDark ? 0.38 : 0.34,
            GlassVariant.clear => isDark ? 0.18 : 0.20,
            GlassVariant.prominent => 0.0,
          };
    return (isDark ? AppPalette.darkSurface : AppPalette.lightCanvas)
        .withValues(alpha: alpha);
  }

  Color _defaultBorder({required bool isDark, required bool highContrast}) {
    if (highContrast) {
      return isDark ? Colors.white.withValues(alpha: 0.42) : Colors.black54;
    }
    return isDark
        ? Colors.white.withValues(alpha: 0.24)
        : Colors.white.withValues(alpha: 0.85);
  }

  List<BoxShadow> _defaultShadow({
    required bool isDark,
    required GlassRole role,
  }) {
    final blur = switch (role) {
      GlassRole.overlay => 24.0,
      GlassRole.prominent => 20.0,
      GlassRole.control => 16.0,
      GlassRole.navigation => 14.0,
      GlassRole.content => 12.0,
    };
    final alpha = switch (role) {
      GlassRole.overlay => isDark ? 0.36 : 0.12,
      GlassRole.prominent => isDark ? 0.30 : 0.10,
      GlassRole.control => isDark ? 0.24 : 0.08,
      GlassRole.navigation => isDark ? 0.20 : 0.06,
      GlassRole.content => isDark ? 0.16 : 0.05,
    };
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: alpha),
        blurRadius: blur,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: alpha * 0.5),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  double _blurFor(GlassRole role) => switch (role) {
        GlassRole.navigation => 24,
        GlassRole.control => 18,
        GlassRole.overlay => 26,
        GlassRole.prominent => 20,
        GlassRole.content => 16,
      };

  double _refractionFor(GlassRole role) => switch (role) {
        GlassRole.navigation => 14,
        GlassRole.control => 16,
        GlassRole.overlay => 18,
        GlassRole.prominent => 18,
        GlassRole.content => 12,
      };

  double _edgeFor(GlassRole role) => switch (role) {
        GlassRole.navigation => 18,
        GlassRole.control => 18,
        GlassRole.overlay => 24,
        GlassRole.prominent => 20,
        GlassRole.content => 16,
      };

  double _glossFor(GlassRole role) => switch (role) {
        GlassRole.navigation => 0.45,
        GlassRole.control => 0.55,
        GlassRole.overlay => 0.50,
        GlassRole.prominent => 0.65,
        GlassRole.content => 0.40,
      };

  double _chromaticFor(GlassRole role) => switch (role) {
        GlassRole.navigation => 1.8,
        GlassRole.control => 2.2,
        GlassRole.overlay => 2.0,
        GlassRole.prominent => 2.4,
        GlassRole.content => 1.4,
      };
}
