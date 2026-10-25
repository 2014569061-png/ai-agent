import 'package:flutter/material.dart';
import '../theme/desktop_theme.dart';

/// 保留原表单、滚动状态和保存逻辑；宽桌面追加只读配置摘要。
class DesktopEditorLayout extends StatelessWidget {
  const DesktopEditorLayout(
      {super.key,
      required this.child,
      required this.title,
      required this.icon,
      required this.status,
      required this.facts,
      required this.notes});
  final Widget child;
  final String title, status;
  final IconData icon;
  final List<({String label, String value})> facts;
  final List<String> notes;
  @override
  Widget build(BuildContext context) {
    final colors = DesktopTheme.maybeOf(context);
    if (colors == null) return child;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1100 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20;
      Widget summary() => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: colors.accent),
                        const SizedBox(height: 12),
                        Text(title,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Text(status, style: TextStyle(color: colors.accent)),
                        const SizedBox(height: 18),
                        for (final fact in facts)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(fact.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    const SizedBox(height: 4),
                                    Text(fact.value,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium),
                                  ])),
                        Divider(color: colors.border),
                        const SizedBox(height: 12),
                        for (final note in notes)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(note,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(height: 1.6))),
                      ]))));
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: child))),
        if (wide) SizedBox(width: 280, child: summary()),
      ]);
    });
  }
}
