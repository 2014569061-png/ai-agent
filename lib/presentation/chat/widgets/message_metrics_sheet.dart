import 'package:flutter/material.dart';
import '../../../domain/models.dart';
import '../../widgets/immersive_sheet.dart';

class MessageMetricsSheet extends StatelessWidget {
  final ChatMessage message;

  const MessageMetricsSheet({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = message.usage;
    final elapsed = message.elapsed;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, color: Color(0xFF1677FF)),
                const SizedBox(width: 8),
                Text('执行指标',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),
            _MetricRow(
              icon: Icons.model_training,
              title: '模型',
              value: message.modelName ?? '未知',
            ),
            const SizedBox(height: 12),
            _MetricRow(
              icon: Icons.timer_outlined,
              title: '总耗时',
              value: elapsed != null
                  ? '${(elapsed.inMilliseconds / 1000).toStringAsFixed(2)} s'
                  : '-',
            ),
            if (message.ttft != null) ...[
              const SizedBox(height: 12),
              _MetricRow(
                icon: Icons.flash_on_rounded,
                title: '首字时长 (TTFT)',
                value: '${message.ttft!.inMilliseconds} ms',
              ),
            ],
            if (usage != null &&
                elapsed != null &&
                usage.completionTokens > 0 &&
                elapsed.inMilliseconds > 0) ...[
              const SizedBox(height: 12),
              _MetricRow(
                icon: Icons.speed_rounded,
                title: '生成速率',
                value:
                    '${(usage.completionTokens / (elapsed.inMilliseconds / 1000)).toStringAsFixed(1)} t/s',
              ),
            ],
            if (usage != null) ...[
              const SizedBox(height: 12),
              _MetricRow(
                icon: Icons.data_usage,
                title: '总 Token',
                value: '${usage.totalTokens}',
              ),
              const SizedBox(height: 12),
              _MetricRow(
                icon: Icons.upload_rounded,
                title: '输入 (Prompt)',
                value: '${usage.promptTokens}',
              ),
              const SizedBox(height: 12),
              _MetricRow(
                icon: Icons.download_rounded,
                title: '输出 (Completion)',
                value: '${usage.completionTokens}',
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _MetricRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant, fontSize: 14)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'monospace')),
      ],
    );
  }
}

class MessageStatusPill extends StatelessWidget {
  final ChatMessage message;

  const MessageStatusPill({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final elapsed = message.elapsed;
    final usage = message.usage;
    final ttft = message.ttft;

    if (elapsed == null && usage == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final speed = (usage != null && elapsed != null && elapsed.inMilliseconds > 0)
        ? (usage.completionTokens / (elapsed.inMilliseconds / 1000))
        : 0.0;

    return GestureDetector(
      onTap: () {
        showImmersiveSheet(
          context: context,
          builder: (_) => MessageMetricsSheet(message: message),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.06)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.1)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            if (elapsed != null) ...[
              Icon(Icons.timer_outlined,
                  size: 13, color: theme.colorScheme.primary),
              Text(
                '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (ttft != null) ...[
              Text('·',
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.outline)),
              Text(
                '首字 ${ttft.inMilliseconds}ms',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (speed > 0) ...[
              Text('·',
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.outline)),
              Text(
                '${speed.toStringAsFixed(0)} t/s',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: const Color(0xFF10B981),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (usage != null && usage.totalTokens > 0) ...[
              Text('·',
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.outline)),
              Text(
                '${usage.totalTokens} tok',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
