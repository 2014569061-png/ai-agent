import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'immersive_sheet.dart';

/// 玻璃化下拉选择：收起态外观对齐 DropdownButtonFormField（复用全局 InputDecorationTheme），
/// 点开后走 showImmersiveSheet 选单，与全应用弹层毛玻璃保持一致。
/// [items] 直接复用现有 DropdownMenuItem 定义，迁移零成本。
class ImmersiveDropdown<T> extends StatefulWidget {
  const ImmersiveDropdown({
    super.key,
    required this.labelText,
    required this.items,
    this.initialValue,
    this.onChanged,
    this.prefixIcon,
  });

  final String labelText;
  final List<DropdownMenuItem<T>> items;
  final T? initialValue;
  final ValueChanged<T?>? onChanged;
  final Widget? prefixIcon;

  @override
  State<ImmersiveDropdown<T>> createState() => _ImmersiveDropdownState<T>();
}

class _ImmersiveDropdownState<T> extends State<ImmersiveDropdown<T>> {
  late T? _value = widget.initialValue;

  @override
  void didUpdateWidget(covariant ImmersiveDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      _value = widget.initialValue;
    }
  }

  Future<void> _pick() async {
    final theme = Theme.of(context);
    final picked = await showImmersiveSheet<T>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                widget.labelText,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in widget.items)
                    ListTile(
                      selected: item.value == _value,
                      title: item.child,
                      trailing: item.value == _value
                          ? Icon(Icons.check_rounded,
                              color: theme.colorScheme.primary)
                          : null,
                      onTap: () => Navigator.pop(sheetContext, item.value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && picked != _value) {
      setState(() => _value = picked);
      widget.onChanged?.call(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.semanticOf(context);
    Widget? selectedChild;
    for (final item in widget.items) {
      if (item.value == _value) {
        selectedChild = item.child;
        break;
      }
    }
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.capsuleRadius),
      onTap: _pick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.labelText,
          prefixIcon: widget.prefixIcon,
          suffixIcon:
              Icon(Icons.expand_circle_down_rounded, color: colors.textMuted),
        ),
        child: selectedChild ??
            Text(widget.labelText, style: TextStyle(color: colors.textMuted)),
      ),
    );
  }
}
