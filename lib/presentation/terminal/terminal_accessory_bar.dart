import 'package:flutter/material.dart';

import '../motion/nexus_haptics.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// 移动端专用终端虚拟辅助按键栏。
///
/// 解决手机软键盘缺乏 ESC、TAB、CTRL、ALT 与方向键的问题，
/// 支持 CTRL 黏滞锁定与触觉振动反馈。
class TerminalAccessoryBar extends StatefulWidget {
  const TerminalAccessoryBar({
    super.key,
    required this.onSendInput,
    required this.onSendCtrl,
    this.ctrlActive = false,
    this.onToggleCtrl,
  });

  final ValueChanged<String> onSendInput;
  final ValueChanged<String> onSendCtrl;
  final bool ctrlActive;
  final ValueChanged<bool>? onToggleCtrl;

  @override
  State<TerminalAccessoryBar> createState() => _TerminalAccessoryBarState();
}

class _TerminalAccessoryBarState extends State<TerminalAccessoryBar> {
  late bool _ctrlActive;

  @override
  void initState() {
    super.initState();
    _ctrlActive = widget.ctrlActive;
  }

  @override
  void didUpdateWidget(covariant TerminalAccessoryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ctrlActive != widget.ctrlActive) {
      _ctrlActive = widget.ctrlActive;
    }
  }

  void _tap(VoidCallback action) {
    NexusHaptics.light(context);
    action();
  }

  void _toggleCtrl() {
    NexusHaptics.selection(context);
    setState(() {
      _ctrlActive = !_ctrlActive;
    });
    widget.onToggleCtrl?.call(_ctrlActive);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final barBg = isDark ? AppPalette.terminalHeaderBg : AppPalette.lightSurfaceHover;
    final borderColor = isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    return Container(
      height: 44,
      width: double.infinity,
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          top: BorderSide(color: borderColor, width: 0.8),
          bottom: BorderSide(color: borderColor, width: 0.8),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        children: [
          _keyButton(
            label: 'ESC',
            onTap: () => _tap(() => widget.onSendInput('\x1b')),
          ),
          _keyButton(
            label: 'TAB',
            onTap: () => _tap(() => widget.onSendInput('\t')),
          ),
          _keyButton(
            label: 'CTRL',
            active: _ctrlActive,
            highlight: true,
            onTap: _toggleCtrl,
          ),
          _keyButton(
            label: 'ALT',
            onTap: () => _tap(() => widget.onSendInput('\x1b')),
          ),
          _keyButton(
            label: 'Ctrl+C',
            danger: true,
            onTap: () => _tap(() {
              widget.onSendCtrl('C');
              if (_ctrlActive) _toggleCtrl();
            }),
          ),
          _keyButton(
            label: 'Ctrl+D',
            onTap: () => _tap(() {
              widget.onSendCtrl('D');
              if (_ctrlActive) _toggleCtrl();
            }),
          ),
          _keyButton(
            label: 'Ctrl+Z',
            onTap: () => _tap(() {
              widget.onSendCtrl('Z');
              if (_ctrlActive) _toggleCtrl();
            }),
          ),
          _keyButton(
            label: '←',
            onTap: () => _tap(() => widget.onSendInput('\x1b[D')),
          ),
          _keyButton(
            label: '→',
            onTap: () => _tap(() => widget.onSendInput('\x1b[C')),
          ),
          _keyButton(
            label: '↑',
            onTap: () => _tap(() => widget.onSendInput('\x1b[A')),
          ),
          _keyButton(
            label: '↓',
            onTap: () => _tap(() => widget.onSendInput('\x1b[B')),
          ),
          _keyButton(
            label: '/',
            onTap: () => _tap(() => widget.onSendInput('/')),
          ),
          _keyButton(
            label: '-',
            onTap: () => _tap(() => widget.onSendInput('-')),
          ),
          _keyButton(
            label: '|',
            onTap: () => _tap(() => widget.onSendInput('|')),
          ),
          _keyButton(
            label: '~',
            onTap: () => _tap(() => widget.onSendInput('~')),
          ),
          _keyButton(
            label: 'clear',
            onTap: () => _tap(() {
              widget.onSendCtrl('L');
            }),
          ),
        ],
      ),
    );
  }

  Widget _keyButton({
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool highlight = false,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color bg;
    Color fg;
    Color border;

    if (active) {
      bg = AppPalette.brand;
      fg = Colors.white;
      border = AppPalette.brand;
    } else if (danger) {
      bg = isDark ? AppPalette.darkDangerSoft : AppPalette.lightDangerSoft;
      fg = isDark ? AppPalette.darkDanger : AppPalette.lightDanger;
      border = (isDark ? AppPalette.darkDanger : AppPalette.lightDanger).withValues(alpha: 0.3);
    } else if (highlight) {
      bg = isDark ? AppPalette.darkBrandSoft : AppPalette.lightBrandSoft;
      fg = isDark ? AppPalette.darkBrandHover : AppPalette.brandAction;
      border = (isDark ? AppPalette.darkBrandHover : AppPalette.brand).withValues(alpha: 0.25);
    } else {
      bg = isDark ? AppPalette.terminalSurface : AppPalette.lightCanvas;
      fg = isDark ? AppPalette.terminalText : AppPalette.lightText;
      border = isDark ? AppPalette.terminalBorder : AppPalette.lightHairline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          child: Container(
            constraints: const BoxConstraints(minWidth: 38),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              border: Border.all(color: border, width: 0.8),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: (active || highlight || danger)
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
