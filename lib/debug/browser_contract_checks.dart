import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../application/browser_agent_tool.dart';
import '../application/browser_session_service.dart';
import '../domain/browser_session.dart';
import '../domain/tool_result.dart';
import '../infrastructure/browser/android_browser_transport.dart';

bool _registered = false, _running = false;
void registerBrowserContractChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension('ext.nexus.browserContract', (method, params) async {
    if (_running || params.keys.any((key) => key != 'isolateId')) {
      return ServiceExtensionResponse.error(
          -32000, 'Fixed fixture is busy or arguments denied');
    }
    _running = true;
    try {
      return ServiceExtensionResponse.result(
          jsonEncode(await runNativeBrowserChecks()));
    } finally {
      _running = false;
    }
  });
}

/// No URLs, JavaScript or user input accepted from the debug client. Native
/// debugFixture is debug-only and permits only the packaged .invalid origin.
class _FixtureTransport implements BrowserTransport {
  final base = AndroidBrowserTransport();
  @override
  Stream<Map<String, dynamic>> get events => base.events;
  @override
  Future<Map<String, dynamic>> invoke(
          String method, Map<String, dynamic> args) =>
      base.invoke(method == 'open' ? 'debugFixture' : method, args);
}

Future<Map<String, dynamic>> runNativeBrowserChecks() async {
  final service = BrowserSessionService(_FixtureTransport());
  final cases = <Map<String, dynamic>>[];
  void record(String name, bool passed) =>
      cases.add({'name': name, 'passed': passed});
  Future<ToolResult> approved(
      BrowserAgentTool tool, Map<String, dynamic> args) async {
    if (tool.approvalDetailsFor(args) == null) {
      throw const BrowserFailure('PREVIEW_MISSING');
    }
    return tool.execute(tool.authorizeAfterApproval(args));
  }

  Future<Map<String, dynamic>> observe(BrowserAgentTool tool) async {
    for (var i = 0; i < 60; i++) {
      final result = await tool.execute({'action': 'observe'});
      if (result.ok) return result.data!;
      if (!['RESULT_PENDING', 'REVISION_CONFLICT'].contains(result.code)) {
        throw BrowserFailure(result.code);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const BrowserFailure('FIXTURE_TIMEOUT');
  }

  Map<String, dynamic> target(
      Map<String, dynamic> snapshot, String label, String action,
      {String? text}) {
    final node = (snapshot['nodes'] as List)
        .cast<Map>()
        .firstWhere((n) => n['label'] == label);
    return {
      'action': action,
      'snapshotId': snapshot['snapshotId'],
      'nodeId': node['id'],
      if (text != null) 'text': text
    };
  }

  try {
    await service.open('browser-fixture');
    final oldId = service.sessionId;
    final tool = BrowserAgentTool(service, 'browser-fixture');
    record(
        'isolated_profile_attached',
        service.state['isolatedProfile'] == true &&
            service.state['attached'] == true);
    record(
        'initial_control_is_manual',
        !service.agentControlled &&
            !(await tool.execute({'action': 'observe'})).ok);
    await service.control('agent');
    final navigated = await approved(tool, {
      'action': 'navigate',
      'url': 'https://nexus-browser-fixture.invalid/'
    });
    record('approved_navigation_dispatched',
        navigated.ok && navigated.effect == ToolEffect.applied);
    var snapshot = await observe(tool);
    record(
        'real_dom_text_and_nodes',
        '${snapshot['text']}'.contains('Browser fixture') &&
            (snapshot['nodes'] as List).isNotEmpty);
    final shadowNodes = (snapshot['nodes'] as List).cast<Map>();
    final shadowObserved =
        '${snapshot['text']}'.contains('Shadow fixture content') &&
            shadowNodes.any((node) => node['label'] == 'Shadow query') &&
            shadowNodes.any((node) => node['label'] == 'Apply shadow');
    cases.add({
      'name': 'open_shadow_root_content_and_controls',
      'passed': shadowObserved,
      if (!shadowObserved) ...{
        'scope': snapshot['scope'],
        'text': snapshot['text'],
        'labels': shadowNodes.map((node) => node['label']).toList(),
        'truncated': snapshot['truncated'],
      }
    });
    record(
        'private_fields_omitted',
        !jsonEncode(snapshot).contains('PRIVATE_PASSWORD_SENTINEL') &&
            !(snapshot['nodes'] as List)
                .cast<Map>()
                .any((n) => ['password', 'file'].contains(n['type'])));
    record('fresh_profile_storage',
        '${snapshot['text']}'.contains('Fresh isolated profile'));
    final fill =
        target(snapshot, 'Fixture query', 'type', text: 'fixture-value');
    record(
        'direct_write_without_ticket_denied', !(await tool.execute(fill)).ok);
    final filled = await approved(tool, fill);
    record('approved_type_dispatched',
        filled.ok && filled.effect == ToolEffect.applied);
    record('old_target_reuse_denied', tool.approvalDetailsFor(fill) == null);
    snapshot = await observe(tool);
    final clicked =
        await approved(tool, target(snapshot, 'Apply fixture', 'click'));
    record('approved_click_dispatched', clicked.ok);
    snapshot = await observe(tool);
    record('readback_confirms_type_and_click',
        '${snapshot['text']}'.contains('Applied fixture-value'));
    final shadowFill =
        target(snapshot, 'Shadow query', 'type', text: 'shadow-value');
    final shadowTyped = await approved(tool, shadowFill);
    snapshot = await observe(tool);
    final shadowApply =
        await approved(tool, target(snapshot, 'Apply shadow', 'click'));
    snapshot = await observe(tool);
    record(
        'approved_shadow_dom_actions_readback',
        shadowTyped.ok &&
            shadowApply.ok &&
            '${snapshot['text']}'.contains('Shadow applied shadow-value'));
    final stale = target(snapshot, 'Apply fixture', 'click');
    await approved(tool, target(snapshot, 'Replace target', 'click'));
    // Exercise the native DOM freshness check itself, independently of the
    // application cache: current native epoch, but an old observed node.
    try {
      await service.command(
          'browser-fixture', 'act', {...stale, 'epoch': service.epoch});
      record('native_replaced_node_rejected', false);
    } on BrowserFailure catch (error) {
      record('native_replaced_node_rejected',
          error.code == 'REVISION_CONFLICT' && !error.dispatched);
    }
    snapshot = await observe(tool);
    final staleShadow = target(snapshot, 'Apply shadow', 'click');
    await approved(tool, target(snapshot, 'Replace shadow target', 'click'));
    try {
      await service.command(
          'browser-fixture', 'act', {...staleShadow, 'epoch': service.epoch});
      record('native_shadow_mutation_invalidates_target', false);
    } on BrowserFailure catch (error) {
      record('native_shadow_mutation_invalidates_target',
          error.code == 'REVISION_CONFLICT' && !error.dispatched);
    }
    snapshot = await observe(tool);
    final link = target(snapshot, 'Next fixture', 'click');
    final linked = await approved(tool, link);
    record('link_outcome_honest',
        linked.ok || linked.effect == ToolEffect.unknown);
    snapshot = await observe(tool);
    record('navigation_readback', '${snapshot['url']}'.endsWith('/next'));
    await service.control('user');
    record('takeover_denies_observation',
        !(await tool.execute({'action': 'observe'})).ok);
    record(
        'takeover_denies_write_preview',
        tool.approvalDetailsFor({
              'action': 'navigate',
              'url': 'https://nexus-browser-fixture.invalid/'
            }) ==
            null);
    await service.close();
    record(
        'closed_owner_denied', !(await tool.execute({'action': 'status'})).ok);
    await service.open('browser-fixture');
    record('new_session_identity', service.sessionId != oldId);
    await service.control('agent');
    final next = BrowserAgentTool(service, 'browser-fixture');
    await approved(next, {
      'action': 'navigate',
      'url': 'https://nexus-browser-fixture.invalid/'
    });
    snapshot = await observe(next);
    record(
        'new_profile_does_not_inherit_storage',
        '${snapshot['text']}'.contains('Fresh isolated profile') &&
            !'${snapshot['text']}'.contains('Previous profile marker'));
    try {
      await service.transport.invoke('observe', {'sessionId': oldId});
      record('old_native_session_denied', false);
    } on BrowserFailure catch (error) {
      record('old_native_session_denied', error.code == 'SESSION_EXPIRED');
    }
  } catch (error) {
    cases.add({
      'name': 'fixture_completion',
      'passed': false,
      'errorType': error.runtimeType.toString(),
      if (error is BrowserFailure) 'code': error.code
    });
  } finally {
    try {
      await service.close();
    } catch (error) {
      cases.add({
        'name': 'fixture_cleanup',
        'passed': false,
        'errorType': error.runtimeType.toString()
      });
    }
    service.dispose();
  }
  return {
    'type': 'BrowserNativeContract',
    'fixtureOnly': true,
    'modelCalls': 0,
    'networkRequests': 0,
    'platformMutations': 'temporary WebView profiles and packaged DOM only',
    'cases': cases,
    'total': cases.length,
    'passed': cases.where((c) => c['passed'] == true).length
  };
}
