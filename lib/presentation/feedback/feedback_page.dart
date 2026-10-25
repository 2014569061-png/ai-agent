import '../theme/mobile_theme.dart';
import 'package:flutter/material.dart';
import '../widgets/nexus_page_layout.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../theme/desktop_theme.dart';
import '../widgets/floating_toast.dart';
import '../widgets/nexus_dropdown.dart';
import '../widgets/nexus_page_header.dart';

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
    final theme = Theme.of(context);
    final desktop = DesktopTheme.maybeOf(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: MobileTheme.pageBackground(context),
      appBar: const NexusPageHeader(
        title: '意见反馈',
        subtitle: '问题反馈与改进建议',
      ),
      body: NexusPageLayout(
          desktopMaxWidth: 920,
          child: ListView(
              padding: EdgeInsets.all(desktop == null ? 20 : 16),
              children: [
                if (desktop != null)
                  Text('帮助我们改进 NEXUS',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('反馈将通过你的邮件客户端发送；发送前仍可检查和编辑。',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                NexusDropdown<String>(
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
                    minLines: 4,
                    maxLines: 8,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                        labelText: '问题描述',
                        hintText: '请描述问题、复现步骤或希望改进的体验。',
                        alignLabelWithHint: true)),
                const SizedBox(height: 12),
                TextField(
                    controller: _contact,
                    decoration: const InputDecoration(
                        labelText: '联系方式（选填）',
                        hintText: '邮箱或其他可联系的方式',
                        helperText: '仅用于跟进本次反馈，请勿填写密码或 API 密钥。')),
                const SizedBox(height: 24),
                FilledButton.icon(
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: MobileTheme.brand(context),
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      minimumSize: Size.fromHeight(
                          desktop == null ? AppTokens.kMinTouchTarget : 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            MobileTheme.controlRadius(context)),
                      ),
                    ),
                    onPressed: _submit,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('打开邮件草稿')),
                const SizedBox(height: 8),
                if (desktop != null)
                  Text('当前通过邮件客户端提交，无需注册账号。',
                      style: TextStyle(
                          fontSize: AppTokens.fontSizeCaption,
                          color: isDark
                              ? AppPalette.darkTextMuted
                              : AppPalette.lightTextMuted)),
              ])),
    );
  }
}
