/// Token 等数字的展示格式化工具。
///
/// 设计意图：用户要求「能看到具体的 token 数字」——因此这里提供两套格式：
/// - [formatExact]：千分位精确数字（如 12,483），用于需要阅读具体数值的场景；
/// - [formatCompact]：紧凑缩写（如 12.4k / 1.5M），用于需要控制宽度的标签。
/// 统一使用 tabular figures（等宽数字）以保证数字对齐、不抖动。
library;

/// 千分位精确格式：12345 -> "12,345"。
String formatExact(int value) {
  if (value == 0) return '0';
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  if (value < 0) return '-$buf';
  return buf.toString();
}

/// 紧凑缩写：< 1000 精确显示；>= 1000 显示 k；>= 1,000,000 显示 M。
/// 1,234 -> "1.2k"；12,345 -> "12.3k"；999 -> "999"。
String formatCompact(int value) {
  if (value >= 1000000) {
    final v = value / 1000000;
    return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    final v = value / 1000;
    return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}k';
  }
  return '$value';
}

/// 耗时标签：>= 1 分钟显示 "19m51s"；>= 1 秒显示 "14.4s"；否则 "820ms"。
///
/// 输入为 null 或非正数时返回 "--"，便于指标条统一处理缺失值。
String formatDurationLabel(Duration? d) {
  if (d == null) return '--';
  final ms = d.inMilliseconds;
  if (ms <= 0) return '0ms';
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final minutes = ms ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  return '${minutes}m${seconds}s';
}

/// 生成速率标签：53.4 -> "53 tok/s"；<= 0 -> "--"。
String formatRate(double tokensPerSecond) {
  if (tokensPerSecond <= 0 || !tokensPerSecond.isFinite) return '--';
  return '${tokensPerSecond.round()} tok/s';
}

/// 费用（分）→ 元展示：860 -> "8.60"；0 或 null -> null。
/// 与既有页面一致使用「分」作为存储单位，展示转为「元」更贴近直觉。
String? formatCostYuan(int? cents) {
  if (cents == null || cents <= 0) return null;
  return (cents / 100).toStringAsFixed(2);
}

/// 百分比（0-1）→ "23%"；null -> "--"。
String formatPercent(double? fraction) {
  if (fraction == null) return '--';
  return '${(fraction * 100).round()}%';
}