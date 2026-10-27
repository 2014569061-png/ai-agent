// Review 2.0：会话级 checkpoint 时间线。
// 每个对话轮次起点自动打点（见 ChatController.send），这里提供
// “回代码 / 回会话 / 两者”三种 rewind，与任务 diff 复查面板并列。
import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_controller.dart';
import '../../application/providers.dart';
import '../../application/session_checkpoint_service.dart';
import '../../application/desktop_git_service.dart';
import '../../application/desktop_host_service.dart';
import '../../application/desktop_run_service.dart';
import '../theme/desktop_theme.dart';
import 'desktop_workbench_panels.dart';

/// 会话级 checkpoint 时间线面板。
class DesktopCheckpointTimeline extends ConsumerStatefulWidget {
  const DesktopCheckpointTimeline({
    super.key,
    this.store = const SessionCheckpointStore(),
    this.service = const SessionCheckpointService(),
  });

  final SessionCheckpointStore store;
  final SessionCheckpointService service;

  @override
  ConsumerState<DesktopCheckpointTimeline> createState() =>
      _DesktopCheckpointTimelineState();
}

enum _Rewind { code, conversation, both }

class _DesktopCheckpointTimelineState
    extends ConsumerState<DesktopCheckpointTimeline> {
  SessionCheckpointStore get _store => widget.store;
  SessionCheckpointService get _service => widget.service;

  int _version = 0;
  bool _busy = false;
  Future<List<SessionCheckpoint>>? _future;
  String? _loadedConversationId;
  int _lastVersion = -1;

  Future<List<SessionCheckpoint>> _ensureFuture(String conversationId) {
    if (_future == null ||
        _loadedConversationId != conversationId ||
        _lastVersion != _version) {
      _loadedConversationId = conversationId;
      _lastVersion = _version;
      _future = _store.listFor(conversationId);
    }
    return _future!;
  }

  String _label(SessionCheckpoint checkpoint) => checkpoint.label.isNotEmpty
      ? checkpoint.label
      : '第 ${checkpoint.turn} 轮前';

  String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _create(String conversationId, String? workspacePath) async {
    final db = await ref.read(databaseProvider.future);
    final messageCount = await db.messageCountFor(conversationId);
    final created = await _service.recordTurn(
      store: _store,
      conversationId: conversationId,
      workspacePath: workspacePath,
      messageCount: messageCount,
    );
    if (!mounted) return;
    setState(() => _version++);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(created == null
            ? '当前位置与最近的 checkpoint 相同，未重复创建'
            : '已创建 checkpoint「${_label(created)}」')));
  }

  Future<int> _rewindConversation(SessionCheckpoint checkpoint) async {
    final db = await ref.read(databaseProvider.future);
    final messages = await db.messagesFor(checkpoint.conversationId);
    final ids = messages
        .skip(checkpoint.messageCount)
        .map((row) => row.id)
        .toList(growable: false);
    final removed = ids.isEmpty ? 0 : await db.deleteMessagesByIds(ids);
    // 正在查看的会话若被截断，内存中的消息列表同步收敛。
    if (mounted &&
        ref.read(chatControllerProvider).conversationId ==
            checkpoint.conversationId) {
      await ref
          .read(chatControllerProvider.notifier)
          .refreshAfterRewind(checkpoint.conversationId);
    }
    return removed;
  }

  Future<CheckpointRewindSummary> _rewindCode(
      SessionCheckpoint checkpoint) async {
    final db = await ref.read(databaseProvider.future);
    return _service.rewindCode(checkpoint, tasksAfter: () async {
      final rows = await db.tasksForConversation(checkpoint.conversationId,
          since: checkpoint.createdAt);
      return [
        for (final row in rows)
          CheckpointTaskRef(id: row.id, createdAt: row.createdAt),
      ];
    });
  }

  Future<void> _rewind(SessionCheckpoint checkpoint, _Rewind scope) async {
    if (_busy || ref.read(chatControllerProvider).running) return;
    final description = switch (scope) {
      _Rewind.code => '仅恢复代码：回滚该 checkpoint 之后创建的任务改动；会话消息保留。',
      _Rewind.conversation =>
        '仅回退会话：消息截断到该 checkpoint 时的 ${checkpoint.messageCount} 条；代码改动保留。',
      _Rewind.both => '回退两者：先恢复代码，再把会话消息截断到 ${checkpoint.messageCount} 条。',
    };
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('回退到「${_label(checkpoint)}」'),
                content: Text(description),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认回退')),
                ]));
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.withRestoreLock<void>(checkpoint, isRunning: () async {
        if (DesktopHostService.instance.hasTerminal(checkpoint.workspacePath) ||
            DesktopRunService.instance.running(checkpoint.workspacePath)) {
          return true;
        }
        final chat = ref.read(chatControllerProvider);
        if (chat.running ||
            ref.read(chatControllerProvider.notifier).hasBoundDevelopmentRun) {
          return true;
        }
        final db = await ref.read(databaseProvider.future);
        final tasks = await db.tasksForConversation(checkpoint.conversationId);
        return tasks.any((task) => const [
              'running',
              'pending',
              'awaiting_approval'
            ].contains(task.status));
      }, action: () async {
        if (scope != _Rewind.conversation &&
            checkpoint.workspacePath.isNotEmpty) {
          final db = await ref.read(databaseProvider.future);
          final preview = await _service.preflight(checkpoint,
              tasksAfter: () async => [
                    for (final row in await db.tasksForConversation(
                        checkpoint.conversationId,
                        since: checkpoint.createdAt))
                      CheckpointTaskRef(id: row.id, createdAt: row.createdAt),
                  ]);
          if (preview.conflicts.isNotEmpty) {
            throw StateError('恢复预检发现冲突，文件和会话均已保留：${preview.conflictText}');
          }
        }
        String message;
        if (scope == _Rewind.code) {
          final summary = await _rewindCode(checkpoint);
          message = '已恢复 ${summary.restored} 个文件（涉及 ${summary.tasks} 个任务）';
          if (summary.conflicts.isNotEmpty) {
            message += '；跳过：${summary.conflictText}';
          }
        } else if (scope == _Rewind.conversation) {
          final removed = await _rewindConversation(checkpoint);
          message = '会话已截断：删除 $removed 条消息';
        } else {
          final summary = await _rewindCode(checkpoint);
          if (summary.conflicts.isNotEmpty) {
            throw StateError('代码恢复未完成，会话已保留：${summary.conflictText}');
          }
          final removed = await _rewindConversation(checkpoint);
          message = '已恢复 ${summary.restored} 个文件，删除 $removed 条会话消息';
          if (summary.conflicts.isNotEmpty) {
            message += '；跳过：${summary.conflictText}';
          }
        }
        if (!mounted) return;
        if (checkpoint.workspacePath.isNotEmpty) {
          ref.invalidate(desktopGitSnapshotProvider(checkpoint.workspacePath));
        }
        setState(() => _version++);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('回退失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(chatControllerProvider
        .select((s) => (s.conversationId, s.currentWorkspacePath, s.running)));
    final conversationId = identity.$1;
    if (conversationId == null) {
      return const DesktopPanelEmpty(message: '打开会话后可查看 checkpoint 时间线');
    }
    final colors = DesktopTheme.maybeOf(context);
    final future = _ensureFuture(conversationId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(
                child: Text('会话 checkpoint · 每轮对话前自动打点',
                    style: Theme.of(context).textTheme.bodySmall)),
            TextButton.icon(
                onPressed: _busy || identity.$3
                    ? null
                    : () => _create(conversationId, identity.$2),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('立即创建')),
            TextButton(
                onPressed: () => setState(() => _version++),
                child: const Text('刷新')),
          ])),
      const Divider(height: 1),
      Expanded(
          child: FutureBuilder<List<SessionCheckpoint>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return DesktopPanelEmpty(
                      message: '读取 checkpoint 失败：${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final checkpoints = snapshot.data!;
                if (checkpoints.isEmpty) {
                  return const DesktopPanelEmpty(
                      message: '暂无 checkpoint：发送首条消息时会自动创建，\n也可点右上角「立即创建」');
                }
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _chronosRibbon(checkpoints, colors),
                      Expanded(
                          child: ListView(children: [
                        for (var i = checkpoints.length - 1; i >= 0; i--)
                          _tile(checkpoints[i], colors),
                      ])),
                    ]);
              })),
    ]);
  }

  Widget _chronosRibbon(
      List<SessionCheckpoint> checkpoints, DesktopTheme? colors) {
    const emerald = DesktopTheme.statusSuccess;
    final border = colors?.border ?? DesktopTheme.light.border;
    final hover = colors?.hover ?? DesktopTheme.light.hover;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hover,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.history_toggle_off_rounded,
                size: 15, color: emerald),
            const SizedBox(width: 6),
            Text('时光磁带',
                style: TextStyle(
                    fontSize: AppTokens.fontSizeBadge,
                    fontWeight: FontWeight.w600,
                    color: colors?.text)),
            const SizedBox(width: 10),
            for (var i = 0; i < checkpoints.length; i++) ...[
              if (i > 0)
                Container(
                    width: 16,
                    height: 1.5,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: border),
              Tooltip(
                message:
                    '${_label(checkpoints[i])} · 消息 ${checkpoints[i].messageCount} 条 · 预检保护已开启',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: i == checkpoints.length - 1
                        ? emerald.withValues(alpha: 0.14)
                        : (colors?.panel ?? Colors.white),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    border: Border.all(
                        color: i == checkpoints.length - 1 ? emerald : border),
                  ),
                  child: Text(
                    '#${checkpoints[i].turn}',
                    style: DesktopTheme.monospaceStyle(context,
                        size: 11,
                        fontWeight: i == checkpoints.length - 1
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: i == checkpoints.length - 1
                            ? emerald
                            : colors?.text),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(SessionCheckpoint checkpoint, DesktopTheme? colors) {
    return ListTile(
        dense: true,
        leading: Icon(Icons.bookmark_border, size: 16, color: colors?.accent),
        title: Text(_label(checkpoint),
            style: DesktopTheme.monospaceStyle(context,
                size: DesktopTheme.smallSize)),
        subtitle: Text(
            '${_time(checkpoint.createdAt)} · 消息 ${checkpoint.messageCount} 条'
            '${checkpoint.workspacePath.isEmpty ? ' · 未绑定工作区' : ''}'),
        trailing: PopupMenuButton<_Rewind>(
            enabled: !_busy && !ref.read(chatControllerProvider).running,
            tooltip: '选择回退方式',
            iconSize: 18,
            itemBuilder: (context) => const [
                  PopupMenuItem(value: _Rewind.code, child: Text('回代码（保留会话）')),
                  PopupMenuItem(
                      value: _Rewind.conversation, child: Text('回会话（保留代码）')),
                  PopupMenuItem(value: _Rewind.both, child: Text('回代码 + 回会话')),
                ],
            onSelected: (scope) => unawaited(_rewind(checkpoint, scope))));
  }
}
