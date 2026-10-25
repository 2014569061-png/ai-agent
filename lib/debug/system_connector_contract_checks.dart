// Fixed, debug-only checks. Invoked in the emulator isolate, never on host.
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import '../domain/system_connector_request.dart';

bool _registered = false;

void registerSystemConnectorContractChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension('ext.nexus.systemConnectorContract',
      (method, params) async {
    return ServiceExtensionResponse.result(jsonEncode(_runChecks()));
  });
}

Map<String, dynamic> _runChecks() {
  final results = <Map<String, dynamic>>[];
  SystemConnectorRequest request(
          String kind, String op, Map<String, dynamic> args) =>
      SystemConnectorRequest.fromJson(
          {'connectorId': kind, 'operation': op, 'arguments': args});
  bool rejects(void Function() action) {
    try {
      action();
      return false;
    } on FormatException {
      return true;
    }
  }

  bool immutable(void Function() action) {
    try {
      action();
      return false;
    } on UnsupportedError {
      return true;
    }
  }

  void check(String name, bool Function() body) {
    try {
      results.add({'name': name, 'passed': body()});
    } catch (_) {
      results.add({'name': name, 'passed': false, 'unexpectedError': true});
    }
  }

  final event = <String, dynamic>{
    'title': 'Synthetic event',
    'start': '2026-10-19T12:00:00+08:00',
    'end': '2026-10-19T13:00:00+08:00'
  };
  check('calendar_explicit_offset_and_roundtrip', () {
    final r = request('calendar', 'prepare_event', event);
    return r.arguments['start'] == '2026-10-19T04:00:00.000Z' &&
        SystemConnectorRequest.fromJson(r.toJson()).arguments['end'] ==
            r.arguments['end'];
  });
  check('invalid_dates_and_implicit_timezone', () {
    return [
      '2026-02-30T12:00:00Z',
      '2026-10-19T24:00:00Z',
      '2026-10-19T12:00:00',
      '2026-10-19T12:00:00+14:01',
      '2026-10-19T12:00:00+08:60',
      '0000-01-01T00:00:00Z',
      '0001-01-01T00:00:00+14:00'
    ].every((date) => rejects(() {
          request('calendar', 'prepare_event', {...event, 'start': date});
        }));
  });
  check(
      'event_requires_positive_duration',
      () => rejects(() {
            request(
                'calendar', 'prepare_event', {...event, 'end': event['start']});
          }));
  check('contact_is_draft_not_saved_resource', () {
    final r =
        request('contacts', 'prepare_contact', {'name': 'Synthetic contact'});
    return r.requiresSystemConfirmation &&
        r.arguments['name'] == 'Synthetic contact';
  });
  check(
      'contacts_reject_controls_and_invalid_email',
      () =>
          rejects(() {
            request('contacts', 'prepare_contact', {'name': 'test\nInjected'});
          }) &&
          rejects(() {
            request('contacts', 'prepare_contact',
                {'name': 'test', 'email': 'invalid'});
          }));
  check(
      'maps_text_only',
      () =>
          request('maps', 'search_place', {'query': ' Synthetic place '})
                  .arguments['query'] ==
              'Synthetic place' &&
          rejects(() {
            request('maps', 'search_place',
                {'query': 'test', 'uri': 'intent://not-allowed'});
          }));
  check('file_types_normalized_and_immutable', () {
    final r = request('files', 'pick_document', {
      'mimeTypes': ['image/*', 'application/pdf', 'image/*']
    });
    return r.arguments['mimeTypes'].toString() ==
            '[application/pdf, image/*]' &&
        immutable(() {
          (r.arguments['mimeTypes'] as List).add('text/plain');
        });
  });
  check(
      'file_defaults_without_path_access',
      () =>
          request('files', 'pick_document', {})
                  .arguments['mimeTypes']
                  .toString() ==
              '[*/*]' &&
          rejects(() {
            request('files', 'pick_document', {'path': '/sdcard'});
          }));
  check(
      'bad_mime_and_limit',
      () => [
            [],
            ['image/*;intent=bad'],
            ['*/pdf'],
            List.filled(9, 'image/*')
          ].every((types) => rejects(() {
                request('files', 'pick_document', {'mimeTypes': types});
              })));
  check(
      'media_closed_enum',
      () =>
          ['image', 'video'].every((kind) =>
              request('media', 'pick_media', {'kind': kind})
                  .arguments['kind'] ==
              kind) &&
          rejects(() {
            request('media', 'pick_media', {'kind': 'camera'});
          }));
  check(
      'operation_and_forged_approval_rejected',
      () =>
          rejects(() {
            request('maps', 'prepare_contact', {'query': 'test'});
          }) &&
          rejects(() {
            SystemConnectorRequest.fromJson({
              'connectorId': 'maps',
              'operation': 'search_place',
              'arguments': {'query': 'test'},
              'approved': true
            });
          }));
  check('input_and_output_mutation_isolated', () {
    final args = <String, dynamic>{'query': 'first'};
    final r = request('maps', 'search_place', args);
    args['query'] = 'second';
    (r.toJson()['arguments'] as Map)['query'] = 'third';
    return r.arguments['query'] == 'first' &&
        immutable(() {
          r.arguments['query'] = 'fourth';
        });
  });
  return {
    'type': 'SystemConnectorContractChecks',
    'fixtureOnly': true,
    'modelCalls': 0,
    'platformMutations': 0,
    'cases': results,
    'passed': results.where((row) => row['passed'] == true).length,
    'total': results.length
  };
}
