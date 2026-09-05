import 'package:flutter/material.dart';

import 'immersive_sheet.dart';

Future<bool> showConfirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
}) async {
  final result = await showImmersiveDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}
