// Permanent regression coverage: in-memory databases and isolated temporary files.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:mobile_agent/infrastructure/files/vault_exporter_io.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/chat_controller.dart';
import 'package:mobile_agent/application/providers.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config.dart';
import 'package:mobile_agent/infrastructure/providers/provider_config_store.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/application/conversation_fork_service.dart';
import 'package:mobile_agent/domain/history_load_result.dart';

Future<Conversation> seed(AppDatabase db, String id, int count) async {
  final now = DateTime(2026, 1, 1);
  final c = Conversation(
      id: id,
      title: id,
      agentId: null,
      mode: 'chat',
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now);
  await db.saveConversation(c);
  await db.transaction(() async {
    for (var i = 0; i < count; i++) {
      await db.insertMessage(MessagesCompanion.insert(
          id: '$id-$i',
          conversationId: id,
          role: i.isEven ? 'user' : 'assistant',
          content: '$id-content-$i',
          createdAt: now.add(Duration(seconds: i))));
    }
  });
  return c;
}

class Config extends ProviderConfigStore {
  @override
  Future<ProviderConfig> load() async => const ProviderConfig(
      baseUrl: 'https://api.openai.com/v1', model: 'demo', apiKey: '');
  @override
  Future<String> readToolKey(String name) async => '';
}

ProviderContainer setup(AppDatabase db) {
  final c = ProviderContainer(overrides: [
    databaseProvider.overrideWith((ref) async => db),
    providerConfigStoreProvider.overrideWith((ref) => Config()),
  ]);
  addTearDown(() async {
    c.dispose();
    await db.close();
  });
  return c;
}

Future<void> waitForInitialization(ProviderContainer container) async {
  if (!container.read(chatControllerProvider).loading) return;
  final ready = Completer<void>();
  final subscription = container.listen(chatControllerProvider, (_, next) {
    if (!next.loading && !ready.isCompleted) ready.complete();
  });
  try {
    await ready.future.timeout(const Duration(seconds: 10));
  } finally {
    subscription.close();
  }
}

class DelayedDatabase extends AppDatabase {
  DelayedDatabase() : super(NativeDatabase.memory());
  final requested = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<(Message, int)>> messagesPage(String id,
      {DateTime? before, int? beforeRowId, int? limit}) async {
    final rows = await super.messagesPage(id,
        before: before, beforeRowId: beforeRowId, limit: limit);
    if (id == 'a' && before != null) {
      requested.complete();
      await release.future;
    }
    return rows;
  }
}

class TempPathProvider extends PathProviderPlatform {
  TempPathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class DelayedMutationDatabase extends AppDatabase {
  DelayedMutationDatabase() : super(NativeDatabase.memory());
  final requested = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> deleteTrailingAssistantAndTool(String id) async {
    requested.complete();
    await release.future;
    await super.deleteTrailingAssistantAndTool(id);
  }

  @override
  Future<void> editMessageAndTruncate(
      String id, String anchor, String content) async {
    requested.complete();
    await release.future;
    await super.editMessageAndTruncate(id, anchor, content);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final edit in [true, false]) {
    test(
        '${edit ? "edit" : "regenerate"} completion cannot overwrite another conversation',
        () async {
      final db = DelayedMutationDatabase();
      final a = await seed(db, 'a', 4);
      final b = await seed(db, 'b', 4);
      final c = setup(db);
      final ctrl = c.read(chatControllerProvider.notifier);
      await waitForInitialization(c);
      await ctrl.switchConversation(a);
      final operation = edit
          ? ctrl.editAndResend(
              messageIndex: 0,
              newText: 'edited',
              approveTool: (_, __, ___) async => ToolApproval.allowOnce)
          : ctrl.regenerate(
              approveTool: (_, __, ___) async => ToolApproval.allowOnce);
      await db.requested.future;
      await ctrl.switchConversation(b);
      db.release.complete();
      await operation;
      final state = c.read(chatControllerProvider);
      expect(state.conversationId, 'b');
      expect(state.messages.map((m) => m.id), ['b-0', 'b-1', 'b-2', 'b-3']);
      expect(state.running, isFalse);
      expect(await db.messagesFor('b'), hasLength(4));
    });
  }

  testWidgets('controller replacement invalidates a pending history request',
      (tester) async {
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final pending = Completer<HistoryLoadResult>();
    var secondCalls = 0;
    Future<void> pump(ScrollController controller,
        Future<HistoryLoadResult> Function() load) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ChatMessageList(
        sessionKey: 'same',
        controller: controller,
        messages: List.generate(
            20,
            (i) => ChatMessage(
                id: 'm$i',
                role: MessageRole.user,
                parts: [MessagePart.text('message $i')])),
        running: false,
        onLongPress: (_) {},
        onRegenerate: () {},
        onLoadHistory: load,
      ))));
      await tester.pumpAndSettle();
    }

    await pump(first, () => pending.future);
    first.jumpTo(1);
    await tester.pump();
    await pump(second, () async {
      secondCalls++;
      return HistoryLoadResult.failed;
    });
    expect(first.hasClients, isFalse);
    second.jumpTo(2);
    await tester.pumpAndSettle();
    expect(secondCalls, 1);
    pending.complete(HistoryLoadResult.exhausted);
    await tester.pumpAndSettle();
    second.jumpTo(3);
    await tester.pumpAndSettle();
    expect(secondCalls, 2);
  });

  test(
      'Regression: edit paginated message must not rewrite the first database message',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final conv = await seed(db, 'a', 240);
    final c = setup(db);
    final ctrl = c.read(chatControllerProvider.notifier);
    await waitForInitialization(c);
    await ctrl.switchConversation(conv);
    expect(c.read(chatControllerProvider).messages.first.id, 'a-40');
    await ctrl.editAndResend(
        messageIndex: 0,
        newText: 'EDITED',
        approveTool: (_, __, ___) async => ToolApproval.allowOnce);
    final rows = await db.messagesFor('a');
    expect(rows.first.content, 'a-content-0',
        reason: 'editing a-40 must preserve earlier a-0 through a-39');
  });

  test('Regression: fork uses visible message id rather than global index',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final conv = await seed(db, 'a', 240);
    final c = setup(db);
    final ctrl = c.read(chatControllerProvider.notifier);
    await waitForInitialization(c);
    await ctrl.switchConversation(conv);
    expect(c.read(chatControllerProvider).messages.first.id, 'a-40');
    final fork = await ctrl.forkFromMessage(0);
    final rows = await db.messagesFor(fork.id);
    expect(rows.length, 41,
        reason: 'fork should include source messages 0..40');
  });

  test(
      'Regression: old pagination result must not contaminate switched conversation',
      () async {
    final db = DelayedDatabase();
    final a = await seed(db, 'a', 240);
    final b = await seed(db, 'b', 10);
    final c = setup(db);
    final ctrl = c.read(chatControllerProvider.notifier);
    await waitForInitialization(c);
    await ctrl.switchConversation(a);
    final older = ctrl.loadOlderMessages();
    await db.requested.future;
    await ctrl.switchConversation(b);
    db.release.complete();
    await older;
    final s = c.read(chatControllerProvider);
    expect(s.conversationId, 'b');
    expect(s.messages.every((m) => m.id!.startsWith('b-')), isTrue,
        reason: 'late page from A must be discarded after switching to B');
  });

  test('Regression: vault skill package name must stay under skills root',
      () async {
    final root = await Directory.systemTemp.createTemp('nexus-audit-isolated-');
    final oldProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = TempPathProvider(root.path);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      PathProviderPlatform.instance = oldProvider;
      await db.close();
      await root.delete(recursive: true);
    });
    final now = DateTime(2026, 1, 1);
    final pack = SkillPack(
        id: 'audit-pack',
        name: '../escaped',
        description: '',
        author: null,
        version: '0.0.1',
        source: 'audit',
        repo: '',
        ref: '',
        subPath: null,
        installRoot: '',
        fileListJson: '[]',
        enabled: true,
        installedAt: now,
        updatedAt: now,
        sha256: '');
    await seed(db, 'preserved', 2);
    await expectLater(
        restoreVault(
            db,
            {
              'version': 2,
              'skillPacks': [pack.toJson()],
              'skillFiles': {
                'audit-pack': {'marker.txt': base64Encode(utf8.encode('audit'))}
              },
            },
            providerStore: Config()),
        throwsA(isA<FormatException>()));
    expect(await db.findConversation('preserved'), isNotNull);
    final escaped = File(p.join(root.path, 'escaped', 'marker.txt'));
    expect(await escaped.exists(), isFalse,
        reason: 'untrusted pack.name must not escape the skills root');
  });

  test('fork failure rolls back its newly created conversation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db, 'source', 2);
    await expectLater(
        const ConversationForkService().fork(
            db: db, sourceConversationId: 'source', forkMessageId: 'missing'),
        throwsStateError);
    expect(await db.recentConversations(), hasLength(1));
  });

  test('an anchor from another conversation cannot truncate messages',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db, 'a', 3);
    await seed(db, 'b', 3);
    await expectLater(
        db.editMessageAndTruncate('b', 'a-0', 'bad'), throwsStateError);
    expect(await db.messagesFor('a'), hasLength(3));
    expect(await db.messagesFor('b'), hasLength(3));
  });

  testWidgets('a transient pagination failure remains retryable',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatMessageList(
      messages: List.generate(
          20,
          (i) => ChatMessage(
              role: MessageRole.user, parts: [MessagePart.text('message $i')])),
      controller: scroll,
      running: false,
      onLongPress: (_) {},
      onRegenerate: () {},
      onLoadHistory: () async {
        calls++;
        return HistoryLoadResult.failed;
      },
    ))));
    await tester.pumpAndSettle();
    scroll.jumpTo(1);
    await tester.pumpAndSettle();
    scroll.jumpTo(2);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets(
      'Regression: exhausted pagination must reset on conversation switch',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var aCalls = 0;
    var bCalls = 0;
    Future<void> pump(String session, Future<bool> Function() load) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ChatMessageList(
        sessionKey: session,
        messages: List.generate(
            20,
            (i) => ChatMessage(
                role: MessageRole.user,
                parts: [MessagePart.text('$session message $i')])),
        controller: scroll,
        running: false,
        onLongPress: (_) {},
        onRegenerate: () {},
        onLoadOlder: load,
      ))));
      await tester.pumpAndSettle();
    }

    await pump('a', () async {
      aCalls++;
      return false;
    });
    scroll.jumpTo(1);
    await tester.pumpAndSettle();
    expect(aCalls, 1);
    await pump('b', () async {
      bCalls++;
      return false;
    });
    scroll.jumpTo(2);
    await tester.pumpAndSettle();
    expect(bCalls, 1, reason: 'B pagination must not inherit A exhausted flag');
  });
}
