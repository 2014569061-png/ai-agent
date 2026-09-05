import 'package:flutter/material.dart';

import '../../application/onboarding_service.dart';
import '../../infrastructure/observability/sentry_service.dart';
import '../chat/chat_page.dart';
import '../l10n/app_strings.dart';
import '../settings/settings_page.dart';
import '../widgets/section_card.dart';

/// 首次启动的 4 步引导：填 Key / 选模型 / 用工具 / 隐私（含崩溃上报授权）。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;
  bool _crashReport = false;

  static const _steps = [
    (
      Icons.key_outlined,
      '填入模型服务',
      '在「设置 → 模型连接」里填入你的 API Key，或用本地模型（Ollama）免 Key 直连。'
    ),
    (
      Icons.tune,
      '选择你的模型',
      '一个 App 接入 OpenAI / Claude / Gemini / DeepSeek / Ollama，配置一次长期复用。'
    ),
    (
      Icons.handyman_outlined,
      '让 Agent 用工具',
      '计算、查时间、联网搜索、HTTP 请求……每一步有副作用的操作都会弹窗请你审批。'
    ),
    (
      Icons.shield_outlined,
      '隐私，本地优先',
      'API Key 只存本机加密存储，聊天记录只存本机数据库，卸载即清空，无云端残留。'
    ),
  ];

  Future<void> _finish() async {
    await SentryService.setEnabled(_crashReport);
    await OnboardingService.markDone();
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const ChatPage()));
  }

  void _next() {
    if (_index < _steps.length - 1) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _finish,
              child: const Text(AppStrings.skip),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _steps.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final (ic, t, d) = _steps[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(28)),
                          child: Icon(ic, color: Colors.white, size: 44),
                        ),
                        const SizedBox(height: 28),
                        Text(t,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Text(d,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.5)),
                        if (i == 0) ...[
                          const SizedBox(height: 20),
                          FilledButton.tonal(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const SettingsPage())),
                            child: const Text('去配置模型'),
                          ),
                        ],
                        if (i == _steps.length - 1) ...[
                          const SizedBox(height: 24),
                          SectionCard(
                            child: SwitchListTile(
                              secondary: const Icon(Icons.bug_report_outlined),
                              title: const Text(AppStrings.crashReport),
                              subtitle: const Text(AppStrings.crashReportHint),
                              value: _crashReport,
                              onChanged: (v) =>
                                  setState(() => _crashReport = v),
                            ),
                          ),
                        ],
                      ]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    _steps.length,
                    (i) => Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _index
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant),
                        )),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_index == _steps.length - 1
                      ? AppStrings.startUsing
                      : '下一步'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
