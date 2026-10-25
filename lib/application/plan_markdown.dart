import '../domain/models.dart';

/// 计划 Markdown 与 PlanStep 列表的双向转换（Plan Mode 可编辑计划）。
///
/// 解析时支持「1. 步骤」「1、步骤」「- 步骤」「* 步骤」「- [ ] 步骤」，
/// 空行与「目标：…」这类说明行忽略；没有任何可识别行时返回空列表。

/// 把用户编辑的计划文本解析为步骤列表。
List<PlanStep> parsePlanStepsFromMarkdown(String markdown) {
  final steps = <PlanStep>[];
  for (final raw in markdown.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final numbered = RegExp(r'^\d+\s*[.、)）]\s*(.+)$').firstMatch(line);
    String? text;
    if (numbered != null) {
      text = numbered.group(1)!.trim();
    } else {
      final bullet =
          RegExp(r'^[-*•]\s*(?:\[[ xX]?\]\s*)?(.+)$').firstMatch(line);
      if (bullet != null) text = bullet.group(1)!.trim();
    }
    if (text == null || text.isEmpty) continue;
    steps.add(PlanStep(id: 's${steps.length + 1}', description: text));
  }
  return steps;
}

/// 把当前计划渲染为可编辑 Markdown：可选目标行 + 编号步骤。
String planStepsToMarkdown({String? goal, required List<PlanStep> steps}) {
  final buffer = StringBuffer();
  final trimmedGoal = goal?.trim();
  if (trimmedGoal != null && trimmedGoal.isNotEmpty) {
    buffer.writeln('目标：$trimmedGoal');
    buffer.writeln();
  }
  for (var i = 0; i < steps.length; i++) {
    buffer.writeln('${i + 1}. ${steps[i].description}');
  }
  return buffer.toString().trimRight();
}
