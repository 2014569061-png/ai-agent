import 'package:flutter/material.dart';

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
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('加载失败', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                error.toString(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return child;
  }
}
