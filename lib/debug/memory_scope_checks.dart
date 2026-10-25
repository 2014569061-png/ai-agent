import 'dart:convert';
import 'dart:io';
import '../infrastructure/database/memory_forget_store.dart';
import '../infrastructure/files/vault_exporter_io.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/providers.dart';
import '../presentation/memory/memory_page.dart';
import 'dart:developer';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import '../application/memory_service.dart';
import '../application/scoped_memory_access.dart';
import '../application/approval_policy.dart';
import '../domain/models.dart';
import '../domain/tool_codes.dart';
import '../domain/tool_result.dart';
import '../infrastructure/database/app_database.dart';
import '../infrastructure/tools/core_tools.dart';

bool _registered = false;
void registerMemoryScopeChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.memoryScopeContract',
      (method, params) async =>
          ServiceExtensionResponse.result(jsonEncode(await _checks())));
  registerExtension(
      'ext.nexus.memoryScopeFixture',
      (method, params) async => ServiceExtensionResponse.result(
          jsonEncode(await _fixture(params['mode']))));
}

Future<Map<String, dynamic>> _checks() async {
  final db = AppDatabase(NativeDatabase.memory());
  final service = MemoryService();
  final global = ScopedMemoryAccess(database: () async => db);
  final a = ScopedMemoryAccess(
      database: () async => db,
      projectId: 'A',
      sourceConversationId: 'fixture-conversation');
  final b = ScopedMemoryAccess(database: () async => db, projectId: 'B');
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<bool> Function() body) async {
    try {
      cases.add({'name': name, 'passed': await body()});
    } catch (_) {
      cases.add({'name': name, 'passed': false, 'unexpectedError': true});
    }
  }

  Future<ToolResult> write(ScopedMemoryAccess access, String? id,
          String? revision, String content, {String mode = 'replace'}) =>
      access.write(
          id: id,
          content: content,
          mode: mode,
          startLine: null,
          endLine: null,
          expectedRevision: revision);
  List<String> ids(ToolResult r) => (r.data!['items'] as List)
      .map((m) => (m as Map)['id'] as String)
      .toList();
  try {
    final g = await service.add(database: db, content: 'GLOBAL_RECORD');
    final ma = await service.add(
        database: db, content: 'PROJECT_A_RECORD', category: 'project:A');
    final mb = await service.add(
        database: db, content: 'PROJECT_B_RECORD', category: 'project:B');
    await check('explicit_global_tool_cannot_read_project_memories', () async {
      final r = await global.get('', 0, 100);
      return r.ok && ids(r).length == 1 && ids(r).single == g.id;
    });
    await check('project_tool_reads_global_and_exact_project_only', () async {
      final found = ids(await a.get('', 0, 100));
      return found.length == 2 &&
          found.contains(g.id) &&
          found.contains(ma.id) &&
          !found.contains(mb.id);
    });
    await check('foreign_resource_id_cannot_bypass_scope', () async {
      final r = await write(
          a,
          mb.id,
          (await a.get('', 0, 100)).data!['revision'] as String,
          'unauthorized');
      return r.code == ToolCodes.permissionRequired &&
          r.effect == ToolEffect.none &&
          (await db.findMemory(mb.id))!.content == 'PROJECT_B_RECORD';
    });
    await check('new_project_memory_is_not_silently_global', () async {
      final r = await a.remember('PROJECT_A_NEW', null);
      final row = await db.findMemory(r.data!['id'] as String);
      return r.ok &&
          row!.category == 'project:A' &&
          row.sourceConversationId == 'fixture-conversation' &&
          row.sourceType == 'agent';
    });
    await check('hidden_project_updates_do_not_change_visible_revision',
        () async {
      final revision = await service.currentRevision(db, scope: a.scope);
      final current = (await db.findMemory(mb.id))!;
      await service.update(db, current.copyWith(content: 'PROJECT_B_CORRECTED'),
          expectedMemory: current);
      return revision == await service.currentRevision(db, scope: a.scope);
    });
    await check('concurrent_same_revision_writes_have_one_winner', () async {
      final revision = (await a.get('', 0, 100)).data!['revision'] as String;
      final result = await Future.wait([
        write(a, ma.id, revision, 'winner one'),
        write(a, ma.id, revision, 'winner two')
      ]);
      return result.where((r) => r.ok).length == 1 &&
          result.where((r) => r.code == ToolCodes.revisionConflict).length == 1;
    });
    await check('stale_manual_edit_cannot_overwrite_current_content', () async {
      final old = (await db.findMemory(ma.id))!;
      await service.update(db, old.copyWith(content: 'new truth'),
          expectedMemory: old);
      try {
        await service.update(db, old.copyWith(content: 'stale draft'),
            expectedMemory: old);
        return false;
      } on MemoryConflictException {
        return (await db.findMemory(ma.id))!.content == 'new truth';
      }
    });
    await check('manual_edit_does_not_recreate_deleted_memory', () async {
      final old = await service.add(database: db, content: 'DELETE_ME');
      await service.delete(db, old.id);
      try {
        await service.update(db, old.copyWith(content: 'late edit'),
            expectedMemory: old);
        return false;
      } on MemoryConflictException {
        return await db.findMemory(old.id) == null;
      }
    });
    await check('disabled_memory_cannot_be_reenabled_by_scoped_write',
        () async {
      final current = (await db.findMemory(mb.id))!;
      await service.update(db, current.copyWith(enabled: false),
          expectedMemory: current);
      final revision = (await b.get('', 0, 100)).data!['revision'] as String;
      final r = await write(b, mb.id, revision, 'not allowed');
      return r.code == ToolCodes.permissionRequired &&
          !(await db.findMemory(mb.id))!.enabled;
    });
    await check('global_new_memory_retains_global_scope', () async {
      final r = await global.remember('GLOBAL_NEW', null);
      return (await db.findMemory(r.data!['id'] as String))!.category ==
          'general';
    });
    await check('page_100_reads_extra_sentinel_without_false_end', () async {
      for (var i = 0; i < 102; i++) {
        await service.add(database: db, content: 'PAGE_MARKER $i');
      }
      final first = await global.get('PAGE_MARKER', 0, 100);
      final second = await global.get('PAGE_MARKER', 100, 100);
      return first.data!['hasMore'] == true &&
          first.data!['nextOffset'] == 100 &&
          ids(first).length == 100 &&
          ids(second).length == 2 &&
          second.data!['hasMore'] == false;
    });
    await check('model_arguments_cannot_select_other_project', () async {
      final tool = RememberTool(
          onRemember: (_) async {}, onRememberWithRevision: a.remember);
      final r = await tool.execute({
        'content': 'SCOPE_ARGUMENT_MARKER',
        'projectId': 'B',
        'category': 'project:B'
      });
      return r.ok &&
          (await db.findMemory(r.data!['id'] as String))!.category ==
              'project:A';
    });
    await check('memory_writes_require_confirmation_in_default_modes',
        () async {
      final remember = RememberTool(onRemember: (_) async {});
      final writeTool = MemoryWriteTool(onWrite: a.write);
      for (final tool in [remember.manifest, writeTool.manifest]) {
        if (!tool.sensitive || tool.risk != ToolRisk.requiresConfirmation) {
          return false;
        }
        for (final mode in [ApprovalMode.ask, ApprovalMode.autoSafe]) {
          if (!const ApprovalPolicy()
              .decide(
                  mode: mode,
                  risk: tool.risk,
                  trusted: false,
                  sensitive: tool.sensitive)
              .requiresUser) {
            return false;
          }
        }
      }
      return true;
    });
    await check('editing_existing_resource_requires_scoped_revision', () async {
      final r = await write(a, ma.id, null, 'without revision');
      return r.code == ToolCodes.revisionConflict &&
          r.effect == ToolEffect.none;
    });
    await check('invalid_new_write_mode_or_content_does_not_create_rows',
        () async {
      final before = (await db.allMemories()).length;
      final invalid = await write(a, null, null, 'bad mode', mode: 'unknown');
      final empty = await a.remember(' ', null);
      final huge = await a.remember('x' * 3501, null);
      return !invalid.ok &&
          !empty.ok &&
          !huge.ok &&
          (await db.allMemories()).length == before;
    });
    await check('stale_delete_does_not_remove_corrected_memory', () async {
      final old = (await db.findMemory(ma.id))!;
      await service.update(db, old.copyWith(content: 'preserve corrected'),
          expectedMemory: old);
      try {
        await service.delete(db, old.id, expectedMemory: old);
        return false;
      } on MemoryConflictException {
        return (await db.findMemory(ma.id))!.content == 'preserve corrected';
      }
    });
    await check(
        'forgotten_normalized_content_cannot_be_automatically_relearned',
        () async {
      final m = await service.add(database: db, content: 'Forget   This VALUE');
      await service.delete(db, m.id, expectedMemory: m);
      final r = await global.remember(' forget this value ', null);
      return !r.ok &&
          r.effect == ToolEffect.none &&
          r.data?['reason'] == 'memory_forgotten';
    });
    await check('forgotten_source_conversation_blocks_paraphrased_auto_writes',
        () async {
      final m = await service.add(
          database: db,
          content: 'source secret',
          sourceConversationId: 'forgotten-source');
      await service.delete(db, m.id);
      final source = ScopedMemoryAccess(
          database: () async => db, sourceConversationId: 'forgotten-source');
      final r = await source.remember('Different words from old history', null);
      return !r.ok && r.data?['reason'] == 'memory_forgotten';
    });
    await check('manual_save_is_allowed_without_reopening_automatic_learning',
        () async {
      final m = await service.add(database: db, content: 'manual consent');
      await service.delete(db, m.id);
      final manual = await service.add(database: db, content: 'manual consent');
      final r = await global.remember('manual consent', null);
      return (await service.search(db, 'manual consent'))
              .any((r) => r.id == manual.id) &&
          !r.ok;
    });
    await check('manual_correction_forgets_previous_content_atomically',
        () async {
      final m = await service.add(database: db, content: 'outdated fact');
      await service.update(db, m.copyWith(content: 'correct fact'),
          expectedMemory: m);
      final r = await global.remember('outdated fact', null);
      return !r.ok && (await db.findMemory(m.id))!.content == 'correct fact';
    });
    await check('disabled_memory_cannot_be_relearned_under_a_new_id', () async {
      final m =
          await service.add(database: db, content: 'disabled privacy item');
      await service.update(db, m.copyWith(enabled: false), expectedMemory: m);
      return !(await global.remember(m.content, null)).ok;
    });
    await check('older_automatic_duplicate_is_not_exposed_after_forgetting',
        () async {
      final m = await service.add(
          database: db, content: 'automatic duplicate', sourceType: 'agent');
      await service.add(
          database: db, content: 'automatic duplicate', sourceType: 'agent');
      await service.delete(db, m.id);
      return (await service.search(db, 'automatic duplicate')).isEmpty;
    });
    await check('failed_forget_transaction_rolls_back_rule_and_record',
        () async {
      final m =
          await service.add(database: db, content: 'rollback privacy item');
      try {
        await db.transaction(() async {
          await service.delete(db, m.id);
          throw StateError('synthetic rollback');
        });
      } on StateError catch (error) {
        if (error.message != 'synthetic rollback') rethrow;
      }
      return await db.findMemory(m.id) != null &&
          !await MemoryForgetStore(db).blocks(m.content);
    });
    await check(
        'vault_carries_only_private_forget_digests_not_raw_content_or_source',
        () async {
      final isolated = AppDatabase(NativeDatabase.memory());
      try {
        final m = await service.add(
            database: isolated,
            content: 'FORGET_RAW_SECRET',
            sourceConversationId: 'FORGET_RAW_SOURCE');
        await service.delete(isolated, m.id);
        final backup = await buildVaultJson(isolated);
        final rules = backup['memoryForgetRules'] as List;
        final encoded = jsonEncode(rules);
        return rules.length == 1 &&
            !encoded.contains('FORGET_RAW_') &&
            (rules.first as Map)['fingerprint'] ==
                MemoryForgetStore.fingerprint(m.content);
      } finally {
        await isolated.close();
      }
    });
    await check('vault_round_trip_keeps_rules_and_skips_forgotten_older_memory',
        () async {
      final from = AppDatabase(NativeDatabase.memory());
      final to = AppDatabase(NativeDatabase.memory());
      try {
        final m =
            await service.add(database: from, content: 'restore forgotten');
        await service.delete(from, m.id);
        final backup = await buildVaultJson(from);
        backup.remove('manifest');
        backup['memories'] = [m.toJson()];
        final report = await restoreVault(to, backup);
        return (await to.allMemories()).isEmpty &&
            report.counts['memories'] == 0 &&
            report.warnings.isNotEmpty &&
            await MemoryForgetStore(to).blocks(m.content);
      } finally {
        await from.close();
        await to.close();
      }
    });
    await check('legacy_vault_does_not_erase_newer_local_forget_rules',
        () async {
      final isolated = AppDatabase(NativeDatabase.memory());
      try {
        final m = await service.add(
            database: isolated, content: 'legacy restored secret');
        await service.delete(isolated, m.id);
        final report = await restoreVault(isolated, {
          'version': 1,
          'memories': [m.toJson()]
        });
        return (await isolated.allMemories()).isEmpty &&
            report.counts['memories'] == 0 &&
            await MemoryForgetStore(isolated).blocks(m.content);
      } finally {
        await isolated.close();
      }
    });
    await check('malformed_forget_rule_is_rejected_before_restore_deletes_data',
        () async {
      final isolated = AppDatabase(NativeDatabase.memory());
      try {
        final m = await service.add(
            database: isolated, content: 'preserve before invalid restore');
        try {
          await restoreVault(isolated, {
            'version': 2,
            'memoryForgetRules': [
              {'fingerprint': 'bad'}
            ]
          });
          return false;
        } on FormatException {
          return await isolated.findMemory(m.id) != null;
        }
      } finally {
        await isolated.close();
      }
    });
    await check('schema_27_upgrade_and_reopen_keep_forget_barrier', () async {
      final dir = await Directory.systemTemp
          .createTemp('nexus-memory-migration-fixture-');
      final file = File('${dir.path}/privacy.sqlite');
      AppDatabase? current;
      try {
        current = AppDatabase(NativeDatabase(file));
        final m = await service.add(
            database: current, content: 'migration retained record');
        await current.customStatement('DROP TABLE memory_forget_rules');
        await current.customStatement('PRAGMA user_version = 27');
        await current.close();
        current = null;
        current = AppDatabase(NativeDatabase(file));
        if ((await current.findMemory(m.id))?.content != m.content) {
          return false;
        }
        await service.delete(current, m.id);
        await current.close();
        current = null;
        current = AppDatabase(NativeDatabase(file));
        return await MemoryForgetStore(current).blocks(m.content) &&
            await current.findMemory(m.id) == null;
      } finally {
        await current?.close();
        await dir.delete(recursive: true);
      }
    });
  } finally {
    await db.close();
  }
  return {
    'type': 'MemoryScopeContractChecks',
    'fixtureOnly': true,
    'modelCalls': 0,
    'platformMutations': 0,
    'persistentDataMutations': 0,
    'cases': cases,
    'passed': cases.where((c) => c['passed'] == true).length,
    'total': cases.length
  };
}

Route<void>? _route;
NavigatorState? _navigator;
AppDatabase? _fixtureDb;
String? _fixtureMemoryId;
Future<Map<String, dynamic>> _fixture(String? mode) async {
  if (!const ['open', 'mutate', 'inspect', 'close'].contains(mode)) {
    throw ArgumentError('Fixed fixture modes only');
  }
  if (mode == 'close') {
    if (_route != null) _navigator?.removeRoute(_route!);
  } else if (mode == 'mutate' || mode == 'inspect') {
    final db = _fixtureDb;
    final id = _fixtureMemoryId;
    if (db == null || id == null) throw StateError('No owned fixture');
    final current = await db.findMemory(id);
    if (current == null) throw StateError('Fixture source missing');
    if (mode == 'mutate') {
      await MemoryService().update(
          db, current.copyWith(content: 'EDITOR_NEWER_MARKER'),
          expectedMemory: current);
    } else if (current.content != 'EDITOR_NEWER_MARKER') {
      throw StateError('Fixture newer revision was overwritten');
    }
  } else {
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
      final memory = await MemoryService()
          .add(database: db, content: 'EDITOR_ORIGINAL_MARKER');
      final route = MaterialPageRoute<void>(
          builder: (_) => ProviderScope(
              overrides: [databaseProvider.overrideWith((ref) async => db)],
              child: Scaffold(
                  appBar: AppBar(title: const Text('隔离验收 · 记忆并发')),
                  body: const MemoryPage())));
      _route = route;
      _navigator = navigator;
      _fixtureDb = db;
      _fixtureMemoryId = memory.id;
      unawaited(navigator!.push(route).whenComplete(() async {
        if (identical(_route, route)) {
          _route = null;
          _navigator = null;
          _fixtureDb = null;
          _fixtureMemoryId = null;
        }
        await db.close();
      }));
    } catch (_) {
      await db.close();
      rethrow;
    }
  }
  return {'fixtureOnly': true, 'mode': mode};
}
