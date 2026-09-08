import '../domain/collaboration_models.dart';

class CollaborationBudget {
  const CollaborationBudget({
    this.maxAgents = 4,
    this.maxRounds = 2,
    this.maxTokens = 8000,
    this.maxDuration = const Duration(minutes: 5),
  });

  final int maxAgents;
  final int maxRounds;
  final int maxTokens;
  final Duration maxDuration;

  CollaborationBudget clamp(CollaborationApproval approval) {
    final agents = approval.maxAgents.clamp(1, maxAgents).toInt();
    final rounds = approval.maxRounds.clamp(1, maxRounds).toInt();
    final tokens = approval.budgetTokens.clamp(500, maxTokens).toInt();
    return CollaborationBudget(
      maxAgents: agents,
      maxRounds: rounds,
      maxTokens: tokens,
      maxDuration: maxDuration,
    );
  }

  bool canStart({required int consumedTokens, required int requestedTokens}) {
    return consumedTokens + requestedTokens <= maxTokens;
  }
}
