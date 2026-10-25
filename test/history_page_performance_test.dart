import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/presentation/history/history_page.dart';

void main() {
  testWidgets('history page lazily builds conversations outside the viewport',
      (tester) async {
    String? selectedId;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime(2026, 9, 17, 12);
    final conversations = List<Conversation>.generate(
      600,
      (index) => Conversation(
        id: 'conversation-$index',
        title: '会话 $index',
        agentId: null,
        mode: 'chat',
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          loadConversations: () async => conversations,
          onConversationSelected: (id) => selectedId = id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('会话 0'), findsOneWidget);
    expect(find.text('会话 599'), findsNothing);
    await tester.tap(find.text('会话 0'));
    await tester.pumpAndSettle();
    expect(selectedId, 'conversation-0');
  });

  testWidgets('history page loads the next page on demand', (tester) async {
    final now = DateTime(2026, 9, 17, 12);
    final conversations = List<Conversation>.generate(
      55,
      (index) => Conversation(
        id: 'paged-conversation-$index',
        title: '浼氳瘽 $index',
        agentId: null,
        mode: 'chat',
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final offsets = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          loadConversationPage: ({required limit, required offset}) async {
            offsets.add(offset);
            return conversations.skip(offset).take(limit).toList();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(offsets, [0]);
    expect(find.text('浼氳瘽 54'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('加载更多'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(offsets, [0, 50]);
    expect(find.text('加载更多'), findsNothing);
  });

  testWidgets('history search debounces rapid text changes', (tester) async {
    final now = DateTime(2026, 9, 17, 12);
    var loadCount = 0;
    final conversations = [
      Conversation(
        id: 'search-result',
        title: 'Alpha Beta',
        agentId: null,
        mode: 'chat',
        isPinned: false,
        isFavorite: false,
        tagsJson: '[]',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: HistoryPage(
        loadConversations: () async {
          loadCount++;
          return conversations;
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'a');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(searchField, 'alpha');
    await tester.pump(const Duration(milliseconds: 219));
    expect(loadCount, 1);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(loadCount, 2);
  });
}
