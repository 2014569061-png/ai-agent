import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';

void main() {
  test('encode 返回稳定的结构化 JSON', () {
    final result = ToolResult.success(
      message: '已完成',
      data: {'count': 2},
      effect: ToolEffect.applied,
    );

    final json = jsonDecode(result.encode()) as Map<String, dynamic>;

    expect(json, {
      'ok': true,
      'code': ToolCodes.ok,
      'message': '已完成',
      'effect': 'applied',
      'data': {'count': 2},
    });
  });

  test('effect 为 none 时 encode 省略 effect 字段', () {
    final result = ToolResult.success(message: '只读完成');

    final json = jsonDecode(result.encode()) as Map<String, dynamic>;

    expect(json['ok'], isTrue);
    expect(json['code'], ToolCodes.ok);
    expect(json.containsKey('effect'), isFalse);
  });

  test('display 只返回短摘要，完整文本保留在 data.text', () {
    final result = ToolResult.text('第一行摘要\n第二行详细内容');

    expect(result.display, '第一行摘要');
    expect(result.message, '第一行摘要');
    expect(result.data?['text'], '第一行摘要\n第二行详细内容');
  });
}
