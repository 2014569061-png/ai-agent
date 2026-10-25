import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/assistant_role.dart';
import '../presentation/settings/default_assistant_page.dart';

Future<List<Map<String, dynamic>>> runAssistantRoleChecks() async {
  final cases = <Map<String, dynamic>>[];
  Future<void> check(String name, FutureOr<bool> Function() action) async {
    try {
      cases.add({'name': name, 'passed': await action()});
    } catch (error) {
      cases.add({
        'name': name,
        'passed': false,
        'error': error.runtimeType.toString()
      });
    }
  }

  await check('assistant_role_connection_requires_all_system_facts', () {
    for (var mask = 0; mask < 64; mask++) {
      bool bit(int n) => mask & (1 << n) != 0;
      final status = AssistantRoleStatus(
          supported: bit(0),
          roleAvailable: bit(1),
          roleHeld: bit(2),
          selected: bit(3),
          active: bit(4),
          ready: bit(5));
      if (status.connected != (mask == 63)) return false;
    }
    return true;
  });
  await check(
      'assistant_role_legacy_still_requires_selection_activation_readiness',
      () {
    const status = AssistantRoleStatus(
        supported: true,
        roleRequired: false,
        selected: true,
        active: true,
        ready: true);
    return status.connected &&
        !const AssistantRoleStatus(
                supported: true, roleRequired: false, selected: true)
            .connected;
  });
  await check(
      'assistant_role_opened_chooser_and_malformed_values_are_not_grants', () {
    return !AssistantRoleStatus.fromMap({'opened': true, 'connected': true})
            .connected &&
        !AssistantRoleStatus.fromMap({
          'supported': 'true',
          'roleHeld': 1,
          'selected': true,
          'active': true,
          'ready': true
        }).connected;
  });
  await check('assistant_role_selected_pending_and_revoked_states_are_distinct',
      () {
    const pending = AssistantRoleStatus(
        supported: true, roleAvailable: true, roleHeld: true, selected: true);
    const revoked = AssistantRoleStatus(
        supported: true,
        roleAvailable: true,
        selected: false,
        active: true,
        ready: true);
    return !pending.connected &&
        pending.label.contains('等待') &&
        !revoked.connected &&
        revoked.label.contains('尚未选择');
  });
  await check('assistant_role_actual_native_registration_and_privacy_status',
      () async {
    final raw = await const MethodChannel('nexus/assistant_role')
        .invokeMapMethod<String, Object?>('status');
    return raw != null &&
        raw['supported'] == true &&
        raw['roleRequired'] == true &&
        raw['roleAvailable'] is bool &&
        raw['selected'] is bool &&
        raw['active'] is bool &&
        raw['ready'] is bool &&
        raw['contextCollection'] == false &&
        raw['backgroundMicrophone'] == false &&
        raw['hotword'] == false &&
        raw['recognitionAdapter'] == 'foreground_app_only';
  });
  return cases;
}

bool _registered = false;
Route<void>? _route;

/// Opens the production settings page. Only real UI taps can request a role;
/// this extension itself performs read-only native status operations.
void registerAssistantRoleUiChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension('ext.nexus.assistantRoleFixture', (method, params) async {
    final mode = params['mode'];
    if (mode == 'open') {
      if (_route != null) throw StateError('Close owned route first');
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
      if (navigator == null) throw StateError('No navigator');
      final route = _route =
          MaterialPageRoute<void>(builder: (_) => const DefaultAssistantPage());
      unawaited(navigator!.push(route));
    } else if (mode == 'close') {
      final route = _route;
      _route = null;
      if (route != null && route.isActive) route.navigator!.removeRoute(route);
    }
    final state = await const MethodChannel('nexus/assistant_role')
        .invokeMapMethod<String, Object?>('status');
    return ServiceExtensionResponse.result(jsonEncode({
      'type': 'AssistantRoleUiStatus',
      'modelCalls': 0,
      'microphoneStarts': 0,
      'routeOpen': _route?.isActive ?? false,
      'status': state,
    }));
  });
}
