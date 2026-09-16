class TaskSummary {
  const TaskSummary({
    required this.version,
    required this.goal,
    this.acceptance = const [],
    this.modifiedFiles = const [],
    this.passedChecks = const [],
    this.openIssues = const [],
    this.evidence = const [],
    this.runId,
    this.eventSequence,
    this.fileVersions = const {},
    this.staleChecks = const [],
  });

  final int version;
  final String goal;
  final List<String> acceptance;
  final List<String> modifiedFiles;
  final List<String> passedChecks;
  final List<String> openIssues;
  final List<String> evidence;
  final String? runId;
  final int? eventSequence;
  final Map<String, String> fileVersions;
  final List<String> staleChecks;

  Map<String, dynamic> toJson() => {
        'version': version,
        'goal': goal,
        'acceptance': acceptance,
        'modifiedFiles': modifiedFiles,
        'passedChecks': passedChecks,
        'openIssues': openIssues,
        'evidence': evidence,
        if (runId != null) 'runId': runId,
        if (eventSequence != null) 'eventSequence': eventSequence,
        'fileVersions': fileVersions,
        'staleChecks': staleChecks,
      };

  factory TaskSummary.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic value) => value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : const [];
    final versions = json['fileVersions'];
    return TaskSummary(
      version: (json['version'] as num?)?.toInt() ?? 1,
      goal: json['goal']?.toString() ?? '',
      acceptance: strings(json['acceptance']),
      modifiedFiles: strings(json['modifiedFiles']),
      passedChecks: strings(json['passedChecks']),
      openIssues: strings(json['openIssues']),
      evidence: strings(json['evidence']),
      runId: json['runId']?.toString(),
      eventSequence: (json['eventSequence'] as num?)?.toInt(),
      fileVersions: versions is Map
          ? versions
              .map((key, value) => MapEntry(key.toString(), value.toString()))
          : const {},
      staleChecks: strings(json['staleChecks']),
    );
  }

  TaskSummary markStale(Iterable<String> checks) {
    final next = {...staleChecks, ...checks}.toList(growable: false);
    return TaskSummary(
      version: version,
      goal: goal,
      acceptance: acceptance,
      modifiedFiles: modifiedFiles,
      passedChecks: passedChecks,
      openIssues: openIssues,
      evidence: evidence,
      runId: runId,
      eventSequence: eventSequence,
      fileVersions: fileVersions,
      staleChecks: next,
    );
  }

  String toPromptBlock() {
    final buffer = StringBuffer('- 任务摘要 v$version');
    if (runId != null) buffer.write('（依据 runId=$runId');
    if (eventSequence != null) buffer.write(' #$eventSequence');
    if (runId != null) buffer.write('）');
    buffer.writeln();
    if (goal.isNotEmpty) buffer.writeln('  · 目标：$goal');
    if (acceptance.isNotEmpty) {
      buffer.writeln('  · 验收条件：${acceptance.join('；')}');
    }
    if (modifiedFiles.isNotEmpty) {
      buffer.writeln('  · 已修改文件：${modifiedFiles.join('、')}');
    }
    if (passedChecks.isNotEmpty) {
      buffer.writeln('  · 已通过检查：${passedChecks.join('、')}');
    }
    if (staleChecks.isNotEmpty) {
      buffer.writeln('  · 代码变化后失效的检查：${staleChecks.join('、')}');
    }
    if (openIssues.isNotEmpty) {
      buffer.writeln('  · 未解决问题：${openIssues.join('、')}');
    }
    if (evidence.isNotEmpty) {
      buffer.writeln('  · 证据：${evidence.join('、')}');
    }
    buffer.writeln('  · 注意：计划执行不得写成已执行。');
    return buffer.toString().trimRight();
  }
}
