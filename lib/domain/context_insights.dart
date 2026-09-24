import 'models.dart';

/// The semantic buckets used by the context dashboard.
///
/// Counts in a [ContextSnapshot] are local estimates unless a provider usage
/// sample is available. Keeping the buckets separate from the UI makes the
/// snapshot useful to both the chat HUD and the dashboard.
enum ContextPartType {
  system,
  tools,
  inject,
  skill,
  user,
  assistant,
  toolResult,
}

extension ContextPartTypeX on ContextPartType {
  String get label => switch (this) {
        ContextPartType.system => '系统提示词',
        ContextPartType.tools => '工具定义',
        ContextPartType.inject => '注入内容',
        ContextPartType.skill => 'Skill',
        ContextPartType.user => '用户消息',
        ContextPartType.assistant => '助手消息',
        ContextPartType.toolResult => '工具结果',
      };
}

/// The user-facing budget bands shared by the chat HUD and metrics sheet.
enum ContextBudgetLevel { normal, attention, warning, critical }

extension ContextBudgetLevelX on ContextBudgetLevel {
  String get label => switch (this) {
        ContextBudgetLevel.normal => '正常',
        ContextBudgetLevel.attention => '关注',
        ContextBudgetLevel.warning => '警告',
        ContextBudgetLevel.critical => '需要处理',
      };

  String get description => switch (this) {
        ContextBudgetLevel.normal => '上下文使用低于 70%',
        ContextBudgetLevel.attention => '上下文使用已达到 70%，建议关注增长',
        ContextBudgetLevel.warning => '上下文使用已达到 85%，建议准备裁剪',
        ContextBudgetLevel.critical => '上下文超过 95%，需要裁剪或压缩',
      };
}

/// Centralizes context budget thresholds so warnings do not drift between UI
/// surfaces and the pre-request budget checks.
class ContextBudget {
  const ContextBudget._();

  static const attentionThreshold = 0.70;
  static const warningThreshold = 0.85;
  static const criticalThreshold = 0.95;

  /// Clamps a requested completion reservation to the configured model window.
  /// A non-positive window remains unknown, so the requested value is preserved
  /// for diagnostics rather than silently becoming zero.
  static int outputReservationFor({
    required int contextWindow,
    required int requestedOutputTokens,
  }) {
    final requested = requestedOutputTokens < 0 ? 0 : requestedOutputTokens;
    if (contextWindow <= 0) return requested;
    return requested > contextWindow ? contextWindow : requested;
  }

  /// Returns the share of the model window consumed by input plus the output
  /// reservation. Provider usage reports input tokens only, but the request
  /// still needs room for [reservedOutputTokens]. Keeping that reservation in
  /// the ratio prevents the HUD from calling a request "normal" when the next
  /// completion would already overflow the model window.
  static int inputBudgetFor({
    required int contextWindow,
    required int reservedOutputTokens,
  }) {
    if (contextWindow <= 0) return 0;
    final output = reservedOutputTokens < 0 ? 0 : reservedOutputTokens;
    return contextWindow > output ? contextWindow - output : 0;
  }

  static double ratioFor({
    required int usedTokens,
    required int contextWindow,
    int reservedOutputTokens = 0,
  }) {
    if (contextWindow <= 0) return 0;
    final input = usedTokens < 0 ? 0 : usedTokens;
    final output = reservedOutputTokens < 0 ? 0 : reservedOutputTokens;
    return (input + output) / contextWindow;
  }

  static ContextBudgetLevel levelFor({
    required int usedTokens,
    required int contextWindow,
    int reservedOutputTokens = 0,
  }) {
    final ratio = ratioFor(
      usedTokens: usedTokens,
      contextWindow: contextWindow,
      reservedOutputTokens: reservedOutputTokens,
    );
    if (ratio < attentionThreshold) return ContextBudgetLevel.normal;
    if (ratio < warningThreshold) return ContextBudgetLevel.attention;
    if (ratio <= criticalThreshold) return ContextBudgetLevel.warning;
    return ContextBudgetLevel.critical;
  }
}

class ContextPart {
  const ContextPart({
    required this.type,
    required this.tokens,
    this.estimated = true,
  });

  final ContextPartType type;
  final int tokens;
  final bool estimated;

  ContextPart copyWith({int? tokens, bool? estimated}) => ContextPart(
        type: type,
        tokens: tokens ?? this.tokens,
        estimated: estimated ?? this.estimated,
      );
}

/// The last request-shaped context seen by the executor.
class ContextSnapshot {
  const ContextSnapshot({
    required this.parts,
    required this.usedTokens,
    required this.contextWindow,
    required this.reservedOutputTokens,
    required this.updatedAt,
    this.providerUsage,
    this.omittedParts = const [],
    this.truncatedParts = const [],
  });

  final List<ContextPart> parts;
  final int usedTokens;
  final int contextWindow;
  final int reservedOutputTokens;
  final DateTime updatedAt;
  final Usage? providerUsage;
  final List<String> omittedParts;
  final List<String> truncatedParts;

  double get ratio => ContextBudget.ratioFor(
        usedTokens: usedTokens,
        contextWindow: contextWindow,
        reservedOutputTokens: reservedOutputTokens,
      ).clamp(0.0, 1.0);

  ContextBudgetLevel get budgetLevel => ContextBudget.levelFor(
        usedTokens: usedTokens,
        contextWindow: contextWindow,
        reservedOutputTokens: reservedOutputTokens,
      );

  /// Remaining capacity after both the current input and reserved output.
  int get remainingTokens {
    final consumed = usedTokens + reservedOutputTokens;
    return contextWindow > consumed ? contextWindow - consumed : 0;
  }

  ContextPart? get dominantPart {
    ContextPart? result;
    for (final part in parts) {
      if (part.tokens <= 0 ||
          (result != null && result.tokens >= part.tokens)) {
        continue;
      }
      result = part;
    }
    return result;
  }

  bool get hasEstimatedComposition => parts.any((part) => part.estimated);

  int get providerTotalTokens => providerUsage?.totalTokens ?? 0;

  int tokensFor(ContextPartType type) => parts
      .where((part) => part.type == type)
      .fold(0, (total, part) => total + part.tokens);

  ContextSnapshot copyWith({
    List<ContextPart>? parts,
    int? usedTokens,
    int? contextWindow,
    int? reservedOutputTokens,
    DateTime? updatedAt,
    Usage? providerUsage,
    List<String>? omittedParts,
    List<String>? truncatedParts,
  }) =>
      ContextSnapshot(
        parts: parts ?? this.parts,
        usedTokens: usedTokens ?? this.usedTokens,
        contextWindow: contextWindow ?? this.contextWindow,
        reservedOutputTokens: reservedOutputTokens ?? this.reservedOutputTokens,
        updatedAt: updatedAt ?? this.updatedAt,
        providerUsage: providerUsage ?? this.providerUsage,
        omittedParts: omittedParts ?? this.omittedParts,
        truncatedParts: truncatedParts ?? this.truncatedParts,
      );

  Map<String, dynamic> toJson() => {
        'usedTokens': usedTokens,
        'contextWindow': contextWindow,
        'reservedOutputTokens': reservedOutputTokens,
        'updatedAt': updatedAt.toIso8601String(),
        'omittedParts': omittedParts,
        'truncatedParts': truncatedParts,
        'parts': [
          for (final part in parts)
            {
              'type': part.type.name,
              'tokens': part.tokens,
              'estimated': part.estimated,
            },
        ],
      };

  ContextSnapshot withProviderUsage(Usage usage) => copyWith(
        providerUsage: usage,
        updatedAt: DateTime.now(),
      );
}

/// One final model request in an Agent run. A request snapshot is emitted before
/// streaming begins; provider usage is attached after that request completes.
class ContextStepRecord {
  const ContextStepRecord({
    required this.step,
    required this.snapshot,
    required this.startedAt,
    this.anchorMessageId,
    this.usage,
  });

  final int step;
  final ContextSnapshot snapshot;
  final DateTime startedAt;
  final String? anchorMessageId;
  final Usage? usage;

  ContextStepRecord withUsage(Usage value) => ContextStepRecord(
        step: step,
        snapshot: snapshot.withProviderUsage(value),
        startedAt: startedAt,
        anchorMessageId: anchorMessageId,
        usage: value,
      );

  Map<String, dynamic> toJson() => {
        'step': step,
        'startedAt': startedAt.toIso8601String(),
        if (anchorMessageId != null) 'anchorMessageId': anchorMessageId,
        'snapshot': snapshot.toJson(),
        if (usage != null)
          'usage': {
            'promptTokens': usage!.promptTokens,
            'completionTokens': usage!.completionTokens,
            'cachedTokens': usage!.cachedTokens,
            'cacheWriteTokens': usage!.cacheWriteTokens,
            'reasoningTokens': usage!.reasoningTokens,
            'usageReported': usage!.usageReported,
            'cacheStatsReported': usage!.cacheStatsReported,
          },
      };
}

class ContextRunEvent {
  const ContextRunEvent({
    required this.type,
    required this.name,
    required this.status,
    required this.createdAt,
    this.metadata = const {},
  });

  final String type;
  final String name;
  final String status;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;
}

/// Restored telemetry for one completed or active Agent run.
class ContextRunHistory {
  const ContextRunHistory({
    required this.runId,
    required this.startedAt,
    required this.status,
    required this.steps,
    required this.events,
  });

  final String runId;
  final DateTime startedAt;
  final String status;
  final List<ContextStepRecord> steps;
  final List<ContextRunEvent> events;

  ContextSnapshot? get latestSnapshot =>
      steps.isEmpty ? null : steps.last.snapshot;
}

/// Timing accumulated for the currently visible Agent run.
class TimingSnapshot {
  const TimingSnapshot({
    required this.wallMs,
    required this.modelWaitMs,
    required this.reasoningMs,
    required this.outputMs,
    required this.toolExecutionMs,
    required this.modelCalls,
    required this.toolCalls,
  });

  final int wallMs;
  final int modelWaitMs;
  final int reasoningMs;
  final int outputMs;
  final int toolExecutionMs;
  final int modelCalls;
  final int toolCalls;

  static const empty = TimingSnapshot(
    wallMs: 0,
    modelWaitMs: 0,
    reasoningMs: 0,
    outputMs: 0,
    toolExecutionMs: 0,
    modelCalls: 0,
    toolCalls: 0,
  );

  TimingSnapshot copyWith({
    int? wallMs,
    int? modelWaitMs,
    int? reasoningMs,
    int? outputMs,
    int? toolExecutionMs,
    int? modelCalls,
    int? toolCalls,
  }) =>
      TimingSnapshot(
        wallMs: wallMs ?? this.wallMs,
        modelWaitMs: modelWaitMs ?? this.modelWaitMs,
        reasoningMs: reasoningMs ?? this.reasoningMs,
        outputMs: outputMs ?? this.outputMs,
        toolExecutionMs: toolExecutionMs ?? this.toolExecutionMs,
        modelCalls: modelCalls ?? this.modelCalls,
        toolCalls: toolCalls ?? this.toolCalls,
      );
}

/// Accumulates provider usage across every model call in one Agent run.
class UsageAccumulator {
  int promptTokens = 0;
  int completionTokens = 0;
  int cachedTokens = 0;
  int cacheWriteTokens = 0;
  int reasoningTokens = 0;
  bool usageReported = false;
  bool cacheStatsReported = false;

  void add(Usage usage) {
    promptTokens += usage.promptTokens;
    completionTokens += usage.completionTokens;
    cachedTokens += usage.cachedTokens;
    cacheWriteTokens += usage.cacheWriteTokens;
    reasoningTokens += usage.reasoningTokens;
    usageReported = usageReported || usage.usageReported;
    cacheStatsReported = cacheStatsReported || usage.cacheStatsReported;
  }

  Usage get value => Usage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        cachedTokens: cachedTokens,
        cacheWriteTokens: cacheWriteTokens,
        reasoningTokens: reasoningTokens,
        usageReported: usageReported,
        cacheStatsReported: cacheStatsReported,
      );
}
