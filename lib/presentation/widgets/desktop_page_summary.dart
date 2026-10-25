import 'package:flutter/material.dart';
import '../theme/desktop_theme.dart';

/// 当前已加载数据的紧凑摘要；不推断全库总数或后台任务状态。
class DesktopPageSummary extends StatelessWidget {
  const DesktopPageSummary({super.key, required this.items});
  final List<({IconData icon, String label, String value})> items;

  @override
  Widget build(BuildContext context) {
    final colors = DesktopTheme.maybeOf(context);
    if (colors == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Wrap(spacing: 10, runSpacing: 8, children: [
        for (final item in items)
          Semantics(
              label: '${item.label}：${item.value}',
              excludeSemantics: true,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                    color: colors.panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.border)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(item.icon, size: 15, color: colors.accent),
                  const SizedBox(width: 7),
                  Text(item.label,
                      style: TextStyle(
                          fontSize: DesktopTheme.smallSize,
                          color: colors.muted)),
                  const SizedBox(width: 10),
                  Text(item.value,
                      style: TextStyle(
                          fontSize: DesktopTheme.labelSize,
                          fontWeight: FontWeight.w600,
                          color: colors.text)),
                ]),
              )),
      ]),
    );
  }
}
