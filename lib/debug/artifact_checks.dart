import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../application/artifact_service.dart';
import '../application/development_verification.dart';
import '../application/providers.dart';
import '../infrastructure/database/app_database.dart';
import '../presentation/artifacts/artifact_center_page.dart';
import 'artifact_action_checks.dart';
import 'result_action_approval_checks.dart';
import 'conversation_result_checks.dart';

bool _registered = false;
bool _actionsRegistered = false;
bool _actionUiRegistered = false;
void registerArtifactChecks() {
  registerConversationResultChecks();
  registerResultActionApprovalChecks();
  if (kDebugMode && !_actionUiRegistered) {
    _actionUiRegistered = true;
    registerExtension('ext.nexus.artifactActionFixture',
        (method, params) async {
      if (params['mode'] == 'actions') {
        await _open(actions: true);
      } else if (params['mode'] == 'close') {
        if (_route != null) _navigator?.removeRoute(_route!);
      } else {
        return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams, 'Fixed action modes only');
      }
      return ServiceExtensionResponse.result(jsonEncode({
        'fixtureOnly': true,
        'mode': params['mode'],
        'modelCalls': 0,
      }));
    });
  }
  if (kDebugMode && !_actionsRegistered) {
    _actionsRegistered = true;
    registerExtension(
        'ext.nexus.artifactActionsContract',
        (method, params) async => ServiceExtensionResponse.result(
            jsonEncode(await runArtifactActionChecks())));
  }
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.artifactContract',
      (method, params) async =>
          ServiceExtensionResponse.result(jsonEncode(await _checks())));
  registerExtension('ext.nexus.artifactFixture', (method, params) async {
    if (params['mode'] == 'open' || params['mode'] == 'actions') {
      await _open(actions: params['mode'] == 'actions');
    } else if (params['mode'] == 'close') {
      if (_route != null) _navigator?.removeRoute(_route!);
    } else {
      return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 'Fixed modes only');
    }
    return ServiceExtensionResponse.result(
        jsonEncode({'fixtureOnly': true, 'mode': params['mode']}));
  });
}

Future<ProjectArtifact> _record(
        ArtifactService service, AppDatabase db, Directory workspace,
        {String file = 'sample.txt', String? hash, int? bytes}) =>
    service.record(
        db: db,
        taskId: 'isolated-task',
        runId: 'isolated-run',
        workspacePath: workspace.path,
        inspection: ArtifactInspection(
            relativePath: file, exists: true, sha256: hash, bytes: bytes));
Future<Map<String, dynamic>> _checks() async {
  final base =
      await Directory.systemTemp.createTemp('nexus-artifact-contract-');
  final workspace = await Directory(p.join(base.path, 'workspace')).create();
  final payloadRoot = Directory(p.join(base.path, 'payloads'));
  final db = AppDatabase(NativeDatabase.memory());
  final service = ArtifactService(rootDirectory: () async => payloadRoot);
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<bool> Function() body) async {
    try {
      cases.add({'name': name, 'passed': await body()});
    } catch (_) {
      cases.add({'name': name, 'passed': false, 'unexpectedError': true});
    }
  }

  Future<bool> rejects(Future<dynamic> Function() action) async {
    try {
      await action();
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<int> directories() async =>
      await payloadRoot.exists() ? await payloadRoot.list().length : 0;
  try {
    final source = await File(p.join(workspace.path, 'sample.txt'))
        .writeAsString('ARTIFACT_SOURCE_MARKER v1');
    final first = await _record(service, db, workspace,
        hash:
            ArtifactService.hashBytes(utf8.encode('ARTIFACT_SOURCE_MARKER v1')),
        bytes: 25);
    await check(
        'record_publishes_real_hashed_copy_only',
        () async =>
            first.hash.length == 64 &&
            (await service.verifiedPayload(first)).readAsStringSync() ==
                'ARTIFACT_SOURCE_MARKER v1');
    await check(
        'non_project_results_reuse_existing_artifact_schema',
        () async =>
            first.projectId.isEmpty &&
            (await service.list(db)).single.id == first.id);
    await source.writeAsString('ARTIFACT_SOURCE_MARKER v2');
    await check(
        'workspace_edits_do_not_rewrite_saved_version',
        () async => (await service.verifiedPayload(first))
            .readAsStringSync()
            .endsWith('v1'));
    await check('new_version_has_independent_id_and_payload', () async {
      final second = await _record(service, db, workspace);
      return second.id != first.id &&
          second.hash != first.hash &&
          (await service.verifiedPayload(second))
              .readAsStringSync()
              .endsWith('v2');
    });
    await check('missing_source_does_not_publish_false_record', () async {
      final before = (await service.list(db)).length;
      return await rejects(
              () => _record(service, db, workspace, file: 'absent.txt')) &&
          (await service.list(db)).length == before;
    });
    await check('inspection_mismatch_rejects_and_cleans_own_copy', () async {
      final before = await directories();
      final rows = (await service.list(db)).length;
      return await rejects(
              () => _record(service, db, workspace, hash: '0' * 64)) &&
          await directories() == before &&
          (await service.list(db)).length == rows;
    });
    await check('portable_path_traversal_rejected', () async {
      for (final path in [
        '../outside.txt',
        '/outside.txt',
        r'..\outside.txt',
        'C:/outside.txt'
      ]) {
        if (!await rejects(() => _record(service, db, workspace, file: path))) {
          return false;
        }
      }
      return true;
    });
    await check('symlink_escape_rejected', () async {
      final outside = await File(p.join(base.path, 'outside.txt'))
          .writeAsString('outside fixture');
      await Link(p.join(workspace.path, 'link.txt')).create(outside.path);
      return rejects(() => _record(service, db, workspace, file: 'link.txt'));
    });
    await check('changed_private_payload_disables_delivery', () async {
      final artifact = await _record(service, db, workspace);
      await (await service.verifiedPayload(artifact)).writeAsString('TAMPERED');
      return (await service.inspectPayload(artifact)).state ==
              ArtifactPayloadState.changed &&
          await rejects(() => service.verifiedPayload(artifact));
    });
    await check('missing_payload_keeps_provenance_but_not_success', () async {
      final artifact = await _record(service, db, workspace);
      await (await service.verifiedPayload(artifact)).delete();
      return (await service.inspectPayload(artifact)).state ==
              ArtifactPayloadState.missing &&
          (await service.list(db)).any((a) => a.id == artifact.id);
    });
    await check('invalid_record_identifier_cannot_resolve_payload', () async {
      final invalid =
          ProjectArtifact.fromJson({...first.toJson(), 'id': '../escape'});
      final legacy = ProjectArtifact.fromJson({...first.toJson(), 'hash': ''});
      return (await service.inspectPayload(invalid)).state ==
              ArtifactPayloadState.invalid &&
          (await service.inspectPayload(legacy)).state ==
              ArtifactPayloadState.unverified;
    });
    await check('database_publish_failure_cleans_new_directory_only', () async {
      final before = await directories();
      await db.customStatement('DROP TABLE artifacts');
      return await rejects(() => _record(service, db, workspace)) &&
          await directories() == before &&
          await source.exists();
    });
  } finally {
    await db.close();
    await base.delete(recursive: true);
  }
  return {
    'type': 'ArtifactContractChecks',
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
Future<void> _open({bool actions = false}) async {
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
  final base = await Directory.systemTemp.createTemp('nexus-artifact-ui-');
  final db = AppDatabase(NativeDatabase.memory());
  try {
    final workspace = await Directory(p.join(base.path, 'workspace')).create();
    final service = ArtifactService(
        rootDirectory: () async => Directory(p.join(base.path, 'payloads')));
    await File(p.join(workspace.path, 'sample.txt'))
        .writeAsString('ARTIFACT_SOURCE_MARKER v1');
    final good = await _record(service, db, workspace);
    await File(p.join(workspace.path, 'missing.txt'))
        .writeAsString('MISSING_SOURCE_MARKER');
    final missing = await _record(service, db, workspace, file: 'missing.txt');
    await (await service.verifiedPayload(missing)).delete();
    final route = MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
            overrides: [databaseProvider.overrideWith((ref) async => db)],
            child: Scaffold(
                appBar: AppBar(title: const Text('隔离验收 · 成果')),
                body:
                    ArtifactCenterPage(service: service, readOnly: !actions))));
    _route = route;
    _navigator = navigator;
    unawaited(navigator!.push(route).whenComplete(() async {
      if (identical(_route, route)) {
        _route = null;
        _navigator = null;
      }
      await db.close();
      await base.delete(recursive: true);
    }));
    assert(good.hash.isNotEmpty);
  } catch (_) {
    await db.close();
    await base.delete(recursive: true);
    rethrow;
  }
}
