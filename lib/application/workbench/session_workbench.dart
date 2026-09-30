import '../../domain/models.dart';
import '../chat_controller.dart' show ToolActivity;

/// 会话工作台（阶段 7c）：把一次会话投影成「文件 / 结果 / 运行状态」三个视图。
///
/// 纯函数投影，只读 [ChatMessage] 与 [ToolActivity]，不改任何底层状态。
/// 输入与会话日志的 `deriveMessages()` 同形，将来切换到日志读取时这里不用动。

/// 文件在本会话里经历的最终变化。
///
/// [written]：`write_file` 写入了一个本会话之前没碰过的文件——工具活动里只有
/// 显示文本，分不清是新建还是覆盖，所以不冒充「新建」。
/// [created]：移动操作的目标路径，确定是本会话新出现的。
/// [attempted]：只有待确认、执行中或失败的调用，没有任何成功的读写。
enum WorkbenchFileChange {
  written,
  created,
  modified,
  deleted,
  moved,
  read,
  attempted,
}

class WorkbenchFile {
  const WorkbenchFile({
    required this.path,
    required this.change,
    required this.writes,
    required this.reads,
    required this.failures,
    required this.lastTool,
    required this.lastIndex,
    this.movedTo,
  });

  /// 工作区相对路径。
  final String path;
  final WorkbenchFileChange change;

  /// 成功的写入次数（新建、修改、删除、移动都算）。
  final int writes;
  final int reads;

  /// 针对这个文件失败的调用次数。
  final int failures;
  final String lastTool;

  /// 最后一次相关调用在 activities 中的位置，用于按新近排序。
  final int lastIndex;

  /// [WorkbenchFileChange.moved] 时的新路径。
  final String? movedTo;

  bool get changed =>
      change != WorkbenchFileChange.read &&
      change != WorkbenchFileChange.attempted;
}

/// 一轮对话的结果：用户提问 + 最终回答。
class WorkbenchTurn {
  const WorkbenchTurn({
    required this.index,
    required this.prompt,
    required this.answer,
  });

  /// 从 1 开始的轮次。
  final int index;
  final String prompt;

  /// 本轮最后一条非空助手回答；还没有回答时为 null。
  final String? answer;
}

class WorkbenchStatus {
  const WorkbenchStatus({
    required this.running,
    required this.paused,
    required this.stageLabel,
    required this.toolCalls,
    required this.pendingApprovals,
    required this.failedTools,
    required this.changedFiles,
    required this.turns,
  });

  final bool running;
  final bool paused;

  /// 当前运行阶段的文字说明；空闲时为 null。
  final String? stageLabel;
  final int toolCalls;
  final int pendingApprovals;
  final int failedTools;
  final int changedFiles;
  final int turns;
}

class SessionWorkbench {
  const SessionWorkbench({
    required this.files,
    required this.turns,
    required this.status,
  });

  /// 改动过的文件在前（按新近），其后是未改动的文件（按新近）。
  final List<WorkbenchFile> files;

  /// 最新一轮在前。
  final List<WorkbenchTurn> turns;
  final WorkbenchStatus status;

  static const pendingApprovalStatus = '等待确认';
  static const runningStatus = '执行中';
  static const failedStatus = '执行失败';
  static const completedStatus = '已完成';

  static SessionWorkbench project({
    required List<ChatMessage> messages,
    required List<ToolActivity> activities,
    bool running = false,
    bool paused = false,
    ChatRunProgress? runProgress,
    ToolTraits Function(String toolName)? traitsFor,
  }) {
    final resolve = traitsFor ?? builtInTraits;
    final files = projectFiles(activities, resolve);
    final turns = projectTurns(messages);
    return SessionWorkbench(
      files: files,
      turns: turns,
      status: WorkbenchStatus(
        running: running,
        paused: paused,
        stageLabel: running || paused ? runProgress?.label : null,
        toolCalls: activities.length,
        pendingApprovals:
            activities.where((a) => a.status == pendingApprovalStatus).length,
        failedTools: activities.where(isFailed).length,
        changedFiles: files.where((f) => f.changed).length,
        turns: turns.length,
      ),
    );
  }

  static bool isFailed(ToolActivity activity) =>
      activity.status == failedStatus || activity.ok == false;

  static bool isSucceeded(ToolActivity activity) =>
      !isFailed(activity) &&
      (activity.ok == true || activity.status == completedStatus);

  /// 没有声明特征时的兜底：内置文件工具与旧的 `*_file` 命名规则。
  static ToolTraits builtInTraits(String name) {
    switch (name) {
      case 'read_file':
        return ToolTraits.workspaceRead;
      case 'write_file':
      case 'edit_file':
      case 'delete_file':
        return ToolTraits.workspaceWrite;
      case 'move_file':
        return const ToolTraits(
          readOnly: false,
          scopes: {ToolEffectScope.workspace},
          pathArguments: ['path', 'newPath'],
          fileOperation: true,
        );
    }
    if (name.endsWith('_file')) {
      return ToolTraits(
        readOnly: name.startsWith('read_') || name.startsWith('view_'),
        scopes: const {ToolEffectScope.workspace},
        pathArguments: const ['path'],
        fileOperation: true,
      );
    }
    return ToolTraits.undeclared;
  }

  static List<WorkbenchFile> projectFiles(
    List<ToolActivity> activities,
    ToolTraits Function(String toolName) traitsFor,
  ) {
    final byPath = <String, _FileAcc>{};
    _FileAcc acc(String path) => byPath.putIfAbsent(path, () => _FileAcc(path));

    for (var i = 0; i < activities.length; i++) {
      final activity = activities[i];
      final call = activity.call;
      final traits = traitsFor(call.name);
      if (!traits.fileOperation || traits.pathArguments.isEmpty) continue;
      final paths = [
        for (final argument in traits.pathArguments)
          if (_pathOf(call.arguments[argument]) case final path?) path,
      ];
      if (paths.isEmpty) continue;

      final failed = isFailed(activity);
      final succeeded = isSucceeded(activity);
      for (final path in paths) {
        final entry = acc(path)
          ..lastTool = call.name
          ..lastIndex = i;
        if (failed) entry.failures++;
      }
      if (!succeeded) continue;

      if (traits.readOnly) {
        for (final path in paths) {
          acc(path).reads++;
        }
        continue;
      }
      if (call.name == 'move_file' && paths.length >= 2) {
        acc(paths[0]).write(WorkbenchFileChange.moved, movedTo: paths[1]);
        acc(paths[1]).write(WorkbenchFileChange.created);
        continue;
      }
      final change = switch (call.name) {
        'delete_file' => WorkbenchFileChange.deleted,
        'write_file' => byPath[paths.first]!.untouched
            ? WorkbenchFileChange.written
            : WorkbenchFileChange.modified,
        _ => WorkbenchFileChange.modified,
      };
      for (final path in paths) {
        acc(path).write(change);
      }
    }

    final all = byPath.values.map((a) => a.build()).toList()
      ..sort((a, b) {
        if (a.changed != b.changed) return a.changed ? -1 : 1;
        return b.lastIndex.compareTo(a.lastIndex);
      });
    return all;
  }

  static List<WorkbenchTurn> projectTurns(List<ChatMessage> messages) {
    final turns = <WorkbenchTurn>[];
    String? prompt;
    String? answer;
    void flush() {
      final current = prompt;
      if (current == null) return;
      turns.add(WorkbenchTurn(
          index: turns.length + 1, prompt: current, answer: answer));
    }

    for (final message in messages) {
      switch (message.role) {
        case MessageRole.user:
          flush();
          prompt = message.text.trim();
          answer = null;
        case MessageRole.assistant:
          final text = message.text.trim();
          if (prompt != null && text.isNotEmpty) answer = text;
        case MessageRole.system:
        case MessageRole.tool:
          break;
      }
    }
    flush();
    return turns.reversed.toList();
  }

  static String? _pathOf(Object? value) {
    if (value is! String) return null;
    final path = value.trim().replaceAll('\\', '/');
    if (path.isEmpty) return null;
    return path.startsWith('./') ? path.substring(2) : path;
  }
}

class _FileAcc {
  _FileAcc(this.path);

  final String path;
  WorkbenchFileChange? change;
  String? movedTo;
  int writes = 0;
  int reads = 0;
  int failures = 0;
  String lastTool = '';
  int lastIndex = -1;

  /// 本会话之前没有任何成功的读写。
  bool get untouched => change == null && reads == 0;

  void write(WorkbenchFileChange next, {String? movedTo}) {
    writes++;
    final previous = change;
    // 新写入的文件之后再改，仍保留最初的标记；之后删除则算「删除」。
    if ((previous == WorkbenchFileChange.created ||
            previous == WorkbenchFileChange.written) &&
        next == WorkbenchFileChange.modified) {
      return;
    }
    // 删除或移走后又写回来，算作修改（文件原本就存在）。
    if ((previous == WorkbenchFileChange.deleted ||
            previous == WorkbenchFileChange.moved) &&
        (next == WorkbenchFileChange.created ||
            next == WorkbenchFileChange.written)) {
      change = WorkbenchFileChange.modified;
      this.movedTo = null;
      return;
    }
    change = next;
    this.movedTo = next == WorkbenchFileChange.moved ? movedTo : null;
  }

  WorkbenchFile build() => WorkbenchFile(
        path: path,
        change: change ??
            (reads > 0 ? WorkbenchFileChange.read : WorkbenchFileChange.attempted),
        writes: writes,
        reads: reads,
        failures: failures,
        lastTool: lastTool,
        lastIndex: lastIndex,
        movedTo: movedTo,
      );
}
