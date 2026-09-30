// 阶段 7e：分支树导航。
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/branches/branch_tree.dart';
import 'package:mobile_agent/application/conversation_fork_service.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

void main() {
  final base = DateTime(2026, 9, 30, 9);

  Conversation conv(String id, {String? parent, String? forkMessage, int minute = 0,
          String? tagsJson}) =>
      Conversation(
        id: id,
        title: '会话 $id',
        agentId: null,
        projectId: null,
        mode: 'chat',
        providerProfileId: null,
        isPinned: false,
        isFavorite: false,
        tagsJson: tagsJson ??
            jsonEncode([
              'keep',
              if (parent != null) 'parent:$parent',
              if (forkMessage != null) 'forkMessage:$forkMessage',
            ]),
        createdAt: base.add(Duration(minutes: minute)),
        updatedAt: base.add(Duration(minutes: minute)),
      );

  //  root
  //  ├─ a (1)
  //  │  └─ a1 (3)
  //  └─ b (2)
  //  other（无关）
  final family = [
    conv('b', parent: 'root', minute: 2),
    conv('a1', parent: 'a', forkMessage: 'm7', minute: 3),
    conv('root'),
    conv('a', parent: 'root', minute: 1),
    conv('other', minute: 5),
  ];

  test('builds the whole family from any member, preorder with depth', () {
    final tree = BranchTree.build(family, 'a1');
    expect(tree.nodes.map((n) => '${n.id}@${n.depth}'),
        ['root@0', 'a@1', 'a1@2', 'b@1']);
    expect(tree.current!.id, 'a1');
    expect(tree.current!.forkMessageId, 'm7');
    expect(tree.nodes.where((n) => n.onCurrentPath).map((n) => n.id),
        ['root', 'a', 'a1']);
    expect(tree.root!.children.map((n) => n.id), ['a', 'b']);
    expect(tree.hasBranches, isTrue);
    expect(tree.missingParentId, isNull);

    expect(BranchTree.build(family, 'b').nodes.length, 4);
  });

  test('a conversation without forks has nothing to navigate', () {
    final tree = BranchTree.build(family, 'other');
    expect(tree.nodes.single.id, 'other');
    expect(tree.hasBranches, isFalse);
    expect(BranchTree.build(family, 'missing').nodes, isEmpty);
  });

  test('deleted source is reported; cycles and bad tags do not hang', () {
    final orphan = BranchTree.build([conv('x', parent: 'gone')], 'x');
    expect(orphan.missingParentId, 'gone');
    expect(orphan.hasBranches, isTrue);

    final cyclic = BranchTree.build([
      conv('p', parent: 'q'),
      conv('q', parent: 'p', minute: 1),
    ], 'p');
    expect(cyclic.nodes.map((n) => n.id).toSet(), {'p', 'q'});

    final self = BranchTree.build([conv('s', parent: 's')], 's');
    expect(self.nodes.single.id, 's');

    final broken = conv('z', tagsJson: '{not json');
    expect(BranchTree.parentOf(broken), isNull);
    expect(BranchTree.build([broken], 'z').hasBranches, isFalse);
  });

  test('integrates with the fork service and resolves the fork point', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.saveConversation(conv('src', tagsJson: '[]'));
    for (final (id, text) in [('m1', '第一问'), ('m2', '  回答\n很长的内容  ')]) {
      await db.insertMessage(MessagesCompanion.insert(
        id: id,
        conversationId: 'src',
        role: id == 'm1' ? 'user' : 'assistant',
        content: text,
        createdAt: id == 'm1' ? base : base.add(const Duration(minutes: 1)),
      ));
    }
    final branch = await const ConversationForkService()
        .fork(db: db, sourceConversationId: 'src', forkMessageId: 'm2');
    final copiedFirst = (await db.messagesFor(branch.id))
        .firstWhere((m) => m.content == '第一问');
    final nested = await const ConversationForkService().fork(
        db: db, sourceConversationId: branch.id, forkMessageId: copiedFirst.id);

    final service = BranchTreeService(db);
    final tree = await service.load(nested.id);
    expect(tree.nodes.map((n) => n.id), ['src', branch.id, nested.id]);
    final branchNode = tree.nodes[1];
    expect(await service.forkPointText(branchNode), '回答 很长的内容');
    expect(await service.forkPointText(tree.nodes[2]), '第一问');
    expect(await service.forkPointText(tree.nodes[0]), isNull);
  });
}
