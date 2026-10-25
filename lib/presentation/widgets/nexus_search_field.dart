import 'package:flutter/material.dart';

/// Shared phone search field, without a fixed height that clips large text.
class NexusSearchField extends StatelessWidget {
  const NexusSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onClear,
    this.onSubmitted,
    this.maxLength,
    this.compact = false,
    this.autofocus = false,
    this.subdued = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final bool compact;
  final bool autofocus;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // The controller may also change from a clear action or an external filter.
    // Update the clear affordance without requiring the page to rebuild.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        maxLength: maxLength,
        textInputAction: TextInputAction.search,
        style: compact ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: hintText,
          counterText: '',
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: value.text.isNotEmpty && onClear != null
              ? IconButton(
                  tooltip: '清空搜索',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 20))
              : null,
          filled: true,
          fillColor: subdued
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5)
              : dark
                  ? const Color(0xFF202B3D)
                  : const Color(0xFFF0F4FA),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(compact ? 12 : 18),
              borderSide: BorderSide.none),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(compact ? 12 : 18),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(compact ? 12 : 18),
              borderSide: BorderSide(
                  color: theme.colorScheme.primary
                      .withValues(alpha: subdued ? .6 : 1),
                  width: subdued ? 1 : 1.2)),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 12 : 14),
        ),
      ),
    );
  }
}
