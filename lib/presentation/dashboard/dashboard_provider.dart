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
  // The dashboard only needs the plan and the selected conversation. Avoid
  // rerunning all of the SQL aggregates for message-stream updates.
  final chatContext = ref.watch(
    chatControllerProvider.select(
      (state) => (state.planState, state.conversationId),
    ),
  );

  return service.loadSummary(
    db: db,
    currentPlanState: chatContext.$1,
    currentConversationId: chatContext.$2,
  );
});
