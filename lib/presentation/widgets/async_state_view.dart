import 'package:flutter/material.dart';
import 'nexus_async_content.dart';

/// 统一异步状态视图（兼容旧接口，并自动复用 NexusAsyncContent 与骨架屏能力）
class AsyncStateView extends StatelessWidget {
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;
  final Widget child;
  final Widget? loadingSkeleton;

  const AsyncStateView({
    super.key,
    required this.loading,
    this.error,
    this.onRetry,
    required this.child,
    this.loadingSkeleton,
  });

  @override
  Widget build(BuildContext context) {
    return NexusAsyncContent(
      loading: loading,
      error: error,
      onRetry: onRetry,
      loadingSkeleton: loadingSkeleton,
      child: child,
    );
  }
}
