import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'nexus_sheet.dart';

Future<bool> showConfirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool isDanger = true,
  bool barrierDismissible = true,
  String? requiredKeyword,
  List<String>? bulletItems,
}) async {
  final result = await showNexusDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
      final textMuted =
          isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

      return _ConfirmActionDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDanger: isDanger,
        requiredKeyword: requiredKeyword,
        bulletItems: bulletItems,
        textMuted: textMuted,
      );
    },
  );
  return result == true;
}

class _ConfirmActionDialog extends StatefulWidget {
  const _ConfirmActionDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.isDanger,
    this.requiredKeyword,
    this.bulletItems,
    required this.textMuted,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDanger;
  final String? requiredKeyword;
  final List<String>? bulletItems;
  final Color textMuted;

  @override
  State<_ConfirmActionDialog> createState() => _ConfirmActionDialogState();
}

class _ConfirmActionDialogState extends State<_ConfirmActionDialog> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keywordMatches = widget.requiredKeyword == null ||
        _inputController.text.trim().toLowerCase() ==
            widget.requiredKeyword!.trim().toLowerCase();

    final confirmColor =
        widget.isDanger ? AppPalette.danger : AppPalette.brandAction;

    return AlertDialog(
      title: Row(
        children: [
          if (widget.isDanger) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppPalette.danger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: AppPalette.danger, size: 18),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            if (widget.bulletItems != null &&
                widget.bulletItems!.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...widget.bulletItems!.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ',
                          style: TextStyle(
                              color: widget.textMuted,
                              fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(item,
                            style: TextStyle(
                                fontSize: 13, color: widget.textMuted)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (widget.requiredKeyword != null) ...[
              const SizedBox(height: 14),
              Text(
                '请输入确认词「${widget.requiredKeyword}」以继续：',
                style: TextStyle(fontSize: 13, color: widget.textMuted),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _inputController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.requiredKeyword,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusControl),
                  ),
                ),
                onPressed: () => Navigator.pop(context, false),
                child: Text(widget.cancelLabel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: confirmColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTokens.radiusControl),
                  ),
                ),
                onPressed:
                    keywordMatches ? () => Navigator.pop(context, true) : null,
                child: Text(widget.confirmLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
