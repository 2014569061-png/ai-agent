import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/agent_loop/output_token_policy.dart';
import 'package:mobile_agent/presentation/agents/agent_editor_page.dart';

void main() {
  test('auto shows the effective limit for the active model', () {
    final text = agentMaxTokensSubtitle(
      auto: true,
      manualTokens: 4096,
      activeModel: 'step-5-preview',
      activeContextTokens: 128000,
    );
    expect(text, startsWith('当前 step-5-preview（推理模型）：16384 Tokens'));
  });

  test('auto respects the half-window cap and normal models', () {
    expect(
      agentMaxTokensSubtitle(
          auto: true,
          manualTokens: 4096,
          activeModel: 'step-5-preview',
          activeContextTokens: 20000),
      startsWith('当前 step-5-preview（推理模型）：10000 Tokens'),
    );
    expect(
      agentMaxTokensSubtitle(
          auto: true,
          manualTokens: 4096,
          activeModel: 'gpt-4o',
          activeContextTokens: 128000),
      startsWith('当前 gpt-4o（普通模型）：${OutputTokenPolicy.standardDefault} Tokens'),
    );
  });

  test('without a configured model only the rule is shown', () {
    expect(agentMaxTokensSubtitle(auto: true, manualTokens: 4096),
        startsWith('推理模型 '));
  });

  test('manual small limit on a reasoning model warns about truncation', () {
    expect(
      agentMaxTokensSubtitle(
          auto: false, manualTokens: 4096, activeModel: 'step-3.7-flash'),
      contains('过小容易被截断'),
    );
    expect(
      agentMaxTokensSubtitle(
          auto: false, manualTokens: 16384, activeModel: 'step-3.7-flash'),
      '已关闭：使用下方的固定上限',
    );
  });
}
