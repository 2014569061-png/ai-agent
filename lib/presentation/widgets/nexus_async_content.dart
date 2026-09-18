import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../application/error_humanizer.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'empty_state_view.dart';
import 'nexus_disclosure.dart';

/// 异步内容容器（统一替代分散的 Spinner 和零碎状态）
class NexusAsyncContent extends StatelessWidget {
  final bool loading;
  final bool isEmpty;
  final Object? error;
  final VoidCallback? onRetry;
  final Widget child;

  /// 自定义骨架加载占位（优先使用）
  final Widget? loadingSkeleton;

  /// 空数据状态定制
  final String? emptyTitle;
  final String? emptySubtitle;
  final IconData? emptyIcon;
  final Widget? emptyAction;

  /// 局部刷新（保留现有 child，仅在顶部显示细小进度条）
  final bool refreshing;

  /// 错误时是否仍然显示 child（即 partialError，已加载内容仍保留）
  final bool retainContentOnError;

  const NexusAsyncContent({
    super.key,
    required this.loading,
    this.isEmpty = false,
    this.error,
    this.onRetry,
    required this.child,
    this.loadingSkeleton,
    this.emptyTitle,
    this.emptySubtitle,
    this.emptyIcon,
    this.emptyAction,
    this.refreshing = false,
    this.retainContentOnError = false,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && !refreshing) {
      if (loadingSkeleton != null) {
        return loadingSkeleton!;
      }
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.0),
        ),
      );
    }

    if (error != null) {
      if (retainContentOnError) {
        return Column(
          children: [
            _InlineErrorBanner(error: error!, onRetry: onRetry),
            Expanded(child: child),
          ],
        );
      }
      return _FullPageErrorView(error: error!, onRetry: onRetry);
    }

    if (isEmpty) {
      return Center(
        child: EmptyStateView(
          icon: emptyIcon ?? Icons.inbox_outlined,
          title: emptyTitle ?? '暂无内容',
          message: emptySubtitle,
          action: emptyAction,
        ),
      );
    }

    if (refreshing) {
      return Column(
        children: [
          const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
          Expanded(child: child),
        ],
      );
    }

    return child;
  }
}

class _InlineErrorBanner extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const _InlineErrorBanner({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final humanized = humanizeError(error.toString());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? AppPalette.darkDangerSoft : AppPalette.lightDangerSoft,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: AppPalette.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              humanized.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: AppTokens.fontSizeFootnote,
                  color: AppPalette.danger),
            ),
          ),
          if (onRetry != null)
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: onRetry,
              child: const Text('重试',
                  style: TextStyle(fontSize: AppTokens.fontSizeFootnote)),
            ),
        ],
      ),
    );
  }
}

class _FullPageErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const _FullPageErrorView({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final humanized = humanizeError(error.toString());

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDark ? AppPalette.darkDangerSoft : AppPalette.lightDangerSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_outlined,
                size: 28,
                color: AppPalette.danger,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '加载未成功',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? AppPalette.darkText : AppPalette.lightText,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                humanized.summary,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: textMuted,
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
              ),
            ],
            if (humanized.detail.isNotEmpty) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: NexusDisclosure(
                  title: Text(
                    '技术诊断详情',
                    style: TextStyle(
                        fontSize: AppTokens.fontSizeFootnote,
                        color: textMuted),
                  ),
                  trailingActions: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    tooltip: '复制详情',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: humanized.detail));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制技术诊断信息'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
                      borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                      border: Border.all(
                        color: isDark ? AppPalette.darkHairline : AppPalette.lightHairline,
                      ),
                    ),
                    child: SelectableText(
                      humanized.detail,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4,
                        color: textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
