// 阶段 7e：分支树面板。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/branches/branch_tree.dart';
import 'package:mobile_agent/presentation/branches/branch_tree_sheet.dart';

void main() {
  final base = DateTime(2026, 9, 30, 9);
  Conversation conv(String id, {String? parent, int minute = 0}) => Conversation(
        id: id,
        title: '会话 $id',
        agentId: null,
        projectId: null,
        mode: 'chat',
        providerProfileId: null,
        isPinned: false,
        isFavorite: false,
        tagsJson: jsonEncode([if (parent != null) 'parent:$parent']),
        createdAt: base.add(Duration(minutes: minute)),
        updatedAt: base,
      );

  Future<void> pump(WidgetTester tester, BranchTree tree,
      {String? forkPoint, ValueChanged<Conversation>? onSelect}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BranchTreeView(
          tree: tree,
          forkPoint: forkPoint,
          onSelect: onSelect ?? (_) {},
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('lists the family, marks current and switches on tap', (tester) async {
    final tree = BranchTree.build([
      conv('root'),
      conv('a', parent: 'root', minute: 1),
      conv('b', parent: 'root', minute: 2),
    ], 'a');
    final selected = <String>[];
    await pump(tester, tree, forkPoint: '第一问', onSelect: (c) => selected.add(c.id));

    expect(find.text('会话 root'), findsOneWidget);
    expect(find.text('会话 a'), findsOneWidget);
    expect(find.text('会话 b'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    expect(find.textContaining('2 个分支'), findsOneWidget);
    expect(find.text('当前会话从「第一问」处分出'), findsOneWidget);

    await tester.tap(find.text('会话 a')); // 当前会话不可点
    await tester.tap(find.text('会话 b'));
    expect(selected, ['b']);
  });

  testWidgets('no branches and deleted source states', (tester) async {
    await pump(tester, BranchTree.build([conv('solo')], 'solo'));
    expect(find.textContaining('这个会话还没有分支'), findsOneWidget);

    await pump(tester, BranchTree.build([conv('x', parent: 'gone')], 'x'));
    expect(find.text('这一族分支的来源会话已被删除'), findsOneWidget);
    expect(find.text('会话 x'), findsOneWidget);
  });
}
