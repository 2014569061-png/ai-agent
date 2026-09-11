import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

import '../../application/chat_controller.dart';
import '../../domain/models.dart';
import '../../infrastructure/tools/tool_humanizer.dart';
import 'immersive_surface.dart';

/// 工具调用卡片：工具名 + 风险徽章 + 状态点 + 可折叠参数/结果。
class ToolCallCard extends StatelessWidget {
  const ToolCallCard(
      {super.key, required this.activity, this.initiallyExpanded = false});

  final ToolActivity activity;
  final bool initiallyExpanded;

  static const _humanizer = ToolHumanizer();

  String? get _summary => _humanizer.summaryOf(activity.call);

  static (Color, String, IconData) _riskStyle(ToolRisk risk) => switch (risk) {
        ToolRisk.safe => (AppPalette.success, '安全', Icons.shield_outlined),
        ToolRisk.requiresConfirmation => (
            AppPalette.warning,
            '需确认',
            Icons.shield_outlined
          ),
        ToolRisk.dangerous => (
            AppPalette.danger,
            '危险',
            Icons.warning_amber_rounded
          ),
      };

  static (Color, bool) _statusStyle(String status) => switch (status) {
        '执行中' => (AppPalette.brand, true),
        '等待确认' => (AppPalette.warning, true),
        '已完成' => (AppPalette.success, false),
        '执行失败' => (AppPalette.danger, false),
        _ => (AppPalette.lightTextMuted, false),
      };

  String _prettyJson(Map<String, dynamic> value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightText;

    final (riskColor, riskLabel, riskIcon) = _riskStyle(activity.risk);
    final (statusColor, pulsing) = _statusStyle(activity.status);
    final waiting = activity.status == '等待确认';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: ImmersiveSurface(
        level: ImmersiveMaterialLevel.regular,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: waiting ? AppPalette.warning : hairline),
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          ),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                border: Border.all(color: hairline, width: 1.0),
              ),
              child: Icon(Icons.handyman_outlined, size: 16, color: riskColor),
            ),
            title: Text(
              activity.call.name,
              style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  fontSize: 13),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _RiskBadge(
                      color: riskColor, label: riskLabel, icon: riskIcon),
                  const SizedBox(width: 8),
                  pulsing
                      ? _PulseDot(color: statusColor)
                      : Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(
                    activity.status,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              if (_summary != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _summary!,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: textMuted),
                  ),
                ),
                Divider(height: 16, color: hairline),
              ],
              _JsonSection(
                  label: '参数', content: _prettyJson(activity.call.arguments)),
              if (activity.result != null) ...[
                const SizedBox(height: 8),
                _JsonSection(label: '结果', content: activity.result!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge(
      {required this.color, required this.label, required this.icon});
  final Color color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _JsonSection extends StatelessWidget {
  const _JsonSection({required this.label, required this.content});
  final String label;
  final String content;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? AppPalette.darkTextMuted : AppPalette.lightTextMuted;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final hairline =
        isDark ? AppPalette.darkHairline : AppPalette.lightHairline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11, color: textMuted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 200),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            border: Border.all(color: hairline, width: 1.0),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 12,
                  color: textMuted,
                  height: 1.45),
            ),
          ),
        ),
      ],
    );
  }
}

/// 状态指示点
class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
