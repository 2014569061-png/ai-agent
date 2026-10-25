import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/system_connector_request.dart';

void main() {
  Map<String, dynamic> input(
          String id, String operation, Map<String, dynamic> args) =>
      {'connectorId': id, 'operation': operation, 'arguments': args};

  test('calendar normalizes explicit offsets without guessing timezone', () {
    final request =
        SystemConnectorRequest.fromJson(input('calendar', 'prepare_event', {
      'title': '模拟事件',
      'start': '2026-10-19T12:00:00+08:00',
      'end': '2026-10-19T13:00:00+08:00',
    }));
    expect(request.arguments['start'], '2026-10-19T04:00:00.000Z');
    expect(request.requiresSystemConfirmation, isTrue);
    expect(SystemConnectorRequest.fromJson(request.toJson()).toJson(),
        request.toJson());
  });

  test('invalid dates and implicit timezone are rejected', () {
    for (final date in [
      '2026-02-30T12:00:00Z',
      '2026-10-19T24:00:00Z',
      '2026-10-19T12:00:00',
      '2026-10-19T12:00:00+14:01',
      '2026-10-19T12:00:00+08:60',
      '0000-01-01T00:00:00Z',
    ]) {
      expect(
          () => SystemConnectorRequest.fromJson(
                  input('calendar', 'prepare_event', {
                'title': '模拟事件',
                'start': date,
                'end': '2027-01-01T00:00:00Z',
              })),
          throwsFormatException);
    }
  });

  test('event end must follow start', () {
    expect(
        () =>
            SystemConnectorRequest.fromJson(input('calendar', 'prepare_event', {
              'title': '模拟事件',
              'start': '2026-10-19T12:00:00Z',
              'end': '2026-10-19T12:00:00Z',
            })),
        throwsFormatException);
  });

  test('contacts are editor drafts, not proof of a saved contact', () {
    final request =
        SystemConnectorRequest.fromJson(input('contacts', 'prepare_contact', {
      'name': '模拟联系人',
      'email': 'test@example.com',
    }));
    expect(request.requiresSystemConfirmation, isTrue);
    expect(request.arguments['name'], '模拟联系人');
  });

  test('contact control characters and malformed email are rejected', () {
    for (final args in <Map<String, dynamic>>[
      {'name': 'test\nInjected'},
      {'name': 'test', 'email': 'no-address'},
    ]) {
      expect(
          () => SystemConnectorRequest.fromJson(
              input('contacts', 'prepare_contact', args)),
          throwsFormatException);
    }
  });

  test('maps accept search text, never arbitrary intents', () {
    final request = SystemConnectorRequest.fromJson(
        input('maps', 'search_place', {'query': ' 模拟地点 '}));
    expect(request.arguments['query'], '模拟地点');
    expect(
        () => SystemConnectorRequest.fromJson(input('maps', 'search_place', {
              'query': 'test',
              'uri': 'intent://arbitrary',
            })),
        throwsFormatException);
  });

  test('file types are sorted, deduplicated and immutable', () {
    final request =
        SystemConnectorRequest.fromJson(input('files', 'pick_document', {
      'mimeTypes': ['image/*', 'application/pdf', 'image/*'],
    }));
    expect(request.arguments['mimeTypes'], ['application/pdf', 'image/*']);
    expect(() => (request.arguments['mimeTypes'] as List).add('text/plain'),
        throwsUnsupportedError);
    expect(() => request.arguments['path'] = '/tmp/not-allowed',
        throwsUnsupportedError);
  });

  test('file selection defaults to one user-selected document', () {
    final request =
        SystemConnectorRequest.fromJson(input('files', 'pick_document', {}));
    expect(request.arguments['mimeTypes'], ['*/*']);
    expect(
        () => SystemConnectorRequest.fromJson(
            input('files', 'pick_document', {'path': '/sdcard'})),
        throwsFormatException);
  });

  test('bad MIME types and oversized lists are rejected', () {
    for (final types in [
      [],
      ['image/*;intent=bad'],
      ['*/pdf'],
      List.filled(9, 'image/*')
    ]) {
      expect(
          () => SystemConnectorRequest.fromJson(
              input('files', 'pick_document', {'mimeTypes': types})),
          throwsFormatException);
    }
  });

  test('media selection has a closed type enum', () {
    for (final kind in ['image', 'video']) {
      expect(
          SystemConnectorRequest.fromJson(
              input('media', 'pick_media', {'kind': kind})).arguments['kind'],
          kind);
    }
    expect(
        () => SystemConnectorRequest.fromJson(
            input('media', 'pick_media', {'kind': 'camera'})),
        throwsFormatException);
  });

  test('connector operation mismatch and unknown top-level keys fail closed',
      () {
    expect(
        () => SystemConnectorRequest.fromJson(
            input('maps', 'prepare_contact', {'query': 'test'})),
        throwsFormatException);
    expect(
        () => SystemConnectorRequest.fromJson({
              ...input('maps', 'search_place', {'query': 'test'}),
              'approved': true,
            }),
        throwsFormatException);
  });

  test('input and output mutations cannot change an existing request', () {
    final args = <String, dynamic>{'query': 'first'};
    final request =
        SystemConnectorRequest.fromJson(input('maps', 'search_place', args));
    args['query'] = 'second';
    (request.toJson()['arguments'] as Map)['query'] = 'third';
    expect(request.arguments['query'], 'first');
  });
}
