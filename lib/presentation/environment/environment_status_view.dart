import 'package:flutter/material.dart';

import '../../application/environment_service.dart';
import '../../infrastructure/terminal/linux_runtime.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../widgets/section_card.dart';

class EnvironmentStatusView extends StatelessWidget {
  const EnvironmentStatusView({
    super.key,
    required this.snapshot,
    this.compact = false,
  });

  final EnvironmentSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidates = snapshot.inspectedCandidates;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxChipWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(snapshot.scenarioLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${snapshot.selected.label} · ${snapshot.architecture}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text('运行时候选', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final candidate in candidates)
                  _chip(
                    '${_kindLabel(candidate.runtime.kind)} · '
                    '${candidate.runtime.available ? '可用' : '不可用'}',
                    candidate.runtime.available
                        ? AppPalette.success
                        : AppPalette.warning,
                    maxWidth: maxChipWidth,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('全局能力（任一可用运行时）', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                  '完整 Shell · ${snapshot.shellAvailable ? '可用' : '缺失'}',
                  snapshot.shellAvailable
                      ? AppPalette.success
                      : AppPalette.danger,
                  maxWidth: maxChipWidth,
                ),
                _chip(
                  '交互式终端 · '
                  '${snapshot.interactiveAvailable ? '可用' : '缺失'}',
                  snapshot.interactiveAvailable
                      ? AppPalette.success
                      : AppPalette.danger,
                  maxWidth: maxChipWidth,
                ),
                _chip(
                  '实时日志 · ${snapshot.liveOutputAvailable ? '可用' : '缺失'}',
                  snapshot.liveOutputAvailable
                      ? AppPalette.success
                      : AppPalette.danger,
                  maxWidth: maxChipWidth,
                ),
              ],
            ),
            if (snapshot.tools.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('工具探测（当前运行时：${snapshot.selected.label}）',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tool in snapshot.tools)
                    _toolChip(tool, maxWidth: maxChipWidth),
                ],
              ),
            ],
            if (!compact)
              for (final candidate in candidates)
                if (candidate.runtime.available && candidate.tools.isNotEmpty)
                  _candidateTools(
                    candidate,
                    theme,
                    maxWidth: maxChipWidth,
                    isSelected:
                        candidate.runtime.kind == snapshot.selected.kind,
                  ),
            const SizedBox(height: 10),
            Text('全局缺失（所有可用运行时）', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: snapshot.missingCapabilities.isEmpty
                  ? [
                      _chip('无', AppPalette.success, maxWidth: maxChipWidth),
                    ]
                  : [
                      for (final capability in snapshot.missingCapabilities)
                        _chip(
                          '缺失 · $capability',
                          AppPalette.danger,
                          maxWidth: maxChipWidth,
                        ),
                    ],
            ),
            if (!compact) ...[
              const SizedBox(height: AppTokens.sp4),
              Text(snapshot.selected.detail, style: theme.textTheme.bodySmall),
              if (snapshot.templates.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('模板匹配', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final match in snapshot.templates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      match.ready
                          ? '${match.label} 可运行'
                          : '${match.label}：${match.blockedReason}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ],
          ],
        );
      },
    );
  }

  String _kindLabel(LinuxRuntimeKind kind) => switch (kind) {
        LinuxRuntimeKind.builtinProot => 'Alpine',
        LinuxRuntimeKind.termux => 'Termux',
        LinuxRuntimeKind.androidShell => 'Android Shell',
        LinuxRuntimeKind.hostProcess => '本机进程',
      };

  Widget _toolChip(
    EnvironmentToolStatus tool, {
    required double maxWidth,
  }) {
    final state = !tool.probed
        ? '未探测'
        : tool.available
            ? '可用'
            : '缺失';
    final color = !tool.probed
        ? AppPalette.warning
        : tool.available
            ? AppPalette.success
            : tool.required
                ? AppPalette.danger
                : AppPalette.warning;
    return _chip(
      '${tool.label} · $state',
      color,
      maxWidth: maxWidth,
    );
  }

  Widget _candidateTools(
    EnvironmentCandidateStatus candidate,
    ThemeData theme, {
    required double maxWidth,
    required bool isSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '工具探测 · ${candidate.runtime.label}'
            '${isSelected ? '（当前）' : ''}',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tool in candidate.tools)
                _toolChip(tool, maxWidth: maxWidth),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label,
    Color color, {
    double? maxWidth,
  }) {
    final text = Text(
      label,
      softWrap: true,
      style: TextStyle(color: color, fontSize: 12),
    );
    return Container(
      constraints: maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      ),
      child: text,
    );
  }
}

class EnvironmentStatusCard extends StatelessWidget {
  const EnvironmentStatusCard({super.key, required this.snapshot});

  final EnvironmentSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: EnvironmentStatusView(snapshot: snapshot),
    );
  }
}
