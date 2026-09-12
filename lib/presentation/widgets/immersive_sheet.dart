import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_tokens.dart';
import 'immersive_surface.dart';

/// 统一的沉浸式悬浮弹窗 (Floating Modal Dialog) 入口。
/// 彻底替代底边抽出的 BottomSheet，采用悬浮微磨砂卡片形式呈现。
Future<T?> showImmersiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool showDragHandle = false,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppStrings.closeApprovalSheet,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final media = MediaQuery.sizeOf(dialogContext);
      final baseTheme = Theme.of(dialogContext);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 460,
              maxHeight: media.height * 0.82,
            ),
            child: Material(
              color: Colors.transparent,
              child: ImmersiveSurface(
                level: ImmersiveMaterialLevel.ultraThick,
                borderRadius: BorderRadius.circular(AppTokens.modalRadius),
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                // 外壳已提供表面，内部的 AlertDialog 必须透明，
                // 否则会在表面之上再叠一层不透明底，形成双重边框。
                // 全局 dialogTheme 保留 canvas 作为裸 showDialog 的兜底。
                child: Theme(
                  data: baseTheme.copyWith(
                    dialogTheme: baseTheme.dialogTheme.copyWith(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      surfaceTintColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: builder(dialogContext),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, anim, secAnim, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curve),
          child: child,
        ),
      );
    },
  );
}

/// 统一的沉浸式毛玻璃对话框入口，替代不透明的 showDialog / AlertDialog 表面。
/// 现有 AlertDialog 代码体无需改动：外壳把 dialogTheme 覆盖为透明，
/// 由 ImmersiveSurface 提供毛玻璃表面（裸 Dialog 内容同样自动变透明）。
Future<T?> showImmersiveDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: AppStrings.closeDialog,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final baseTheme = Theme.of(dialogContext);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 320),
            child: Material(
              color: Colors.transparent,
              child: ImmersiveSurface(
                level: ImmersiveMaterialLevel.ultraThick,
                borderRadius: BorderRadius.circular(AppTokens.modalRadius),
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                child: Theme(
                  data: baseTheme.copyWith(
                    dialogTheme: baseTheme.dialogTheme.copyWith(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      surfaceTintColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ),
                  ),
                  child: builder(dialogContext),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, anim, secAnim, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curve),
          child: child,
        ),
      );
    },
  );
}
