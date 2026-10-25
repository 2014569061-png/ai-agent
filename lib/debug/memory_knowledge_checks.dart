// Fixed emulator checks and UI fixtures; only disposable memory storage is used.
import 'dart:async';
import 'dart:io';
import '../application/global_search_service.dart';
import '../infrastructure/files/vault_exporter_io.dart';
import 'dart:convert';
import 'dart:developer';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/memory_service.dart';
import '../application/knowledge_service.dart';
import '../application/providers.dart';
import '../infrastructure/database/app_database.dart';
import '../presentation/memory/memory_page.dart';
import '../presentation/knowledge/knowledge_page.dart';

class _Memory extends MemoryService {
  bool enabled = true;
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }
}

class _Knowledge extends KnowledgeService {
  bool enabled = true;
  bool failNextIngest = false;
  @override
  Future<KnowledgeDoc> ingest(
      {required AppDatabase db,
      required String name,
      required String sourceType,
      required String content,
      String? projectId}) async {
    if (failNextIngest) {
      failNextIngest = false;
      throw StateError('Synthetic ingest failure');
    }
    return super.ingest(
        db: db,
        name: name,
        sourceType: sourceType,
        content: content,
        projectId: projectId);
  }

  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }
}

bool _registered = false;
void registerMemoryKnowledgeChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.knowledgeScopeContract',
      (method, params) async => ServiceExtensionResponse.result(
          jsonEncode(await _knowledgeScopeChecks())));
  registerExtension(
      'ext.nexus.memoryKnowledgeContract',
      (method, params) async =>
          ServiceExtensionResponse.result(jsonEncode(await _checks())));
  registerExtension('ext.nexus.memoryKnowledgeFixture', (method, params) async {
    final mode = params['mode'];
    if (!const [
      'open-memory',
      'open-knowledge',
      'close',
      'fail-next-knowledge',
      'inspect-knowledge'
    ].contains(mode)) {
      return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 'Fixed fixture modes only');
    }
    if (mode == 'fail-next-knowledge') {
      if (_fixtureKnowledge == null) throw StateError('Open fixture first');
      _fixtureKnowledge!.failNextIngest = true;
    } else if (mode == 'inspect-knowledge') {
      final db = _fixtureDatabase;
      if (db == null || _fixtureKnowledge == null) {
        throw StateError('Open fixture first');
      }
      final docs = (await db.allKnowledgeDocs())
          .where((d) => d.name == 'UI_KNOWLEDGE_DOCUMENT')
          .toList();
      if (docs.length != 1 ||
          (await db.knowledgeDocumentScopes())[docs.single.id] != 'fixture-A' ||
          (await db.chunksFor(docs.single.id)).single.content !=
              'UI_KNOWLEDGE_MARKER' ||
          (await _fixtureKnowledge!
                  .buildInjectionBlock(db, 'UI_KNOWLEDGE_MARKER'))
              .contains('UI_KNOWLEDGE_MARKER') ||
          !(await _fixtureKnowledge!.buildInjectionBlock(
                  db, 'UI_KNOWLEDGE_MARKER',
                  projectId: 'fixture-A'))
              .contains('UI_KNOWLEDGE_MARKER')) {
        throw StateError('Synthetic scoped import mismatch');
      }
    } else if (mode == 'close') {
      if (_route != null) _navigator?.removeRoute(_route!);
    } else {
      await _openFixture(mode == 'open-memory');
    }
    return ServiceExtensionResponse.result(
        jsonEncode({'fixtureOnly': true, 'mode': mode}));
  });
}

Future<Map<String, dynamic>> _checks() async {
  final db = AppDatabase(NativeDatabase.memory());
  final memory = _Memory();
  final knowledge = _Knowledge();
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<bool> Function() body) async {
    try {
      cases.add({'name': name, 'passed': await body()});
    } catch (_) {
      cases.add({'name': name, 'passed': false, 'unexpectedError': true});
    }
  }

  try {
    await check(
        'source_labels_never_call_agent_manual',
        () async =>
            MemoryService.sourceLabel('agent') == '助手写入' &&
            MemoryService.sourceLabel('manual') == '手动录入' &&
            MemoryService.sourceLabel('auto') == '自动沉淀' &&
            MemoryService.sourceLabel('future') == '未知来源');
    await check(
        'scope_defaults_and_malformed_project_prefix',
        () async =>
            !MemoryService.visibleInContext('project:A') &&
            !MemoryService.visibleInContext(' project:A ', projectId: '') &&
            !MemoryService.visibleInContext('project:', projectId: '') &&
            !MemoryService.visibleInContext('PROJECT:B', projectId: 'A') &&
            MemoryService.visibleInContext('general'));
    final global =
        await memory.add(database: db, content: 'GLOBAL_MARKER', importance: 5);
    await memory.add(
        database: db, content: 'PROJECT_A_MARKER', category: 'project:A');
    final b = await memory.add(
        database: db, content: 'PROJECT_B_MARKER', category: 'project:B');
    await check('no_project_context_excludes_all_project_records', () async {
      final block = await memory.buildInjectionBlock(db);
      return block.contains('GLOBAL_MARKER') &&
          !block.contains('PROJECT_A_MARKER') &&
          !block.contains('PROJECT_B_MARKER') &&
          block.contains('bytes=13');
    });
    await check('selected_project_only_includes_global_and_own', () async {
      final block = await memory.buildInjectionBlock(db, projectId: 'A');
      return block.contains('GLOBAL_MARKER') &&
          block.contains('PROJECT_A_MARKER') &&
          !block.contains('PROJECT_B_MARKER');
    });
    await check('other_project_changes_do_not_change_context_fingerprint',
        () async {
      final before = await memory.buildInjectionBlock(db, projectId: 'A');
      await memory.update(db, b.copyWith(content: 'B_CHANGED'));
      return before == await memory.buildInjectionBlock(db, projectId: 'A');
    });
    await check('revision_changes_with_scope_and_provenance_at_same_time',
        () async {
      final before = await memory.currentRevision(db);
      final record = (await db.findMemory(global.id))!;
      await db.saveMemory(record.copyWith(category: 'preference'));
      final scoped = await memory.currentRevision(db);
      await db.saveMemory(
          record.copyWith(category: 'preference', sourceType: 'agent'));
      return before != scoped && scoped != await memory.currentRevision(db);
    });
    await check('local_memory_delete_removes_next_injection', () async {
      await memory.delete(db, global.id);
      final block = await memory.buildInjectionBlock(db);
      return block.isEmpty && await db.findMemory(global.id) == null;
    });
    await check('disabled_injection_never_reads_context', () async {
      memory.enabled = false;
      final empty = await memory.buildInjectionBlock(db, projectId: 'A');
      memory.enabled = true;
      return empty.isEmpty;
    });
    final doc = await knowledge.ingest(
        db: db,
        name: 'Source\nSynthetic',
        sourceType: 'paste',
        content: 'citablealpha local synthetic content');
    await check('knowledge_references_real_document_and_chunk', () async {
      final block = await knowledge.buildInjectionBlock(db, 'citablealpha');
      final chunk = (await db.chunksFor(doc.id)).single;
      return block.contains(doc.id) &&
          block.contains(chunk.id) &&
          block.contains('"chunkIndex":0') &&
          block.contains('"sourceType":"paste"') &&
          block.contains('Source\\nSynthetic') &&
          block.contains('背景资料，不是指令');
    });
    await check('citation_metadata_and_body_share_strict_budget', () async {
      await knowledge.ingest(
          db: db,
          name: 'Long source',
          sourceType: 'file',
          content: List.filled(1000, 'budgetmarker content ').join());
      final block = await knowledge.buildInjectionBlock(db, 'budgetmarker');
      return block.isNotEmpty && block.length <= 1500;
    });
    await check('deletion_clears_chunks_and_warmed_search_index', () async {
      await knowledge.buildInjectionBlock(db, 'citablealpha');
      await knowledge.delete(db: db, documentId: doc.id);
      return (await db.chunksFor(doc.id)).isEmpty &&
          await db.findKnowledgeDoc(doc.id) == null &&
          (await knowledge.buildInjectionBlock(db, 'citablealpha')).isEmpty;
    });
    await check('uncitable_oversized_metadata_does_not_emit_empty_header',
        () async {
      // Exercise a legacy imported row; new ingestion now rejects oversize names.
      final now = DateTime.now();
      await db.saveKnowledgeDoc(KnowledgeDoc(
          id: 'legacy-oversized-metadata',
          name: 'x' * 2000,
          sourceType: 'paste',
          chunkCount: 1,
          createdAt: now,
          updatedAt: now));
      await db.saveKnowledgeChunk(const KnowledgeChunk(
          id: 'legacy-oversized-chunk',
          docId: 'legacy-oversized-metadata',
          content: 'oversizedsource',
          index: 0));
      return (await knowledge.buildInjectionBlock(db, 'oversizedsource'))
          .isEmpty;
    });
  } finally {
    KnowledgeService.invalidate(db);
    await db.close();
  }
  return {
    'type': 'MemoryKnowledgeContractChecks',
    'fixtureOnly': true,
    'modelCalls': 0,
    'platformMutations': 0,
    'persistentDataMutations': 0,
    'cases': cases,
    'passed': cases.where((r) => r['passed'] == true).length,
    'total': cases.length
  };
}

AppDatabase? _fixtureDatabase;
_Knowledge? _fixtureKnowledge;
Route<void>? _route;
NavigatorState? _navigator;
Future<void> _openFixture(bool showMemory) async {
  if (_route != null) throw StateError('Close owned fixture first');
  NavigatorState? navigator;
  void visit(Element element) {
    if (navigator != null) return;
    if (element is StatefulElement && element.state is NavigatorState) {
      navigator = element.state as NavigatorState;
    } else {
      element.visitChildElements(visit);
    }
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  if (navigator == null) throw StateError('No app navigator');
  final db = AppDatabase(NativeDatabase.memory());
  final memory = _Memory();
  final knowledge = _Knowledge();
  try {
    final now = DateTime.now();
    await db.saveProject(Project(
        id: 'fixture-A',
        name: '隔离项目 A',
        canonicalRootPath: '/isolated/knowledge-ui-A',
        sourceKind: 'directory',
        projectKind: 'unknown',
        settingsJson: '{}',
        settingsVersion: 1,
        archived: false,
        createdAt: now,
        updatedAt: now));
    await memory.add(
        database: db,
        content: '隔离样例：助手记录的项目偏好，不调用模型。',
        category: 'project:fixture-A',
        sourceType: 'agent',
        sourceConversationId: 'fixture-conversation');
    await memory.add(
        database: db,
        content: '隔离样例：来源未识别，不能标成手动录入。',
        sourceType: 'legacy_unknown');
    await knowledge.ingest(
        db: db,
        name: '隔离来源样例',
        sourceType: 'paste',
        content: 'Synthetic source marker. 本地分块样例，仅供预览，不执行任务，不调用模型。');
    final route = MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
              overrides: [
                databaseProvider.overrideWith((ref) async => db),
                memoryServiceProvider.overrideWithValue(memory),
                knowledgeServiceProvider.overrideWithValue(knowledge)
              ],
              child: Scaffold(
                  appBar: AppBar(title: const Text('隔离验收 · 仅内存数据')),
                  body:
                      showMemory ? const MemoryPage() : const KnowledgePage()),
            ));
    _fixtureDatabase = db;
    _fixtureKnowledge = knowledge;
    _route = route;
    _navigator = navigator;
    unawaited(navigator!.push(route).whenComplete(() async {
      if (identical(_route, route)) {
        _fixtureDatabase = null;
        _fixtureKnowledge = null;
        _route = null;
        _navigator = null;
      }
      KnowledgeService.invalidate(db);
      await db.close();
    }));
  } catch (_) {
    KnowledgeService.invalidate(db);
    await db.close();
    rethrow;
  }
}

Future<Map<String, dynamic>> _knowledgeScopeChecks() async {
  final db = AppDatabase(NativeDatabase.memory());
  final service = _Knowledge();
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<bool> Function() body) async {
    try {
      cases.add({'name': name, 'passed': await body()});
    } catch (_) {
      cases.add({'name': name, 'passed': false, 'unexpectedError': true});
    }
  }

  Future<void> projects(AppDatabase target) async {
    final now = DateTime.now();
    for (final id in ['A', 'B']) {
      await target.saveProject(Project(
          id: id,
          name: 'Fixture $id',
          canonicalRootPath: '/isolated/knowledge-$id',
          sourceKind: 'directory',
          projectKind: 'unknown',
          settingsJson: '{}',
          settingsVersion: 1,
          archived: false,
          createdAt: now,
          updatedAt: now));
    }
  }

  try {
    await projects(db);
    final global = await service.ingest(
        db: db,
        name: 'Global',
        sourceType: 'paste',
        content: 'needle GLOBAL_KNOWLEDGE_MARKER');
    final a = await service.ingest(
        db: db,
        name: 'Project A',
        sourceType: 'file',
        content: 'needle A_KNOWLEDGE_MARKER',
        projectId: 'A');
    final b = await service.ingest(
        db: db,
        name: 'Project B',
        sourceType: 'paste',
        content: 'needle B_KNOWLEDGE_MARKER',
        projectId: 'B');
    await check('global_context_excludes_every_project_document', () async {
      final text = await service.buildInjectionBlock(db, 'needle');
      return text.contains('GLOBAL_KNOWLEDGE_MARKER') &&
          !text.contains('A_KNOWLEDGE_MARKER') &&
          !text.contains('B_KNOWLEDGE_MARKER');
    });
    await check('project_a_context_is_global_plus_exact_project', () async {
      final text =
          await service.buildInjectionBlock(db, 'needle', projectId: 'A');
      return text.contains('GLOBAL_KNOWLEDGE_MARKER') &&
          text.contains('A_KNOWLEDGE_MARKER') &&
          !text.contains('B_KNOWLEDGE_MARKER');
    });
    await check('project_b_context_has_separate_cached_index', () async {
      final text =
          await service.buildInjectionBlock(db, 'needle', projectId: 'B');
      return text.contains('GLOBAL_KNOWLEDGE_MARKER') &&
          text.contains('B_KNOWLEDGE_MARKER') &&
          !text.contains('A_KNOWLEDGE_MARKER');
    });
    await check('citations_preserve_source_type_and_project_provenance',
        () async {
      final text =
          await service.buildInjectionBlock(db, 'needle', projectId: 'A');
      return text.contains('"projectId":"A"') &&
          text.contains('"sourceType":"file"') &&
          text.contains(a.id);
    });
    await check(
        'new_ingest_enforces_name_content_and_source_bounds_without_writes',
        () async {
      final before = (await db.allKnowledgeDocs()).length;
      var rejected = 0;
      for (var i = 0; i < 3; i++) {
        try {
          await service.ingest(
              db: db,
              name: i == 0 ? 'x' * 257 : 'Bounded title',
              content: i == 1 ? 'x' * 1000001 : 'bounded content',
              sourceType: i == 2 ? 'x' * 65 : 'paste');
        } on FormatException {
          rejected++;
        }
      }
      return rejected == 3 && (await db.allKnowledgeDocs()).length == before;
    });
    await check('missing_project_cannot_create_document_or_chunks', () async {
      final before = (await db.allKnowledgeDocs()).length;
      try {
        await service.ingest(
            db: db,
            name: 'Invalid',
            sourceType: 'paste',
            content: 'should not persist',
            projectId: 'missing');
        return false;
      } on StateError {
        return (await db.allKnowledgeDocs()).length == before;
      }
    });
    await check('scoped_ingest_and_durable_revision_roll_back_together',
        () async {
      final before = await db.currentKnowledgeRevision();
      final docs = (await db.allKnowledgeDocs()).length;
      try {
        await db.transaction(() async {
          await service.ingest(
              db: db,
              name: 'Rollback',
              sourceType: 'paste',
              content: 'rollback',
              projectId: 'A');
          throw StateError('synthetic rollback');
        });
      } on StateError catch (error) {
        if (error.message != 'synthetic rollback') rethrow;
      }
      return await db.currentKnowledgeRevision() == before &&
          (await db.allKnowledgeDocs()).length == docs &&
          (await db.knowledgeDocumentScopes()).length == 2;
    });
    await check('owner_search_project_filter_uses_real_document_binding',
        () async {
      final result = await GlobalSearchService(db)
          .search(query: 'needle', kind: SearchKind.knowledge, projectId: 'A');
      return result.items.length == 1 &&
          result.items.single.id == a.id &&
          result.items.single.projectId == 'A';
    });
    await check('owner_global_search_retains_full_library_visibility',
        () async {
      final result = await GlobalSearchService(db)
          .search(query: 'needle', kind: SearchKind.knowledge);
      return result.items
          .map((r) => r.id)
          .toSet()
          .containsAll([global.id, a.id, b.id]);
    });
    await check('scope_change_invalidates_cached_automatic_context', () async {
      final local = db.knowledgeGeneration;
      await db.bindKnowledgeDocument(a.id, 'B');
      final text =
          await service.buildInjectionBlock(db, 'needle', projectId: 'A');
      return !text.contains('A_KNOWLEDGE_MARKER') &&
          db.knowledgeGeneration == local;
    });
    await check('raw_chunk_update_is_detected_without_local_invalidation',
        () async {
      final local = db.knowledgeGeneration;
      await db.customStatement(
          'UPDATE knowledge_chunks SET content = ? WHERE doc_id = ?',
          ['needle UPDATED_GLOBAL_MARKER', global.id]);
      final text = await service.buildInjectionBlock(db, 'needle');
      return text.contains('UPDATED_GLOBAL_MARKER') &&
          !text.contains('GLOBAL_KNOWLEDGE_MARKER') &&
          db.knowledgeGeneration == local;
    });
    await check('deletion_cleans_scope_chunks_and_cached_results', () async {
      await service.buildInjectionBlock(db, 'needle', projectId: 'B');
      await service.delete(db: db, documentId: b.id);
      final text =
          await service.buildInjectionBlock(db, 'needle', projectId: 'B');
      return !text.contains('B_KNOWLEDGE_MARKER') &&
          (await db.chunksFor(b.id)).isEmpty &&
          !(await db.knowledgeDocumentScopes()).containsKey(b.id);
    });
    await check('orphan_chunk_is_never_a_citable_source', () async {
      final m = await service.ingest(
          db: db,
          name: 'Orphan',
          sourceType: 'paste',
          content: 'orphanunique secret');
      await db
          .customStatement('DELETE FROM knowledge_docs WHERE id = ?', [m.id]);
      return (await db.chunksFor(m.id)).isNotEmpty &&
          (await service.buildInjectionBlock(db, 'orphanunique')).isEmpty;
    });
    await check('explicit_invalidation_does_not_change_scope_visibility',
        () async {
      KnowledgeService.invalidate(db);
      final text = await service.buildInjectionBlock(db, 'needle');
      return !text.contains('A_KNOWLEDGE_MARKER') &&
          !text.contains('B_KNOWLEDGE_MARKER');
    });
    await check('vault_round_trip_keeps_project_scope_not_globalizes_it',
        () async {
      final restored = AppDatabase(NativeDatabase.memory());
      try {
        final backup = await buildVaultJson(db);
        await restoreVault(restored, backup);
        final globalText =
            await service.buildInjectionBlock(restored, 'needle');
        final scopedText = await service.buildInjectionBlock(restored, 'needle',
            projectId: 'B');
        return (await restored.knowledgeDocumentScopes())[a.id] == 'B' &&
            !globalText.contains('A_KNOWLEDGE_MARKER') &&
            scopedText.contains('A_KNOWLEDGE_MARKER');
      } finally {
        await restored.close();
      }
    });
    await check('malformed_scope_is_rejected_before_restore_modifies_data',
        () async {
      final before = await db.currentKnowledgeRevision();
      try {
        await restoreVault(db, {
          'version': 2,
          'knowledgeScopes': [
            {'docId': 'missing', 'projectId': 'A'}
          ]
        });
        return false;
      } on FormatException {
        return await db.currentKnowledgeRevision() == before;
      }
    });
    await check('legacy_vault_without_scope_keeps_legacy_global_semantics',
        () async {
      final restored = AppDatabase(NativeDatabase.memory());
      try {
        final doc = (await db.findKnowledgeDoc(global.id))!;
        await restoreVault(restored, {
          'version': 1,
          'knowledgeDocs': [doc.toJson()],
          'knowledgeChunks': [
            for (final c in await db.chunksFor(global.id)) c.toJson()
          ]
        });
        return (await restored.knowledgeDocumentScopes()).isEmpty &&
            (await service.buildInjectionBlock(restored, 'needle'))
                .contains('UPDATED_GLOBAL_MARKER');
      } finally {
        await restored.close();
      }
    });
    final dir =
        await Directory.systemTemp.createTemp('nexus-knowledge-scope-fixture-');
    AppDatabase? reader, writer;
    try {
      final file = File('${dir.path}/shared.sqlite');
      reader = AppDatabase(NativeDatabase(file));
      writer = AppDatabase(NativeDatabase(file));
      final r = reader, w = writer;
      await projects(r);
      final doc = await service.ingest(
          db: r,
          name: 'Across connections',
          sourceType: 'paste',
          content: 'crossneedle CROSS_OLD');
      await service.buildInjectionBlock(r, 'crossneedle');
      await check('second_connection_content_commit_invalidates_first_cache',
          () async {
        final local = r.knowledgeGeneration;
        await w.customStatement(
            'UPDATE knowledge_chunks SET content = ? WHERE doc_id = ?',
            ['crossneedle CROSS_NEW', doc.id]);
        final text = await service.buildInjectionBlock(r, 'crossneedle');
        return text.contains('CROSS_NEW') &&
            !text.contains('CROSS_OLD') &&
            local == r.knowledgeGeneration;
      });
      await check('second_connection_scope_commit_prevents_global_recall',
          () async {
        await w.bindKnowledgeDocument(doc.id, 'A');
        return (await service.buildInjectionBlock(r, 'crossneedle')).isEmpty &&
            (await service.buildInjectionBlock(r, 'crossneedle',
                    projectId: 'A'))
                .contains('CROSS_NEW');
      });
      await check('second_connection_delete_prevents_stale_citation', () async {
        await w.deleteKnowledgeDoc(doc.id);
        return (await service.buildInjectionBlock(r, 'crossneedle',
                projectId: 'A'))
            .isEmpty;
      });
    } finally {
      await reader?.close();
      await writer?.close();
      await dir.delete(recursive: true);
    }
    await check('schema_28_upgrade_preserves_global_legacy_documents',
        () async {
      final dir = await Directory.systemTemp
          .createTemp('nexus-knowledge-upgrade-fixture-');
      final file = File('${dir.path}/legacy.sqlite');
      AppDatabase? current;
      try {
        current = AppDatabase(NativeDatabase(file));
        final doc = await service.ingest(
            db: current,
            name: 'Legacy',
            sourceType: 'paste',
            content: 'migrationneedle LEGACY_GLOBAL');
        final triggers = await current
            .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'nexus_knowledge_%'")
            .get();
        for (final trigger in triggers) {
          await current.customStatement(
              'DROP TRIGGER "${trigger.read<String>('name')}"');
        }
        await current.customStatement('DROP TABLE knowledge_doc_scopes');
        await current.customStatement('DROP TABLE knowledge_revision');
        await current.customStatement('PRAGMA user_version = 28');
        await current.close();
        current = null;
        current = AppDatabase(NativeDatabase(file));
        return (await current.findKnowledgeDoc(doc.id)) != null &&
            (await current.knowledgeDocumentScopes()).isEmpty &&
            (await service.buildInjectionBlock(current, 'migrationneedle'))
                .contains('LEGACY_GLOBAL');
      } finally {
        await current?.close();
        await dir.delete(recursive: true);
      }
    });
  } finally {
    await db.close();
  }
  return {
    'type': 'KnowledgeScopeContractChecks',
    'fixtureOnly': true,
    'modelCalls': 0,
    'platformMutations': 0,
    'persistentDataMutations': 0,
    'cases': cases,
    'passed': cases.where((c) => c['passed'] == true).length,
    'total': cases.length
  };
}
