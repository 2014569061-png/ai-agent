import 'task_summary.dart';
import 'development_verification.dart';

class VerificationRepairRequest {
  const VerificationRepairRequest({
    required this.command,
    required this.cwd,
    required this.exitCode,
    required this.logExcerpt,
    this.relatedFiles = const [],
    this.diff = '',
    this.acceptance = const [],
    this.attempt = 1,
    this.maxAttempts = 2,
    this.reason = 'test_failed',
  });

  final String command;
  final String cwd;
  final int exitCode;
  final String logExcerpt;
  final List<String> relatedFiles;
  final String diff;
  final List<String> acceptance;
  final int attempt;
  final int maxAttempts;
  final String reason;
}

class VerificationRepairService {
  const VerificationRepairService();

  static const maxAutoAttempts = 2;

  VerificationRepairRequest? fromFailedPlan({
    required DevelopmentVerificationPlan plan,
    required String workspacePath,
    TaskSummary? summary,
    String diff = '',
    int attempt = 1,
  }) {
    final failed = plan.steps
        .where((step) => step.status == VerificationStepStatus.failed)
        .toList(growable: false);
    if (failed.isEmpty) return null;
    final step = failed.first;
    return VerificationRepairRequest(
      command: step.command.isEmpty ? step.title : step.command,
      cwd: workspacePath,
      exitCode: step.exitCode ?? 1,
      logExcerpt: _clip(step.output.isEmpty ? (step.error ?? '') : step.output),
      relatedFiles: summary?.modifiedFiles ?? const [],
      diff: diff,
      acceptance: summary?.acceptance ?? const [],
      attempt: attempt,
      reason: _reasonFor(step),
    );
  }

  bool canAutoRetry(VerificationRepairRequest request) {
    if (request.attempt >= request.maxAttempts) return false;
    return request.reason == 'test_failed';
  }

  String promptFor(VerificationRepairRequest request) {
    final buffer = StringBuffer('根据这次错误继续修复。\n');
    buffer.writeln('命令：${request.command}');
    buffer.writeln('工作目录：${request.cwd}');
    buffer.writeln('退出码：${request.exitCode}');
    buffer.writeln('原因分类：${request.reason}');
    if (request.acceptance.isNotEmpty) {
      buffer.writeln('验收条件：${request.acceptance.join('；')}');
    }
    if (request.relatedFiles.isNotEmpty) {
      buffer.writeln('关联文件：${request.relatedFiles.join('、')}');
    }
    if (request.diff.trim().isNotEmpty) {
      buffer.writeln('当前差异：\n${_clip(request.diff, 1600)}');
    }
    buffer.writeln('失败日志：\n${request.logExcerpt}');
    if (request.reason == 'permission_denied') {
      buffer.writeln('不要绕过用户授权，也不要扩大权限。');
    }
    if (request.reason == 'environment_missing') {
      buffer.writeln('不要反复安装同一缺失项；说明缺少的工具并停止自动重试。');
    }
    if (!canAutoRetry(request)) {
      buffer.writeln(
          '自动修复已达 ${request.maxAttempts} 次上限，请给出下一步建议而不是继续重跑。');
    }
    return buffer.toString().trim();
  }

  String _reasonFor(VerificationStep step) {
    final haystack = '${step.error ?? ''} ${step.output}'.toLowerCase();
    if (haystack.contains('permission') ||
        haystack.contains('eacces') ||
        haystack.contains('denied')) {
      return 'permission_denied';
    }
    if (haystack.contains('not found') ||
        haystack.contains('no such file') ||
        haystack.contains('command not found') ||
        haystack.contains('missing')) {
      return 'environment_missing';
    }
    return 'test_failed';
  }

  String _clip(String text, [int maxChars = 1200]) {
    final trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(trimmed.length - maxChars)}\n…[日志已截取尾部]';
  }
}
