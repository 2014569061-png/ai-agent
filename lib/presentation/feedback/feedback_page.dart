import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/floating_toast.dart';
import '../widgets/immersive_dropdown.dart';

/// 应用内反馈渠道（F6）：内置表单 + mailto 兜底（无后端时）。
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _type = TextEditingController(text: '功能建议');
  final _description = TextEditingController();
  final _contact = TextEditingController();

  @override
  void dispose() {
    _type.dispose();
    _description.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_description.text.trim().isEmpty) {
      FloatingToast.show(context, '请填写问题描述');
      return;
    }
    final subject = '【NEXUS 反馈】${_type.text}';
    final body =
        '类型：${_type.text}\n描述：${_description.text}\n联系方式：${_contact.text}';
    final uri = Uri(
      scheme: 'mailto',
      path: 'feedback@nexusagent.app',
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    try {
      final ok = await launchUrl(uri);
      if (!mounted) return;
      FloatingToast.show(context, ok ? '已打开邮件客户端，请发送' : '无法打开邮件客户端');
    } catch (_) {
      if (mounted) FloatingToast.show(context, '提交失败，请稍后再试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('意见反馈')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ImmersiveDropdown<String>(
          labelText: '问题类型',
          initialValue: _type.text,
          items: const [
            DropdownMenuItem(value: '功能建议', child: Text('功能建议')),
            DropdownMenuItem(value: 'Bug 反馈', child: Text('Bug 反馈')),
            DropdownMenuItem(value: '体验问题', child: Text('体验问题')),
            DropdownMenuItem(value: '其他', child: Text('其他')),
          ],
          onChanged: (v) => setState(() => _type.text = v ?? '功能建议'),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: _description,
            maxLines: 6,
            decoration: const InputDecoration(
                labelText: '问题描述', alignLabelWithHint: true)),
        const SizedBox(height: 12),
        TextField(
            controller: _contact,
            decoration: const InputDecoration(labelText: '联系方式（选填，便于跟进）')),
        const SizedBox(height: 20),
        FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send_outlined),
            label: const Text('提交反馈')),
        const SizedBox(height: 8),
        const Text('当前通过邮件客户端提交，无需注册账号。',
            style: TextStyle(fontSize: 12, color: Color(0xFF627D98))),
      ]),
    );
  }
}
