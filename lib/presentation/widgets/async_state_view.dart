import 'package:flutter/material.dart';
import '../../application/error_humanizer.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

class AsyncStateView extends StatelessWidget {
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;
  final Widget child;

  const AsyncStateView({
    super.key,
    required this.loading,
    this.error,
    this.onRetry,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
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
              const Icon(
                Icons.cloud_off_outlined,
                size: 44,
                color: AppPalette.danger,
              ),
              const SizedBox(height: 12),
              Text(
                '加载失败',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
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
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                ),
              ],
              if (humanized.detail.isNotEmpty) ...[
                const SizedBox(height: 12),
                _AsyncErrorDetailBlock(detail: humanized.detail),
              ],
            ],
          ),
        ),
      );
    }
    return child;
  }
}

class _AsyncErrorDetailBlock extends StatefulWidget {
  const _AsyncErrorDetailBlock({required this.detail});
  final String detail;

  @override
  State<_AsyncErrorDetailBlock> createState() => _AsyncErrorDetailBlockState();
}

class _AsyncErrorDetailBlockState extends State<_AsyncErrorDetailBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expanded ? '收起技术详情' : '展开技术详情',
                    style: TextStyle(fontSize: 12, color: textMuted),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                border: Border.all(color: hairline),
              ),
              child: SelectableText(
                widget.detail,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.4,
                  color: textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
