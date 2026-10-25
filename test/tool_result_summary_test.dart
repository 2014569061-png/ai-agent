// 工具消息摘要：结构化结果取 message，失败加前缀，其他文本取第一行。
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';

void main() {
  test('legacy error strings remain readable without exposing JSON', () {
    expect(toolResultSummary('{"ok":false,"error":"读取失败"}'), '失败：读取失败');
    expect(toolResultSummary('{"ok":false,"error":{"code":1}}'),
        '{"ok":false,"error":{"code":1}}');
  });
  test('成功的结构化结果显示 message', () {
    final raw = ToolResult.success(message: '已读取 lib/main.dart').encode();
    expect(toolResultSummary(raw), '已读取 lib/main.dart');
  });

  test('失败的结构化结果加「失败：」前缀', () {
    final raw =
        ToolResult.failure(code: 'not_found', message: '找不到文件').encode();
    expect(toolResultSummary(raw), '失败：找不到文件');
  });

  test('普通文本与非法 JSON 取第一行', () {
    expect(toolResultSummary('第一行\n第二行'), '第一行');
    expect(toolResultSummary('{不是 json\n第二行'), '{不是 json');
    expect(toolResultSummary('{"data":1}'), '{"data":1}');
  });
}
