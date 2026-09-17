import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// 液态玻璃强度档位。
///
/// 三档的存在是为了让「美观」与「可读性 / 性能 / 平铺规范」之间可调，
/// 而不是一刀切：
///
/// * [flat]    纯平面 —— 膜层 + hairline 描边，零模糊。与 v2 设计规范
///             （纯扁平、零阴影、零肌理）完全一致，也是旧 `GlassChip` 的行为。
/// * [frosted] 磨砂 —— 对背景做高斯模糊，全平台可用（Skia / Impeller 均可）。
/// * [liquid]  液态 —— 磨砂 + 边缘折射 + 镜面高光，最接近 Apple Liquid Glass。
///             需要 Impeller 后端；不可用时**自动降级**为 [frosted]，不会抛异常。
enum GlassIntensity { flat, frosted, liquid }

/// 液态玻璃面板。
///
/// 关键约束：**玻璃必须叠在有内容的背景之上才有意义。**
/// 若它背后的像素是一片纯色（例如 `NexusBackground` 的单色画布），
/// 模糊与折射都不会产生任何可见变化 —— 效果等同于一个普通容器。
/// 因此正确的落点是「浮在滚动内容之上」的位置：顶栏、悬浮输入区、
/// Toast、底部弹层。内容在它下方滚动时，玻璃效果才成立。
///
/// 用法：
/// ```dart
/// LiquidGlass(
///   intensity: GlassIntensity.liquid,
///   borderRadius: BorderRadius.circular(AppTokens.radiusModal),
///   child: const Text('浮在内容之上'),
/// )
/// ```
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.intensity = GlassIntensity.liquid,
    this.borderRadius,
    this.blurSigma = 16,
    this.refraction = 16,
    this.edgeWidth = 22,
    this.gloss = 0.45,
    this.chromaticAberration = 2.2,
    this.tint,
    this.outlined = true,
    this.borderColor,
    this.borderWidth = 1.0,
    this.boxShadow,
    this.padding,
    this.margin,
  });

  final Widget child;
  final GlassIntensity intensity;

  /// 面板圆角，默认 [AppTokens.radiusModal]（16）。
  final BorderRadius? borderRadius;

  /// 高斯模糊强度。越大越糊，也越贵。
  final double blurSigma;

  /// 边缘折射位移强度（逻辑像素）。着色器不可用时此项无效。
  final double refraction;

  /// 折射带宽度（逻辑像素）。应显著小于面板短边。
  final double edgeWidth;

  /// 左上方向镜面高光强度 0..1。
  final double gloss;
  final double chromaticAberration;

  /// 膜层颜色。缺省按明暗模式取画布色加透明度。
  final Color? tint;

  /// 是否描边。平面档用 hairline，玻璃档用高光边缘。
  final bool outlined;

  /// 自定义描边颜色。如果为空，根据明暗模式自动取值。
  final Color? borderColor;

  /// 自定义描边粗细，默认 1.0。
  final double borderWidth;

  /// 投射阴影。
  final List<BoxShadow>? boxShadow;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// 清空折射着色器程序缓存。
  ///
  /// 正常构建流程不需要调用；用于测试隔离，以及在热重载后强制重新读取资源。
  static void resetShaderCache() => _GlassShaderProgram.reset();

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  /// 每个实例独占一个 FragmentShader，避免多面板共用导致 uniform 串扰。
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _ensureShader();
  }

  @override
  void didUpdateWidget(covariant LiquidGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intensity != widget.intensity) {
      _ensureShader();
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  void _ensureShader() {
    if (widget.intensity != GlassIntensity.liquid || _shader != null) return;
    // 先查后端能力，避免白跑一次资源加载。
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    unawaited(_loadShader());
  }

  Future<void> _loadShader() async {
    final program = await _GlassShaderProgram.resolve();
    if (!mounted || program == null) return;
    setState(() => _shader = program.fragmentShader());
  }

  @override
  Widget build(BuildContext context) {
    final radius =
        widget.borderRadius ?? BorderRadius.circular(AppTokens.radiusModal);

    if (widget.intensity == GlassIntensity.flat) {
      return _buildShell(context, radius, null);
    }

    // 折射需要知道面板尺寸才能算圆角距离场；拿不到有限约束时退回磨砂。
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasSize =
            constraints.maxWidth.isFinite && constraints.maxHeight.isFinite;
        final size =
            hasSize ? Size(constraints.maxWidth, constraints.maxHeight) : null;
        return _buildShell(context, radius, _resolveFilter(size));
      },
    );
  }

  /// 优先返回折射滤镜；任何一环不满足即退回高斯模糊。
  ui.ImageFilter _resolveFilter(Size? size) {
    final shader = _shader;
    if (widget.intensity == GlassIntensity.liquid &&
        shader != null &&
        size != null &&
        size.width > 0 &&
        size.height > 0) {
      try {
        shader
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          ..setFloat(2, _shaderRadius(size))
          ..setFloat(3, widget.refraction)
          ..setFloat(4, widget.edgeWidth)
          ..setFloat(5, widget.gloss)
          ..setFloat(6, widget.chromaticAberration);
        // Keep the same ordering as a physical glass pipeline:
        // backdrop blur first, then the lens displacement/color split. The
        // shader alone only displaces samples and otherwise leaves a sharp
        // backdrop, which is why the previous implementation read as a
        // translucent tint on detailed content.
        return ui.ImageFilter.compose(
          outer: ui.ImageFilter.shader(shader),
          inner: ui.ImageFilter.blur(
            sigmaX: widget.blurSigma,
            sigmaY: widget.blurSigma,
            tileMode: ui.TileMode.clamp,
          ),
        );
      } catch (_) {
        // uniform 数量不匹配或后端拒绝：静默降级，不让玻璃把页面拖垮。
      }
    }
    return ui.ImageFilter.blur(
      sigmaX: widget.blurSigma,
      sigmaY: widget.blurSigma,
      tileMode: ui.TileMode.clamp,
    );
  }

  /// 着色器只支持统一圆角，取左上角并在短边内钳制。
  double _shaderRadius(Size size) {
    final raw =
        (widget.borderRadius ?? BorderRadius.circular(AppTokens.radiusModal))
            .topLeft
            .x;
    return raw.clamp(0.0, size.shortestSide / 2);
  }

  Widget _buildShell(
    BuildContext context,
    BorderRadius radius,
    ui.ImageFilter? filter,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hasExplicitBorder = widget.borderColor != null;
    final border = widget.outlined
        ? Border.all(
            color: hasExplicitBorder
                ? widget.borderColor!
                : _borderColor(isDark),
            width: widget.borderWidth,
          )
        : null;

    Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.tint ?? _defaultTint(isDark),
        borderRadius: radius,
        border: border,
        boxShadow: widget.boxShadow,
      ),
      child: widget.padding == null
          ? widget.child
          : Padding(padding: widget.padding!, child: widget.child),
    );

    if (filter != null) {
      panel = BackdropGroup.of(context) == null
          ? BackdropFilter(filter: filter, child: panel)
          : BackdropFilter.grouped(filter: filter, child: panel);
    }

    final content = ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          panel,
          if (widget.intensity != GlassIntensity.flat)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GlassOpticalPainter(
                    borderRadius: radius,
                    isDark: isDark,
                    gloss: widget.gloss,
                    outlined: widget.outlined,
                    liquid: widget.intensity == GlassIntensity.liquid,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Container(
      margin: widget.margin,
      child: content,
    );
  }

  Color _defaultTint(bool isDark) {
    // 玻璃膜层留足透明度，让底层极光背景与毛玻璃内容清晰透出
    return isDark
        ? AppPalette.darkSurface.withValues(alpha: 0.38)
        : AppPalette.lightCanvas.withValues(alpha: 0.34);
  }

  Color _borderColor(bool isDark) {
    if (widget.intensity == GlassIntensity.flat) {
      return isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    }
    // 玻璃档默认使用半透明白色高光
    return isDark ? const Color(0x33FFFFFF) : const Color(0x66FFFFFF);
  }
}

/// Paints the optical layer that reproduces Apple Liquid Glass specular rim highlights,
/// vertical light transmission gradients, and lens edge bevels.
class _GlassOpticalPainter extends CustomPainter {
  const _GlassOpticalPainter({
    required this.borderRadius,
    required this.isDark,
    required this.gloss,
    required this.outlined,
    required this.liquid,
  });

  final BorderRadius borderRadius;
  final bool isDark;
  final double gloss;
  final bool outlined;
  final bool liquid;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Offset.zero & size;
    final shape = borderRadius.toRRect(rect).deflate(0.5);
    final normalizedGloss = gloss.clamp(0.0, 1.0);

    canvas.save();
    canvas.clipRRect(shape);

    // 1. 顶部透光微光渐变 (Top-to-bottom surface sheen)
    final surfaceSheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                Colors.white.withValues(alpha: 0.08 + normalizedGloss * 0.10),
                Colors.white.withValues(alpha: 0.015),
                Colors.black.withValues(alpha: liquid ? 0.14 : 0.08),
              ]
            : [
                Colors.white.withValues(alpha: 0.16 + normalizedGloss * 0.14),
                Colors.white.withValues(alpha: 0.03),
                Colors.black.withValues(alpha: liquid ? 0.04 : 0.02),
              ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, surfaceSheen);

    // 2. 左上透镜漫反射光斑 (Lens Specular Sweep)
    final sheenRect = Rect.fromLTWH(
      -size.width * 0.15,
      -size.height * 0.35,
      size.width * 1.25,
      size.height * 0.85,
    );
    final specular = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.14 + normalizedGloss * 0.20),
          Colors.white.withValues(alpha: 0.025 + normalizedGloss * 0.03),
          Colors.transparent,
        ],
        stops: const [0.0, 0.38, 1.0],
      ).createShader(sheenRect);
    canvas.drawRect(rect, specular);
    canvas.restore();

    if (!outlined) return;

    // 3. iOS 标志性顶部定向渐变高光边框 (Specular Rim Light)
    // 顶部与圆角处呈现晶莹高亮白光，向两侧及底部优雅渐变衰减
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = liquid ? 1.2 : 1.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                Colors.white.withValues(alpha: 0.82 + normalizedGloss * 0.15),
                Colors.white.withValues(alpha: 0.35),
                Colors.white.withValues(alpha: 0.08),
                Colors.transparent,
              ]
            : [
                Colors.white.withValues(alpha: 0.95),
                Colors.white.withValues(alpha: 0.55),
                Colors.white.withValues(alpha: 0.15),
                Colors.transparent,
              ],
        stops: const [0.0, 0.18, 0.65, 1.0],
      ).createShader(rect);
    canvas.drawRRect(shape, highlight);

    // 4. 底部微弱内倒角阴影 (Lower Bevel Shadow) 增强厚度立体感
    final lowerEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = liquid ? 1.1 : 0.8
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
          Colors.black.withValues(alpha: isDark ? 0.38 : 0.10),
        ],
        stops: const [0.45, 0.80, 1.0],
      ).createShader(rect);
    canvas.drawRRect(shape.deflate(0.4), lowerEdge);
  }

  @override
  bool shouldRepaint(covariant _GlassOpticalPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.isDark != isDark ||
        oldDelegate.gloss != gloss ||
        oldDelegate.outlined != outlined ||
        oldDelegate.liquid != liquid;
  }
}

/// 折射着色器程序进程内单例。
///
/// 加载失败后置位，避免每次 rebuild 都重新尝试读取资源。
class _GlassShaderProgram {
  static const String assetPath = 'shaders/liquid_glass.frag';

  static ui.FragmentProgram? _program;
  static bool _failed = false;
  static Future<ui.FragmentProgram?>? _pending;

  static Future<ui.FragmentProgram?> resolve() {
    final cached = _program;
    if (cached != null) return Future<ui.FragmentProgram?>.value(cached);
    if (_failed) return Future<ui.FragmentProgram?>.value();
    return _pending ??= _load();
  }

  static Future<ui.FragmentProgram?> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(assetPath);
      _program = program;
      return program;
    } catch (_) {
      _failed = true;
      _pending = null;
      return null;
    }
  }

  static void reset() {
    _program = null;
    _failed = false;
    _pending = null;
  }
}
