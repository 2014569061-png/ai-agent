import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/database/app_database.dart';
import '../providers.dart';

export '../../infrastructure/database/app_database.dart' show Conversation;

/// 分支树导航（阶段 7e）。
///
/// 分叉关系来自会话标签 `parent:<id>` / `forkMessage:<messageId>`
/// （`ConversationForkService` 写入），不依赖会话日志开关，老数据也能用。

class BranchNode {
  BranchNode({
    required this.conversation,
    required this.depth,
    required this.isCurrent,
    required this.onCurrentPath,
    this.forkMessageId,
  });

  final Conversation conversation;
  final int depth;
  final bool isCurrent;

  /// 当前会话本身或它的祖先。
  final bool onCurrentPath;
  final String? forkMessageId;
  final List<BranchNode> children = [];

  String get id => conversation.id;
}

class BranchTree {
  const BranchTree({
    required this.nodes,
    this.missingParentId,
  });

  static const empty = BranchTree(nodes: []);

  /// 先序遍历：父在前，兄弟按创建时间排列；`depth` 给出缩进层级。
  final List<BranchNode> nodes;

  /// 根节点声明了来源、但来源会话已被删除时，记下它的 id。
  final String? missingParentId;

  BranchNode? get root => nodes.isEmpty ? null : nodes.first;

  BranchNode? get current {
    for (final node in nodes) {
      if (node.isCurrent) return node;
    }
    return null;
  }

  /// 只有当前会话自己、也没有丢失的来源时，没什么可导航的。
  bool get hasBranches => nodes.length > 1 || missingParentId != null;

  static String? parentOf(Conversation conversation) =>
      _tag(conversation, 'parent:');

  static String? forkMessageOf(Conversation conversation) =>
      _tag(conversation, 'forkMessage:');

  static String? _tag(Conversation conversation, String prefix) {
    for (final tag in decodeTags(conversation.tagsJson)) {
      if (tag.startsWith(prefix) && tag.length > prefix.length) {
        return tag.substring(prefix.length);
      }
    }
    return null;
  }

  static List<String> decodeTags(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return [for (final t in decoded) if (t is String) t];
    } on FormatException {
      // 标签损坏时当作没有分叉信息。
    }
    return const [];
  }

  /// 以 [currentId] 所在分支族的根为起点建树。
  static BranchTree build(List<Conversation> all, String currentId) {
    final byId = {for (final c in all) c.id: c};
    if (!byId.containsKey(currentId)) return empty;

    final children = <String, List<Conversation>>{};
    for (final conversation in all) {
      final parent = parentOf(conversation);
      if (parent != null && parent != conversation.id) {
        children.putIfAbsent(parent, () => []).add(conversation);
      }
    }
    for (final list in children.values) {
      list.sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    }

    // 从当前会话往上找根；遇到环或缺失的来源就停。
    final path = <String>{currentId};
    var top = byId[currentId]!;
    String? missingParentId;
    while (true) {
      final parentId = parentOf(top);
      if (parentId == null) break;
      final parent = byId[parentId];
      if (parent == null) {
        missingParentId = parentId;
        break;
      }
      if (!path.add(parentId)) break;
      top = parent;
    }

    final nodes = <BranchNode>[];
    final visited = <String>{};
    BranchNode visit(Conversation conversation, int depth) {
      visited.add(conversation.id);
      final node = BranchNode(
        conversation: conversation,
        depth: depth,
        isCurrent: conversation.id == currentId,
        onCurrentPath: path.contains(conversation.id),
        forkMessageId: forkMessageOf(conversation),
      );
      nodes.add(node);
      for (final child in children[conversation.id] ?? const <Conversation>[]) {
        if (visited.contains(child.id)) continue;
        node.children.add(visit(child, depth + 1));
      }
      return node;
    }

    visit(top, 0);
    return BranchTree(nodes: nodes, missingParentId: missingParentId);
  }
}

class BranchTreeService {
  const BranchTreeService(this.db);

  final AppDatabase db;

  Future<BranchTree> load(String currentId) async =>
      BranchTree.build(await db.recentConversations(), currentId);

  /// 分叉点消息的文字摘要（在来源会话里查找）；找不到时返回 null。
  Future<String?> forkPointText(BranchNode node, {int maxLength = 80}) async {
    final parentId = BranchTree.parentOf(node.conversation);
    final messageId = node.forkMessageId;
    if (parentId == null || messageId == null) return null;
    final messages = await db.messagesFor(parentId);
    for (final message in messages) {
      if (message.id != messageId) continue;
      final text = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) return null;
      return text.length <= maxLength ? text : '${text.substring(0, maxLength)}…';
    }
    return null;
  }
}

final branchTreeServiceProvider = FutureProvider<BranchTreeService>(
    (ref) async => BranchTreeService(await ref.watch(databaseProvider.future)));
