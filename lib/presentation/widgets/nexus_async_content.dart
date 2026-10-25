import '../theme/mobile_theme.dart';
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
      return Center(
          child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.all(16),
        child: Semantics(
            liveRegion: true,
            label: '正在加载内容',
            child: ExcludeSemantics(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(height: 12),
              Text('正在加载…', style: Theme.of(context).textTheme.bodySmall),
            ]))),
      ));
    }

    if (error != null) {
      if (retainContentOnError) {
        return _ContentFrame(
          status: _InlineErrorBanner(error: error!, onRetry: onRetry),
          child: child,
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

    return _ContentFrame(
      status: refreshing
          ? Semantics(
              liveRegion: true,
              child: const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  semanticsLabel: '正在刷新，当前内容仍可查看'))
          : null,
      child: child,
    );
  }
}

class _ContentFrame extends StatelessWidget {
  const _ContentFrame({required this.child, this.status});
  final Widget child;
  final Widget? status;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        return Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: constraints.hasBoundedWidth
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: [
              if (status == null)
                const SizedBox.shrink()
              else
                ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: bounded
                            ? constraints.maxHeight * .45
                            : double.infinity),
                    child:
                        SingleChildScrollView(primary: false, child: status!)),
              if (bounded) Expanded(child: child) else child,
            ]);
      });
}

class _InlineErrorBanner extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const _InlineErrorBanner({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final humanized = humanizeError(error.toString());

    final danger = Theme.of(context).colorScheme.error;
    return Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                isDark ? AppPalette.darkDangerSoft : AppPalette.lightDangerSoft,
            borderRadius:
                BorderRadius.circular(MobileTheme.controlRadius(context)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline_rounded, size: 18, color: danger),
              const SizedBox(width: 8),
              Expanded(
                  child: Tooltip(
                      message: humanized.summary,
                      child: Text(humanized.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppTokens.fontSizeFootnote,
                              color: danger)))),
            ]),
            const SizedBox(height: 4),
            Text('已保留上次加载的内容',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            if (onRetry != null)
              TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('重试')),
          ]),
        ));
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
                color: isDark
                    ? AppPalette.darkDangerSoft
                    : AppPalette.lightDangerSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_outlined,
                size: 28,
                color: AppPalette.danger,
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  '加载未成功',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppPalette.darkText : AppPalette.lightText,
                  ),
                )),
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
                        fontSize: AppTokens.fontSizeFootnote, color: textMuted),
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
                      color: isDark
                          ? AppPalette.darkSurface
                          : AppPalette.lightSurface,
                      borderRadius: BorderRadius.circular(
                          MobileTheme.controlRadius(context)),
                      border: Border.all(
                        color: isDark
                            ? AppPalette.darkHairline
                            : AppPalette.lightHairline,
                      ),
                    ),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: SingleChildScrollView(
                            primary: false,
                            child: SelectableText(
                              humanized.detail,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.4,
                                color: textMuted,
                              ),
                            ))),
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
