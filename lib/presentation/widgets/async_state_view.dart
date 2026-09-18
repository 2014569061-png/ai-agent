import 'package:flutter/material.dart';
import 'nexus_async_content.dart';

/// 统一异步状态视图（兼容旧接口，并自动复用 NexusAsyncContent 与骨架屏能力）
class AsyncStateView extends StatelessWidget {
  final bool loading;
  final bool isEmpty;
  final Object? error;
  final VoidCallback? onRetry;
  final Widget child;
  final Widget? loadingSkeleton;
  final String? emptyTitle;
  final String? emptySubtitle;
  final IconData? emptyIcon;
  final Widget? emptyAction;
  final bool refreshing;
  final bool retainContentOnError;

  const AsyncStateView({
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
    return NexusAsyncContent(
      loading: loading,
      isEmpty: isEmpty,
      error: error,
      onRetry: onRetry,
      loadingSkeleton: loadingSkeleton,
      emptyTitle: emptyTitle,
      emptySubtitle: emptySubtitle,
      emptyIcon: emptyIcon,
      emptyAction: emptyAction,
      refreshing: refreshing,
      retainContentOnError: retainContentOnError,
      child: child,
    );
  }
}
