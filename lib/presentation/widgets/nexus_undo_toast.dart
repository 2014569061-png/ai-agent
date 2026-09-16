import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'floating_toast.dart';

/// 统一撤销 Toast 工具组件
abstract final class NexusUndoToast {
  /// 显示一条具备撤销操作的 Toast
  static void show(
    BuildContext context, {
    required String message,
    required VoidCallback onUndo,
    String undoLabel = '撤销',
    Duration duration = const Duration(seconds: 4),
  }) {
    FloatingToast.show(
      context,
      message,
      tone: ToastTone.neutral,
      actions: [
        FloatingCapsuleAction(
          label: undoLabel,
          icon: Icons.undo_rounded,
          onPressed: () {
            HapticFeedback.lightImpact();
            onUndo();
          },
        ),
      ],
    );
  }
}
