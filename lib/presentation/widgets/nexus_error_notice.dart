import 'package:flutter/material.dart';

import 'nexus_disclosure.dart';
import 'section_card.dart';

/// A local failure keeps the surrounding content and offers a useful next step.
class NexusErrorNotice extends StatelessWidget {
  const NexusErrorNotice({
    super.key,
    required this.title,
    required this.message,
    this.details,
    this.onRetry,
    this.retryLabel = '重试',
  });

  final String title;
  final String message;
  final String? details;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.error_outline_rounded, color: colors.error, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(message,
              style: TextStyle(
                  fontSize: 14, height: 1.55, color: colors.onSurfaceVariant)),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(retryLabel)),
            ),
          if (details?.isNotEmpty ?? false)
            NexusDisclosure(
              title: Text('诊断详情',
                  style:
                      TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
              headerPadding: const EdgeInsets.symmetric(vertical: 12),
              contentPadding: EdgeInsets.zero,
              child: SelectableText(details!,
                  style: const TextStyle(fontSize: 12, height: 1.5)),
            ),
        ],
      ),
    );
  }
}
