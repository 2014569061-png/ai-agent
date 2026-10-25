import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/context_window.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result_truncation.dart';
import 'package:mobile_agent/infrastructure/tools/parallel_sub_agents_tool.dart';
import 'package:mobile_agent/infrastructure/tools/sub_agent_tool.dart';

void main() {
  test('纯截断函数与 ContextWindow 兼容且保留 Unicode 边界', () {
    for (final text in ['', 'short', 'START${'😀' * 100}BUILD FAILED']) {
      for (final limit in [-1, 0, 1, 2, 7, 40, 500]) {
        final result = ToolResultTruncation.truncate(text, limit);
        expect(result, ContextWindow.truncateToolResult(text, limit));
        expect(utf8.decode(utf8.encode(result)), result);
      }
    }
    expect(ToolResultTruncation.truncate('START${'😀' * 100}BUILD FAILED', 40),
        allOf(startsWith('START'), endsWith('BUILD FAILED'), contains('中间省略')));
  });

  test('并行子任务保留逐项状态、预算、部分摘要和截断行为', () async {
    final received = <int?>[];
    final output = 'START${'😀' * 2500}BUILD FAILED';
    final tool = ParallelSubAgentsTool(onRun: (_, prompt, budget) async {
      received.add(budget);
      if (prompt == 'paused') {
        throw SubAgentFailure(ToolCodes.tokenBudgetExhausted,
            partialText: output, inputTokens: 100, outputTokens: 50);
      }
      return output;
    });
    final result = await tool.execute({
      'tasks': [
        {'id': 'ok', 'prompt': 'ok', 'maxTokens': 500},
        {'id': 'paused', 'prompt': 'paused', 'maxTokens': 1000},
      ]
    });
    expect(received, unorderedEquals([500, 1000]));
    expect(result.ok, isFalse);
    expect(result.data!['allocatedBudget'], 1500);
    expect(result.data!['totalTokenBudget'], 6000);
    final jobs = result.data!['results'] as List;
    expect(jobs[0]['ok'], isTrue);
    expect(jobs[1]['code'], ToolCodes.tokenBudgetExhausted);
    expect(jobs[1]['inputTokens'], 100);
    expect(jobs[1]['outputTokens'], 50);
    for (final job in jobs) {
      expect(job['truncated'], isTrue);
      expect(job['summary'], ToolResultTruncation.truncate(output, 3500));
      expect(
          utf8.decode(utf8.encode(job['summary'] as String)), job['summary']);
    }
  });
}
