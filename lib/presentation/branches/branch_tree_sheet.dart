import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/branches/branch_tree.dart';
import '../widgets/nexus_sheet.dart';

/// 打开分支树（阶段 7e）。选中其他会话时先关闭面板再回调。
Future<void> showBranchTreeSheet(
  BuildContext context, {
  required String currentConversationId,
  required ValueChanged<Conversation> onSelect,
}) =>
    showNexusSheet<void>(
      context: context,
      builder: (_) => BranchTreeSheet(
        currentConversationId: currentConversationId,
        onSelect: onSelect,
      ),
    );

class BranchTreeSheet extends ConsumerStatefulWidget {
  const BranchTreeSheet({
    super.key,
    required this.currentConversationId,
    required this.onSelect,
  });

  final String currentConversationId;
  final ValueChanged<Conversation> onSelect;

  @override
  ConsumerState<BranchTreeSheet> createState() => _BranchTreeSheetState();
}

class _BranchTreeSheetState extends ConsumerState<BranchTreeSheet> {
  BranchTree? _tree;
  String? _forkPoint;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service = await ref.read(branchTreeServiceProvider.future);
      final tree = await service.load(widget.currentConversationId);
      final current = tree.current;
      final forkPoint =
          current == null ? null : await service.forkPointText(current);
      if (mounted) {
        setState(() {
          _tree = tree;
          _forkPoint = forkPoint;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    if (_error != null) {
      return _SheetBody(children: [
        Text('读取分支失败：$_error', style: Theme.of(context).textTheme.bodyMedium),
      ]);
    }
    if (tree == null) {
      return const _SheetBody(children: [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ]);
    }
    return BranchTreeView(
      tree: tree,
      forkPoint: _forkPoint,
      onSelect: (conversation) {
        Navigator.of(context).pop();
        widget.onSelect(conversation);
      },
    );
  }
}

/// 分支树的纯展示部分。
class BranchTreeView extends StatelessWidget {
  const BranchTreeView({
    super.key,
    required this.tree,
    required this.onSelect,
    this.forkPoint,
  });

  final BranchTree tree;
  final String? forkPoint;
  final ValueChanged<Conversation> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    return _SheetBody(children: [
      Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (tree.missingParentId != null)
              const _Note(
                icon: Icons.link_off_rounded,
                text: '这一族分支的来源会话已被删除',
              ),
            if (forkPoint != null)
              _Note(
                icon: Icons.call_split_rounded,
                text: '当前会话从「$forkPoint」处分出',
              ),
            if (!tree.hasBranches)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '这个会话还没有分支。\n长按任意消息，选择「新建分支」，即可从那里分出新会话。',
                  textAlign: TextAlign.center,
                  style: muted,
                ),
              )
            else
              for (final node in tree.nodes) _row(context, node),
          ],
        ),
      ),
    ]);
  }

  Widget _row(BuildContext context, BranchNode node) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final conversation = node.conversation;
    final details = <String>[
      _formatDate(conversation.createdAt),
      if (node.children.isNotEmpty) '${node.children.length} 个分支',
    ];
    return InkWell(
      key: ValueKey('branch_${node.id}'),
      borderRadius: BorderRadius.circular(10),
      onTap: node.isCurrent ? null : () => onSelect(conversation),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8.0 + node.depth * 18.0, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              node.depth == 0
                  ? Icons.account_tree_outlined
                  : Icons.subdirectory_arrow_right_rounded,
              size: 18,
              color: node.onCurrentPath
                  ? primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: node.onCurrentPath ? FontWeight.w600 : null,
                    ),
                  ),
                  Text(details.join(' · '), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (node.isCurrent)
              Text('当前',
                  style: theme.textTheme.labelSmall?.copyWith(color: primary))
            else
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime time) {
    final t = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('分支', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('本会话的来源与分支，点一下即可切换', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
