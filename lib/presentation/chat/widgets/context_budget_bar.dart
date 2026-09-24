import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/context_insights.dart';
import '../../theme/app_palette.dart';

class ContextBudgetSegment {
  const ContextBudgetSegment({required this.tokens, required this.color});

  final int tokens;
  final Color color;
}

/// Shared visualization for consumed input, reserved output and free capacity.
class ContextBudgetBar extends StatelessWidget {
  const ContextBudgetBar({
    super.key,
    required this.segments,
    required this.limit,
    this.reservedOutputTokens = 0,
    this.fallbackRatio = 0,
    this.fallbackColor = AppPalette.brand,
    this.height = 12,
  });

  factory ContextBudgetBar.fromParts({
    Key? key,
    required List<ContextPart> parts,
    required int limit,
    int reservedOutputTokens = 0,
    double fallbackRatio = 0,
    Color fallbackColor = AppPalette.brand,
    double height = 12,
  }) =>
      ContextBudgetBar(
        key: key,
        segments: [
          for (final part in parts)
            ContextBudgetSegment(
              tokens: part.tokens,
              color: contextPartColor(part.type),
            ),
        ],
        limit: limit,
        reservedOutputTokens: reservedOutputTokens,
        fallbackRatio: fallbackRatio,
        fallbackColor: fallbackColor,
        height: height,
      );

  final List<ContextBudgetSegment> segments;
  final int limit;
  final int reservedOutputTokens;
  final double fallbackRatio;
  final Color fallbackColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(
      0,
      (sum, segment) => sum + math.max(0, segment.tokens),
    );
    final reserved = math.max(
      0,
      math.min(reservedOutputTokens, math.max(0, limit - total)),
    );
    final remaining = math.max(0, limit - total - reserved);
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: height,
        child: total <= 0
            ? LinearProgressIndicator(
                value: fallbackRatio.clamp(0.0, 1.0),
                minHeight: height,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(fallbackColor),
              )
            : Row(children: [
                for (final segment in segments)
                  if (segment.tokens > 0)
                    Expanded(
                      flex: segment.tokens,
                      child: ColoredBox(color: segment.color),
                    ),
                if (reserved > 0)
                  Expanded(
                    flex: reserved,
                    child: Container(
                      key: const ValueKey('context-output-reserved-segment'),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                if (remaining > 0)
                  Expanded(
                    flex: remaining,
                    child: ColoredBox(color: scheme.surfaceContainerHighest),
                  ),
              ]),
      ),
    );
  }
}

Color contextPartColor(ContextPartType type) => switch (type) {
      ContextPartType.system => AppPalette.brand,
      ContextPartType.tools => AppPalette.warning,
      ContextPartType.inject => AppPalette.brand,
      ContextPartType.skill => AppPalette.warning,
      ContextPartType.user => AppPalette.success,
      ContextPartType.assistant => AppPalette.brand,
      ContextPartType.toolResult => AppPalette.success,
    };

Color contextBudgetColor(ContextBudgetLevel level) => switch (level) {
      ContextBudgetLevel.normal => AppPalette.brand,
      ContextBudgetLevel.attention => AppPalette.warning,
      ContextBudgetLevel.warning => AppPalette.warning,
      ContextBudgetLevel.critical => AppPalette.danger,
    };
