// Debug-only emulator checks. No host business tests or user DB writes.
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/global_search_service.dart';
import '../application/knowledge_service.dart';
import '../application/memory_service.dart';
import '../application/providers.dart';
import '../infrastructure/database/app_database.dart';
import '../presentation/search/global_search_page.dart';
import '../presentation/history/history_page.dart';

bool _registered = false;
void registerGlobalSearchChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.globalSearchContract',
      (method, params) async =>
          ServiceExtensionResponse.result(jsonEncode(await _checks())));
  registerExtension('ext.nexus.globalSearchFixture', (method, params) async {
    final mode = params['mode'];
    if (!const ['open-search', 'open-history', 'close'].contains(mode)) {
      return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 'Fixed modes only');
    }
    if (mode == 'close') {
      if (_route != null) _navigator?.removeRoute(_route!);
    } else {
      await _openFixture(mode == 'open-history');
    }
    return ServiceExtensionResponse.result(
        jsonEncode({'fixtureOnly': true, 'mode': mode}));
  });
}

Future<void> _conversation(AppDatabase db, String id, String title, DateTime at,
        {String? project}) =>
    db.insertConversation(ConversationsCompanion.insert(
        id: id,
        title: Value(title),
        projectId: Value(project),
        createdAt: at,
        updatedAt: at));
Future<void> _seed(AppDatabase db) async {
  final now = DateTime.utc(2026, 10, 19, 12), old = DateTime.utc(2020, 1, 1);
  await _conversation(db, 'old', 'Early source conversation', old,
      project: 'P-A');
  await db.saveMessage(Message(
      id: 'old-message',
      conversationId: 'old',
      role: 'user',
      content: 'EARLY_SOURCE_MARKER true early body',
      toolCallId: null,
      toolCallsJson: null,
      reasoningContent: null,
      displayMetadataJson: null,
      createdAt: old));
  for (var i = 0; i < 62; i++) {
    await _conversation(db, 'recent-$i', 'PAGINATION_MARKER recent $i', now);
  }
}

Future<Map<String, dynamic>> _checks() async {
  final db = AppDatabase(NativeDatabase.memory());
  final service = GlobalSearchService(db);
  final now = DateTime.utc(2026, 10, 19, 12);
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<bool> Function() body) async {
    try {
      cases.add({'name': name, 'passed': await body()});
    } catch (_) {
      cases.add({'name': name, 'passed': false, 'unexpectedError': true});
    }
  }

  try {
    await _seed(db);
    await check(
        'history_searches_old_message_body_beyond_recent_pages',
        () async =>
            (await db.searchConversations(query: 'EARLY_SOURCE_MARKER'))
                .single
                .id ==
            'old');
    await check('global_search_returns_real_early_message_source', () async {
      final result = await service.search(query: 'EARLY_SOURCE_MARKER');
      return result.items.single.id == 'old-message' &&
          (await service.readSource(result.items.single))!
              .contains('true early body');
    });
    await _conversation(
        db, 'indexed-conversation', 'INDEX_MARKER conversation', now,
        project: 'P-A');
    await db.saveMessage(Message(
        id: 'indexed-message',
        conversationId: 'indexed-conversation',
        role: 'assistant',
        content: 'INDEX_MARKER message',
        toolCallId: null,
        toolCallsJson: null,
        reasoningContent: null,
        displayMetadataJson: null,
        createdAt: now));
    await db.saveTask(Task(
        id: 'indexed-task',
        conversationId: 'indexed-conversation',
        projectId: 'P-A',
        stateRevision: 0,
        type: 'agent',
        status: 'paused',
        requestJson: '{"title":"INDEX_MARKER task"}',
        progressJson: '{}',
        resumeCount: 0,
        createdAt: now,
        updatedAt: now));
    await db.insertProject(ProjectsCompanion.insert(
        id: 'P-A',
        name: 'INDEX_MARKER project',
        canonicalRootPath: '/isolated/fixture',
        createdAt: now,
        updatedAt: now));
    await db.saveArtifactRecord({
      'id': 'indexed-artifact',
      'projectId': 'P-A',
      'taskId': 'indexed-task',
      'runId': 'fixture',
      'kind': 'file',
      'relativePath': 'INDEX_MARKER.txt',
      'hash': 'synthetic',
      'bytes': 0,
      'inspectionJson': {},
      'createdAt': now.toIso8601String()
    });
    final doc = await KnowledgeService().ingest(
        db: db,
        name: 'INDEX_MARKER knowledge',
        sourceType: 'paste',
        content: 'ONLY_KNOWLEDGE_BODY');
    await MemoryService().add(database: db, content: 'INDEX_MARKER memory');
    await check(
        'all_seven_types_share_database_query',
        () async =>
            (await service.search(query: 'INDEX_MARKER'))
                .items
                .map((h) => h.kind)
                .toSet()
                .length ==
            7);
    await check(
        'type_filter_applies_before_page_limit',
        () async =>
            (await service.search(
                    query: 'INDEX_MARKER', kind: SearchKind.task, limit: 1))
                .items
                .single
                .id ==
            'indexed-task');
    await check('project_filter_does_not_assign_global_material_to_project',
        () async {
      final items =
          (await service.search(query: 'INDEX_MARKER', projectId: 'P-A')).items;
      return items.length == 5 && items.every((h) => h.projectId == 'P-A');
    });
    await check(
        'exclusive_date_range_filters_old_sources',
        () async => (await service.search(
                query: 'EARLY_SOURCE_MARKER',
                since: now.subtract(const Duration(days: 1))))
            .items
            .isEmpty);
    await check('like_metacharacters_are_literal_not_wildcards', () async {
      await MemoryService().add(database: db, content: r'literal 100%_\VALUE');
      await MemoryService().add(database: db, content: 'literal 100XXVALUE');
      return (await service.search(query: r'100%_\VALUE')).items.length == 1;
    });
    await check('cursor_pages_same_timestamp_without_duplicates_or_recent_cap',
        () async {
      SearchCursor? cursor;
      final keys = <String>[];
      do {
        final page = await service.search(
            query: 'PAGINATION_MARKER', limit: 7, after: cursor);
        keys.addAll(page.items.map((h) => h.key));
        cursor = page.next;
        if (keys.length > 100) return false;
      } while (cursor != null);
      return keys.length == 62 && keys.toSet().length == 62;
    });
    await check('insert_before_cursor_does_not_shift_next_page', () async {
      final first = await service.search(query: 'PAGINATION_MARKER', limit: 7);
      await _conversation(db, 'newer', 'PAGINATION_MARKER newest',
          now.add(const Duration(hours: 1)));
      final second = await service.search(
          query: 'PAGINATION_MARKER', limit: 7, after: first.next);
      return second.items.length == 7 &&
          !second.items.any((h) => first.items.any((a) => a.key == h.key)) &&
          !second.items.any((h) => h.id == 'newer');
    });
    await check('knowledge_body_match_has_real_bounded_chunk_preview',
        () async {
      final hit =
          (await service.search(query: 'ONLY_KNOWLEDGE_BODY')).items.single;
      final source = await service.readSource(hit);
      return hit.id == doc.id &&
          source!.contains('${doc.id}:chunk:0') &&
          source.contains('ONLY_KNOWLEDGE_BODY');
    });
    await check('deleted_source_cannot_be_opened_from_stale_hit', () async {
      final hit =
          (await service.search(query: 'INDEX_MARKER', kind: SearchKind.task))
              .items
              .single;
      await (db.delete(db.tasks)..where((t) => t.id.equals(hit.id))).go();
      return await service.readSource(hit) == null;
    });
    await check('invalid_inputs_rejected_without_sql_or_network', () async {
      var rejected = 0;
      for (final size in [0, 101]) {
        try {
          await service.search(limit: size);
        } on ArgumentError {
          rejected++;
        }
      }
      try {
        await service.search(query: 'x' * 513);
      } on ArgumentError {
        rejected++;
      }
      try {
        await service.search(since: now, before: now);
      } on ArgumentError {
        rejected++;
      }
      return rejected == 4;
    });
  } finally {
    KnowledgeService.invalidate(db);
    await db.close();
  }
  return {
    'type': 'GlobalSearchContractChecks',
    'fixtureOnly': true,
    'modelCalls': 0,
    'platformMutations': 0,
    'persistentDataMutations': 0,
    'cases': cases,
    'passed': cases.where((r) => r['passed'] == true).length,
    'total': cases.length
  };
}

Route<void>? _route;
NavigatorState? _navigator;
Future<void> _openFixture(bool history) async {
  if (_route != null) throw StateError('Close owned fixture first');
  NavigatorState? navigator;
  void visit(Element e) {
    if (navigator != null) return;
    if (e is StatefulElement && e.state is NavigatorState) {
      navigator = e.state as NavigatorState;
    } else {
      e.visitChildElements(visit);
    }
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  if (navigator == null) throw StateError('No app navigator');
  final db = AppDatabase(NativeDatabase.memory());
  try {
    await _seed(db);
    final route = MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
            overrides: [databaseProvider.overrideWith((ref) async => db)],
            child: Scaffold(
                appBar: AppBar(title: const Text('隔离验收 · 本地搜索')),
                body: history
                    ? HistoryPage(loadDatabase: () async => db)
                    : const GlobalSearchPage(
                        initialQuery: 'EARLY_SOURCE_MARKER', readOnly: true))));
    _route = route;
    _navigator = navigator;
    unawaited(navigator!.push(route).whenComplete(() async {
      if (identical(_route, route)) {
        _route = null;
        _navigator = null;
      }
      await db.close();
    }));
  } catch (_) {
    await db.close();
    rethrow;
  }
}
