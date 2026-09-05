import 'package:flutter/material.dart';

import '../../../application/chat_controller.dart';
import '../../../infrastructure/tools/tool_humanizer.dart';

/// 运行时工具横幅：运行中固定在输入区上方，高亮当前正在执行/等待确认的工具。
///
/// 相比收在「工具执行明细」折叠卡里，横幅让用户始终能看见 Agent 当前动线，
/// 尤其突出「等待确认」一步，符合安全代理「透明 + 可拦截」的核心体验。
class RuntimeToolBanner extends StatelessWidget {
  const RuntimeToolBanner({super.key, required this.activities});

  final List<ToolActivity> activities;

  static const _humanizer = ToolHumanizer();

  /// 找到当前活跃步骤：取第一个「执行中」，否则第一个「等待确认」，否则第一个「等待执行」。
  static (ToolActivity, int)? _current(List<ToolActivity> acts) {
    int pick(String status) => acts.indexWhere((a) => a.status == status);
    var idx = pick('执行中');
    if (idx < 0) idx = pick('等待确认');
    if (idx < 0) idx = pick('等待执行');
    if (idx < 0) return null;
    return (acts[idx], idx);
  }

  static (Color, IconData) _style(String status) => switch (status) {
        '执行中' => (const Color(0xFF2563EB), Icons.hourglass_top_rounded),
        '等待确认' => (const Color(0xFFF59E0B), Icons.gpp_maybe_outlined),
        _ => (const Color(0xFF64748B), Icons.settings_ethernet_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final current = _current(activities);
    final active = current;
    if (active == null) return const SizedBox.shrink();
    final (activity, index) = active;
    final (color, icon) = _style(activity.status);
    final sub = activities.where(
        (a) => a.status == '执行中' || a.status == '等待确认' || a.status == '等待执行');
    final total = activities.length;
    final summary = _humanizer.summaryOf(activity.call) ?? activity.call.name;
    final totalLabel = sub.isEmpty ? '$total' : '${sub.length}/$total';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        _Pulse(icon: icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 1),
              Text(
                '${activity.status} · 步骤 ${index + 1}/$totalLabel',
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.15),
            shape: BoxShape.circle),
        child: Icon(widget.icon, size: 17, color: widget.color),
      ),
    );
  }
}
