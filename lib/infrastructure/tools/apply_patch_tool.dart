import 'dart:io';
import 'dart:math';

import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import 'tool_registry.dart';
import 'workspace_tools.dart';
import '../files/workspace_fs.dart';
import '../files/patch_journal.dart';
import '../observability/unified_diff.dart';

/// Strict patches with preflight and compensating rollback for file batches.
class ApplyPatchTool implements AgentTool, ToolExecutionMetadata {
  ApplyPatchTool({required this.sandbox})
      : _writer = WriteFileTool(sandbox: sandbox);
  final WorkspaceSandbox sandbox;
  final WriteFileTool _writer;
  @override
  Map<String, dynamic> lastMetadata = const {};
  @override
  final manifest = const UnifiedTool(
    name: 'apply_patch',
    description:
        '对已读取的已有文件应用 unified diff。单文件用 path/patch，多文件用 files 数组（最多10个），不可混用。全部预校验，失败时回滚；不模糊匹配。创建文件用 write_file。',
    risk: ToolRisk.requiresConfirmation,
    traits: ToolTraits.workspaceWrite,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'files': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 10,
          'items': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'patch': {'type': 'string'}
            },
            'required': ['path', 'patch']
          }
        },
        'path': {'type': 'string'},
        'patch': {
          'type': 'string',
          'description':
              '--- a/path\n+++ b/path\n@@ -旧行,数量 +新行,数量 @@\n 上下文\n-删除\n+新增'
        },
      },
      'oneOf': [
        {
          'required': ['path', 'patch'],
          'not': {
            'required': ['files']
          }
        },
        {
          'required': ['files'],
          'not': {
            'anyOf': [
              {
                'required': ['path']
              },
              {
                'required': ['patch']
              }
            ]
          }
        }
      ]
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    lastMetadata = const {};
    final recovery = await sandbox.prepareForWrite();
    if (recovery != null) {
      lastMetadata = {'operation': 'patch_recovery', ...?recovery.data};
      return recovery;
    }
    if (arguments.containsKey('files')) return _executeBatch(arguments);
    final path = arguments['path'];
    final patch = arguments['patch'];
    if (path is! String ||
        path.isEmpty ||
        patch is! String ||
        patch.length > 128 * 1024) {
      return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: '需要 path 和不超过 128KiB 的 patch');
    }
    try {
      final full = sandbox.resolvePath(path, allowRoot: false);
      final before = await sandbox.fs.readText(full);
      final conflict = sandbox.checkFresh(full, before);
      if (conflict != null) return conflict;
      final after = applyUnifiedPatch(before, patch, sandbox.toRelative(full));
      // The writer rereads and checks freshness again before committing.
      final result = await _writer.execute({'path': path, 'content': after});
      lastMetadata = _writer.lastMetadata;
      return result;
    } on FormatException catch (error) {
      return ToolResult.failure(
          code: ToolCodes.invalidFormat,
          message: '补丁未应用：${error.message}。请 read_file 后重新生成补丁。');
    } on ArgumentError {
      return ToolResult.failure(
          code: ToolCodes.sandboxViolation, message: '补丁路径越出工作区');
    } catch (_) {
      return ToolResult.failure(
          code: ToolCodes.ioError, message: '无法读取补丁目标，未应用补丁');
    }
  }

  Future<ToolResult> _executeBatch(Map<String, dynamic> arguments) async {
    final files = arguments['files'];
    if (arguments.containsKey('path') ||
        arguments.containsKey('patch') ||
        files is! List ||
        files.isEmpty ||
        files.length > 10) {
      return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: 'files 必须包含 1–10 个补丁，且不能与 path/patch 混用');
    }
    final prepared = <_PreparedPatch>[];
    final seen = <String>{};
    final fs = sandbox.fs;
    final journal = sandbox.patchJournal;
    var journalStarted = false;
    final nonce = List.generate(
            16,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    var committing = false;
    var committed = false;
    var code = ToolCodes.ioError;
    var message = '补丁批次失败';
    final unresolved = <String>[];
    final leftovers = <String>[];
    try {
      var size = 0;
      for (final entry in files) {
        if (entry is! Map ||
            entry['path'] is! String ||
            (entry['path'] as String).trim().isEmpty ||
            entry['patch'] is! String ||
            (entry['patch'] as String).length > 128 * 1024) {
          code = ToolCodes.invalidArguments;
          throw const FormatException('每个文件需要 path 和不超过 128KiB 的 patch');
        }
        final full =
            sandbox.resolvePath(entry['path'] as String, allowRoot: false);
        final relative = sandbox.toRelative(full);
        if (!PatchJournal.isSafeRelativePath(relative)) {
          throw const FormatException('补丁目标不能包含内部元数据或不可安全恢复的路径别名');
        }
        if (fs is LocalWorkspaceFs && await FileSystemEntity.isLink(full)) {
          throw const FormatException('批量补丁不替换符号链接，请使用真实文件路径');
        }
        final key = Platform.isWindows ? full.toLowerCase() : full;
        // Reject aliases too: two paths to the same file must not be patched twice.
        final canonical = fs is LocalWorkspaceFs
            ? await File(full).resolveSymbolicLinks()
            : key;
        if (!seen
            .add(Platform.isWindows ? canonical.toLowerCase() : canonical)) {
          throw const FormatException('批次包含重复目标路径');
        }
        final before = await fs.readText(full, maxBytes: 1024 * 1024);
        final conflict = sandbox.checkFresh(full, before);
        if (conflict != null) return conflict;
        final after =
            applyUnifiedPatch(before, entry['patch'] as String, relative);
        size += before.length + after.length;
        if (size > 2 * 1024 * 1024) {
          throw const FormatException('批次文本总量超过 2Mi 字符');
        }
        prepared.add(_PreparedPatch(full, relative, before, after,
            '$full.nexus-patch-$nonce.tmp', '$full.nexus-patch-$nonce.bak'));
      }
      await journal.start(nonce, [
        for (final item in prepared)
          {
            'path': item.relative,
            'before': PatchJournal.hash(item.before),
            'after': PatchJournal.hash(item.after),
          }
      ]);
      journalStarted = true;
      // Stage all output before touching any original file.
      for (final item in prepared) {
        for (final temporary in [item.staged, item.backup]) {
          sandbox.resolvePath(sandbox.toRelative(temporary), allowRoot: false);
          if (await fs.kindOf(temporary) != WorkspaceEntryKind.notFound) {
            throw const FormatException('补丁暂存路径已存在');
          }
        }
        item.stagingStarted = true;
        if (fs is LocalWorkspaceFs) {
          await fs.copyFile(item.full, item.staged);
          if (!Platform.isWindows &&
              (await File(item.full).stat()).mode !=
                  (await File(item.staged).stat()).mode) {
            throw StateError('file permissions could not be preserved');
          }
        }
        await fs.writeText(item.staged, item.after);
        if (await fs.readText(item.staged) != item.after) {
          throw StateError('staging failed');
        }
      }
      for (final item in prepared) {
        sandbox.resolvePath(item.relative, allowRoot: false);
        if (await fs.readText(item.full) != item.before) {
          code = ToolCodes.revisionConflict;
          throw const FormatException('目标文件在预校验后变化');
        }
      }
      committing = true;
      for (final item in prepared) {
        sandbox.resolvePath(item.relative, allowRoot: false);
        if (await fs.readText(item.full) != item.before) {
          code = ToolCodes.revisionConflict;
          throw const FormatException('目标文件在提交时变化');
        }
        item.commitStarted = true;
        await fs.rename(item.full, item.backup);
        await fs.rename(item.staged, item.full);
      }
      await journal.commit();
      committed = true;
      for (final item in prepared) {
        sandbox.rememberRead(item.full, item.after);
      }
    } on ArgumentError {
      code = ToolCodes.sandboxViolation;
      message = '补丁路径越出工作区';
    } on FormatException catch (error) {
      if (code == ToolCodes.ioError) code = ToolCodes.invalidFormat;
      message = '补丁未完成：${error.message}';
    } catch (_) {
      message = '补丁文件操作失败';
    } finally {
      if (committing && !committed) {
        for (final item in prepared.reversed.where((e) => e.commitStarted)) {
          try {
            sandbox.resolvePath(item.relative, allowRoot: false);
            sandbox.resolvePath(sandbox.toRelative(item.backup),
                allowRoot: false);
            final hasBackup =
                await fs.kindOf(item.backup) == WorkspaceEntryKind.file;
            final exists =
                await fs.kindOf(item.full) != WorkspaceEntryKind.notFound;
            final current = exists ? await fs.readText(item.full) : null;
            if (hasBackup && (current == null || current == item.after)) {
              if (await fs.readText(item.backup) != item.before) {
                throw StateError('backup changed');
              }
              if (exists) await fs.deleteFile(item.full);
              await fs.rename(item.backup, item.full);
            } else if (current != item.before) {
              // Never overwrite an external edit while compensating.
              throw StateError('concurrent edit');
            }
            if (await fs.readText(item.full) != item.before) {
              throw StateError('rollback failed');
            }
          } catch (_) {
            unresolved.add(item.relative);
          }
        }
        sandbox.forgetReads();
      }
      for (final item in prepared) {
        for (final temporary in [
          if (item.stagingStarted) item.staged,
          if (item.commitStarted && !unresolved.contains(item.relative))
            item.backup,
        ]) {
          try {
            sandbox.resolvePath(sandbox.toRelative(temporary),
                allowRoot: false);
            if (await fs.kindOf(temporary) == WorkspaceEntryKind.file) {
              await fs.deleteFile(temporary);
            }
          } catch (_) {
            leftovers.add(sandbox.toRelative(temporary));
          }
        }
      }
      if (journalStarted) {
        try {
          await journal.finish(clean: unresolved.isEmpty && leftovers.isEmpty);
        } catch (_) {
          leftovers.add('.nexus/patch-journal/$nonce.json');
        }
      }
    }
    final changes = [
      for (final item in prepared)
        if (committed || unresolved.contains(item.relative))
          buildUnifiedDiff(item.before, item.after,
                  oldPath: 'a/${item.relative}', newPath: 'b/${item.relative}')
              .toMetadata(operation: 'edit', path: item.relative)
    ];
    lastMetadata = {
      'operation': 'apply_patch',
      'fileChanges': changes,
      'transactionStatus': committed
          ? 'committed'
          : unresolved.isEmpty
              ? 'rolled_back'
              : 'needs_recovery',
      if (unresolved.isNotEmpty) 'unresolvedFiles': unresolved,
      if (leftovers.isNotEmpty) 'temporaryFiles': leftovers,
      if (unresolved.isNotEmpty)
        'recoveryFiles': [
          for (final item in prepared)
            if (unresolved.contains(item.relative))
              sandbox.toRelative(item.backup)
        ],
    };
    final data = lastMetadata;
    if (committed) {
      return ToolResult.success(
          message: '已应用 ${prepared.length} 个文件补丁',
          effect: ToolEffect.applied,
          data: data);
    }
    return ToolResult.failure(
        code: code,
        message: unresolved.isEmpty
            ? '$message；目标文件未改变或已恢复。'
            : '$message；可能已执行，请先读取确认。回滚冲突文件已保留备份。',
        effect: unresolved.isNotEmpty || leftovers.isNotEmpty
            ? ToolEffect.unknown
            : ToolEffect.none,
        data: data);
  }
}

class _PreparedPatch {
  _PreparedPatch(this.full, this.relative, this.before, this.after, this.staged,
      this.backup);
  final String full, relative, before, after, staged, backup;
  bool stagingStarted = false;
  bool commitStarted = false;
}

String applyUnifiedPatch(String source, String patch, String path) {
  final eol = source.contains('\r\n') ? '\r\n' : '\n';
  final old =
      source.isEmpty ? <String>[] : source.replaceAll('\r\n', '\n').split('\n');
  if (source.endsWith('\n')) old.removeLast();
  final lines = patch.replaceAll('\r\n', '\n').split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  if (lines.length < 3 ||
      lines[0] != '--- a/$path' ||
      lines[1] != '+++ b/$path') {
    throw const FormatException('只接受匹配 path 的单文件 --- a/path 和 +++ b/path 头部');
  }
  final output = <String>[];
  var cursor = 0;
  var index = 2;
  var hunks = 0;
  int? noNewlineAt;
  var touchesEnd = false;
  final header =
      RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: .*)?$');
  while (index < lines.length) {
    final match = header.firstMatch(lines[index++]);
    if (match == null) throw const FormatException('无效的 hunk 头部');
    hunks++;
    final oldStart = int.parse(match.group(1)!);
    final oldCount = int.parse(match.group(2) ?? '1');
    final newStart = int.parse(match.group(3)!);
    final newCount = int.parse(match.group(4) ?? '1');
    final start = oldCount == 0 ? oldStart : oldStart - 1;
    if (start < cursor || start > old.length) {
      throw const FormatException('hunk 越界或重叠');
    }
    output.addAll(old.sublist(cursor, start));
    cursor = start;
    if (output.length != (newCount == 0 ? newStart : newStart - 1)) {
      throw const FormatException('新文件行号与补丁顺序不一致');
    }
    var removed = 0;
    var added = 0;
    String? previous;
    while (index < lines.length && !lines[index].startsWith('@@ ')) {
      final line = lines[index++];
      if (line == r'\ No newline at end of file') {
        if (previous == null) throw const FormatException('无效的文件末尾标记');
        if (previous == ' ' || previous == '-') {
          if (cursor != old.length || source.endsWith('\n')) {
            throw const FormatException('旧文件末尾标记与实际内容不符');
          }
        }
        if (previous == ' ' || previous == '+') noNewlineAt = output.length;
        previous = null;
        continue;
      }
      if (line.isEmpty || ![' ', '+', '-'].contains(line[0])) {
        throw const FormatException('hunk 行必须以空格、+ 或 - 开头');
      }
      previous = line[0];
      final text = line.substring(1);
      if (previous != '+') {
        if (cursor >= old.length || old[cursor] != text) {
          throw const FormatException('旧代码上下文不匹配');
        }
        cursor++;
        removed++;
      }
      if (previous != '-') {
        output.add(text);
        added++;
      }
    }
    if (removed != oldCount || added != newCount) {
      throw const FormatException('hunk 行数不匹配');
    }
    touchesEnd = cursor == old.length;
  }
  if (hunks == 0) throw const FormatException('补丁没有修改块');
  output.addAll(old.sublist(cursor));
  if (noNewlineAt != null && noNewlineAt != output.length) {
    throw const FormatException('末尾标记出现在文件中间');
  }
  final newline = noNewlineAt == null && (touchesEnd || source.endsWith('\n'));
  return output.join(eol) + (output.isNotEmpty && newline ? eol : '');
}
