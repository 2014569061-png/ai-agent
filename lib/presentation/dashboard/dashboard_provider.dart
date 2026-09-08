import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_controller.dart';
import '../../application/dashboard_service.dart';
import '../../application/providers.dart';

/// 仪表盘聚合数据状态提供者 (Riverpod FutureProvider)
/// 支持自动注销，并提供天然的 ref.invalidate 刷新支持。
final dashboardSummaryProvider =
    FutureProvider.autoDispose<DashboardSummary>((ref) async {
  final service = ref.watch(dashboardServiceProvider);
  final db = await ref.watch(databaseProvider.future);
  final chatState = ref.watch(chatControllerProvider);

  return service.loadSummary(
    db: db,
    currentPlanState: chatState.planState,
    currentConversationId: chatState.conversationId,
  );
});
