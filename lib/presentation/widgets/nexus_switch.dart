import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/desktop_theme.dart';

import '../motion/nexus_haptics.dart';
import '../motion/nexus_spring.dart';

/// L6：弹簧开关，[Switch] / [Switch.adaptive] 的替身（同名常用参数）。
///
/// - 滑块位置由 bouncy 弹簧驱动，到位时带一次轻回弹；中途再点从当前速度折返；
/// - 滑块直径随开关 16 → 24，按住时横向拉伸（果冻感），松手弹回；
/// - 轨道颜色随位置插值；切换时 selection 触感；支持横向拖动切换。
class NexusSwitch extends StatefulWidget {
  const NexusSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeTrackColor,
    this.activeThumbColor,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeTrackColor;
  final Color? activeThumbColor;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  static const double trackWidth = 52;
  static const double trackHeight = 32;

  @override
  State<NexusSwitch> createState() => _NexusSwitchState();
}

class _NexusSwitchState extends State<NexusSwitch>
    with TickerProviderStateMixin {
  late final SpringController _position =
      SpringController(vsync: this, value: widget.value ? 1 : 0);
  late final SpringController _press = SpringController(vsync: this);

  bool get _enabled => widget.onChanged != null;
  bool _hasFocus = false;
  bool _showFocusHighlight = false;

  @override
  void didUpdateWidget(covariant NexusSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _settle(widget.value);
  }

  @override
  void dispose() {
    _position.dispose();
    _press.dispose();
    super.dispose();
  }

  void _settle(bool on) {
    _position.animateTo(
      on ? 1 : 0,
      spring: NexusSpringPolicy.resolve(context, NexusSprings.bouncy,
          listen: false),
    );
  }

  void _pressTo(double target) {
    _press.animateTo(
      target,
      spring: NexusSpringPolicy.resolve(context, NexusSprings.snappy,
          listen: false),
    );
  }

  void _toggle(bool next) {
    if (!_enabled) return;
    if (next == widget.value) {
      _settle(next);
      return;
    }
    NexusHaptics.selection(context);
    widget.onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onTrack = widget.activeTrackColor ?? scheme.primary;
    final onThumb = widget.activeThumbColor ?? scheme.onPrimary;
    final offTrack = scheme.surfaceContainerHighest;
    final offThumb = scheme.outline;
    const travel = NexusSwitch.trackWidth - NexusSwitch.trackHeight;
    return Semantics(
      label: widget.semanticLabel,
      focusable: _enabled,
      focused: _enabled ? _hasFocus : null,
      onTap: _enabled ? () => _toggle(!widget.value) : null,
      toggled: widget.value,
      enabled: _enabled,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        includeFocusSemantics: false,
        mouseCursor:
            _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onFocusChange: (value) => setState(() => _hasFocus = value),
        onShowFocusHighlight: (value) =>
            setState(() => _showFocusHighlight = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _toggle(!widget.value);
            return null;
          }),
        },
        child: Opacity(
          opacity: _enabled ? 1 : 0.38,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapDown: _enabled ? (_) => _pressTo(1) : null,
            onTapCancel: _enabled ? () => _pressTo(0) : null,
            onTapUp: _enabled
                ? (_) {
                    _pressTo(0);
                    _toggle(!widget.value);
                  }
                : null,
            onHorizontalDragStart: _enabled
                ? (_) {
                    _position.stop();
                    _pressTo(1);
                  }
                : null,
            onHorizontalDragUpdate: _enabled
                ? (details) => _position.jumpTo(
                    (_position.value + details.primaryDelta! / travel)
                        .clamp(0.0, 1.0))
                : null,
            onHorizontalDragEnd: _enabled
                ? (details) {
                    _pressTo(0);
                    final v = details.primaryVelocity ?? 0;
                    final next = v.abs() > 300 ? v > 0 : _position.value > 0.5;
                    _toggle(next);
                  }
                : null,
            onHorizontalDragCancel: _enabled
                ? () {
                    _pressTo(0);
                    _settle(widget.value);
                  }
                : null,
            child: DecoratedBox(
              key: const ValueKey('nexus_switch_focus_ring'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    width: 2,
                    color: _showFocusHighlight
                        ? scheme.onSurface
                        : Colors.transparent),
              ),
              child: SizedBox(
                width: NexusSwitch.trackWidth + 8,
                height: DesktopTheme.maybeOf(context) == null
                    ? 48
                    : NexusSwitch.trackHeight + 8,
                child: Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_position, _press]),
                    builder: (context, _) {
                      final p = _position.value;
                      final pc = p.clamp(0.0, 1.0);
                      final press = _press.value.clamp(0.0, 1.0);
                      final diameter = 16 + 8 * pc + 4 * press;
                      final width = diameter + 6 * press;
                      const half = NexusSwitch.trackHeight / 2;
                      final centerX = half + travel * p;
                      return Container(
                        key: const ValueKey('nexus_switch_track'),
                        width: NexusSwitch.trackWidth,
                        height: NexusSwitch.trackHeight,
                        decoration: BoxDecoration(
                          color: Color.lerp(offTrack, onTrack, pc),
                          borderRadius: BorderRadius.circular(half),
                          border: Border.all(
                            color: offThumb.withValues(alpha: 1 - pc),
                            width: 2,
                          ),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: centerX - width / 2 - 2,
                              top: half - diameter / 2 - 2,
                              child: Container(
                                key: const ValueKey('nexus_switch_thumb'),
                                width: width,
                                height: diameter,
                                decoration: BoxDecoration(
                                  color: Color.lerp(offThumb, onThumb, pc),
                                  borderRadius: BorderRadius.circular(diameter),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [SwitchListTile] 的替身：整行可点，尾部为 [NexusSwitch]。
class NexusSwitchListTile extends StatelessWidget {
  const NexusSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: ListTile(
        contentPadding: contentPadding,
        leading: secondary,
        title: title,
        subtitle: subtitle,
        enabled: onChanged != null,
        trailing: ExcludeFocus(
          child: NexusSwitch(value: value, onChanged: onChanged),
        ),
        onTap: onChanged == null
            ? null
            : () {
                NexusHaptics.selection(context);
                onChanged(!value);
              },
      ),
    );
  }
}
