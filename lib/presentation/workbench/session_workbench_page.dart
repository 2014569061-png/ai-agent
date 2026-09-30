import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_controller.dart';
import '../../application/workbench/session_workbench.dart';
import '../motion/nexus_page_route_factory.dart';
import '../theme/app_appearance_controller.dart';
import '../theme/app_palette.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/floating_toast.dart';
import '../widgets/glass_surface.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';
import '../workspace/workspace_editor_page.dart';

/// 会话工作台（阶段 7c）：当前会话的「文件 / 结果」页签 + 运行状态条。
///
/// 「对话」就是聊天页本身；这里只做投影，数据随聊天状态实时刷新。
class SessionWorkbenchPage extends ConsumerWidget {
  const SessionWorkbenchPage({super.key, this.initialTab = 0});

  /// 0 = 文件，1 = 结果。
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatControllerProvider.select((s) => s.messages));
    final activities =
        ref.watch(chatControllerProvider.select((s) => s.toolActivities));
    final running = ref.watch(chatControllerProvider.select((s) => s.running));
    final paused = ref.watch(chatControllerProvider.select((s) => s.paused));
    final runProgress =
        ref.watch(chatControllerProvider.select((s) => s.runProgress));
    final title =
        ref.watch(chatControllerProvider.select((s) => s.conversationTitle));
    final workspace =
        ref.watch(chatControllerProvider.select((s) => s.currentWorkspacePath));
    final projectId =
        ref.watch(chatControllerProvider.select((s) => s.currentProjectId));

    final workbench = SessionWorkbench.project(
      messages: messages,
      activities: activities,
      running: running,
      paused: paused,
      runProgress: runProgress,
    );

    return SessionWorkbenchView(
      workbench: workbench,
      title: title,
      workspace: workspace,
      projectId: projectId,
      initialTab: initialTab,
    );
  }
}

/// 工作台的纯展示部分，便于测试。
class SessionWorkbenchView extends StatelessWidget {
  const SessionWorkbenchView({
    super.key,
    required this.workbench,
    this.title = '',
    this.workspace,
    this.projectId,
    this.initialTab = 0,
  });

  final SessionWorkbench workbench;
  final String title;
  final String? workspace;
  final String? projectId;
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFlat =
        AppAppearanceController.resolvedGlassIntensity == GlassIntensity.flat;
    final changed = workbench.files.where((f) => f.changed).length;

    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Scaffold(
        backgroundColor: isFlat
            ? (isDark ? AppPalette.darkCanvas : AppPalette.lightCanvas)
            : Colors.transparent,
        appBar: NexusPageHeader(
          title: '会话工作台',
          subtitle: title.isEmpty ? '当前会话' : title,
          onBack: () => Navigator.of(context).pop(),
          bottom: TabBar(tabs: [
            Tab(text: changed == 0 ? '文件' : '文件 ($changed)'),
            Tab(
                text: workbench.turns.isEmpty
                    ? '结果'
                    : '结果 (${workbench.turns.length})'),
          ]),
        ),
        body: Column(
          children: [
            WorkbenchStatusBar(status: workbench.status),
            Expanded(
              child: TabBarView(children: [
                _FilesTab(
                  files: workbench.files,
                  workspace: workspace,
                  projectId: projectId,
                ),
                _ResultsTab(turns: workbench.turns),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// 运行状态条：运行中 / 已暂停 / 空闲，以及工具、待确认、失败、改动计数。
class WorkbenchStatusBar extends StatelessWidget {
  const WorkbenchStatusBar({super.key, required this.status});

  final WorkbenchStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (IconData icon, String label, Color color) = status.running
        ? (Icons.play_circle_outline_rounded, status.stageLabel ?? '运行中',
            scheme.primary)
        : status.paused
            ? (Icons.pause_circle_outline_rounded, status.stageLabel ?? '已暂停',
                scheme.tertiary)
            : (Icons.check_circle_outline_rounded, '空闲', scheme.outline);
    final chips = <String>[
      '${status.turns} 轮',
      '${status.toolCalls} 次工具调用',
      if (status.changedFiles > 0) '${status.changedFiles} 个文件改动',
      if (status.pendingApprovals > 0) '${status.pendingApprovals} 项待确认',
      if (status.failedTools > 0) '${status.failedTools} 次失败',
    ];
    return SectionCard(
      key: const ValueKey('workbench_status_bar'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(color: color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              chips.join(' · '),
              maxLines: 2,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: status.pendingApprovals > 0 || status.failedTools > 0
                    ? scheme.error
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesTab extends StatelessWidget {
  const _FilesTab({
    required this.files,
    required this.workspace,
    required this.projectId,
  });

  final List<WorkbenchFile> files;
  final String? workspace;
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const EmptyStateView(
        icon: Icons.folder_open_outlined,
        title: '本会话还没有接触文件',
        message: 'Agent 读取或修改工作区文件后会列在这里',
      );
    }
    final changed = files.where((f) => f.changed).toList();
    final read = files.where((f) => !f.changed).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (changed.isNotEmpty) _header(context, '改动的文件 (${changed.length})'),
        for (final file in changed) _tile(context, file),
        if (read.isNotEmpty) _header(context, '未改动的文件 (${read.length})'),
        for (final file in read) _tile(context, file),
      ],
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium),
      );

  Widget _tile(BuildContext context, WorkbenchFile file) {
    final scheme = Theme.of(context).colorScheme;
    final details = <String>[
      workbenchChangeLabel(file.change),
      if (file.movedTo != null) '→ ${file.movedTo}',
      if (file.writes > 0) '写入 ${file.writes} 次',
      if (file.reads > 0) '读取 ${file.reads} 次',
      if (file.failures > 0) '失败 ${file.failures} 次',
    ];
    return SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: Icon(workbenchChangeIcon(file.change),
            color: file.failures > 0 &&
                    file.change == WorkbenchFileChange.attempted
                ? scheme.error
                : file.changed
                    ? scheme.primary
                    : scheme.outline),
        title: Text(file.path, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(details.join(' · ')),
        onTap: () => _open(context, file),
      ),
    );
  }

  void _open(BuildContext context, WorkbenchFile file) {
    final root = workspace;
    if (root == null || root.isEmpty) {
      FloatingToast.show(context, '当前会话没有关联工作区', tone: ToastTone.warning);
      return;
    }
    final target = file.change == WorkbenchFileChange.moved
        ? file.movedTo
        : file.change == WorkbenchFileChange.deleted
            ? null
            : file.path;
    if (target == null) {
      FloatingToast.show(context, '文件已删除');
      return;
    }
    Navigator.of(context).push(NexusPageRoute.detail(
      builder: (_) => WorkspaceEditorPage(
        workspacePath: root,
        relativePath: target,
        projectId: projectId,
      ),
    ));
  }
}

class _ResultsTab extends StatelessWidget {
  const _ResultsTab({required this.turns});

  final List<WorkbenchTurn> turns;

  @override
  Widget build(BuildContext context) {
    if (turns.isEmpty) {
      return const EmptyStateView(
        icon: Icons.chat_bubble_outline_rounded,
        title: '还没有结果',
        message: '每轮对话的最终回答会汇总在这里',
      );
    }
    final textTheme = Theme.of(context).textTheme;
    final faint = Theme.of(context).colorScheme.outline;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: turns.length,
      itemBuilder: (context, index) {
        final turn = turns[index];
        return SectionCard(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: turn.answer == null ? null : () => _showAnswer(context, turn),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('第 ${turn.index} 轮',
                      style: textTheme.labelSmall?.copyWith(color: faint)),
                  const SizedBox(height: 4),
                  Text(turn.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    turn.answer ?? '（还没有回答）',
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: turn.answer == null ? faint : null),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAnswer(BuildContext context, WorkbenchTurn turn) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('第 ${turn.index} 轮结果'),
          content: SingleChildScrollView(child: SelectableText(turn.answer!)),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: turn.answer!));
                if (dialogContext.mounted) {
                  FloatingToast.show(dialogContext, '已复制');
                }
              },
              child: const Text('复制'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
}

String workbenchChangeLabel(WorkbenchFileChange change) => switch (change) {
      WorkbenchFileChange.written => '已写入',
      WorkbenchFileChange.created => '新增',
      WorkbenchFileChange.modified => '修改',
      WorkbenchFileChange.deleted => '删除',
      WorkbenchFileChange.moved => '移动',
      WorkbenchFileChange.read => '只读',
      WorkbenchFileChange.attempted => '未生效',
    };

IconData workbenchChangeIcon(WorkbenchFileChange change) => switch (change) {
      WorkbenchFileChange.written => Icons.save_outlined,
      WorkbenchFileChange.created => Icons.add_circle_outline_rounded,
      WorkbenchFileChange.modified => Icons.edit_note_rounded,
      WorkbenchFileChange.deleted => Icons.delete_outline_rounded,
      WorkbenchFileChange.moved => Icons.drive_file_move_outline,
      WorkbenchFileChange.read => Icons.visibility_outlined,
      WorkbenchFileChange.attempted => Icons.hourglass_empty_rounded,
    };
