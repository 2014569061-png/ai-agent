import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_agent/application/remote_execution_probe.dart';
import 'package:mobile_agent/infrastructure/remote/remote_executor_client.dart';
import 'package:mobile_agent/presentation/projects/remote_execution_page.dart';

void main() {
  const token = 'test-only-credential-0000000000000000000000000';
  Map<String, Object> handshake() => {
        'protocolVersion': 'nexus-remote/1',
        'arch': 'AMD64',
        'toolchain': ['python'],
        'freeBytes': 4096,
        'maxConcurrency': 1
      };
  test('no configured client means no synthetic successful handshake',
      () async {
    await expectLater(
        const RemoteExecutionProbe().handshake(), throwsStateError);
  });
  test('probe rejects unsupported and incomplete capability responses',
      () async {
    for (final value in <Map<String, dynamic>>[
      {},
      {...handshake(), 'protocolVersion': 'nexus-remote/0'},
      {...handshake(), 'arch': 'unknown'},
      {...handshake(), 'freeBytes': -1},
      {...handshake(), 'maxConcurrency': 0},
      {
        ...handshake(),
        'toolchain': [1]
      }
    ]) {
      await expectLater(
          RemoteExecutionProbe(handshakeClient: () async => value).handshake(),
          throwsFormatException);
    }
  });
  test('transport sends bearer auth and does not follow redirects', () async {
    final client = RemoteExecutorClient(
        endpoint: Uri.parse('http://10.0.2.2:8767'),
        token: token,
        client: MockClient((request) async {
          expect(request.url.path, '/handshake');
          expect(request.headers['Authorization'], 'Bearer $token');
          expect(request.followRedirects, isFalse);
          return http.Response(jsonEncode(handshake()), 200);
        }));
    final result = await RemoteExecutionProbe(handshakeClient: client.handshake)
        .handshake();
    expect(result.arch, 'AMD64');
    expect(result.freeBytes, 4096);
  });
  test('auth failures do not echo sensitive response bodies', () async {
    final client = RemoteExecutorClient(
        endpoint: Uri.parse('http://127.0.0.1:8767'),
        token: token,
        client: MockClient(
            (request) async => http.Response('sensitive-response-body', 401)));
    await expectLater(
        client.handshake(),
        throwsA(predicate((error) =>
            error.toString().contains('认证失败') &&
            !error.toString().contains('sensitive-response-body'))));
  });
  test('redirects, invalid objects and oversized responses are rejected',
      () async {
    for (final response in [
      http.Response('', 302),
      http.Response('[]', 200),
      http.Response('a' * (1024 * 1024 + 1), 200)
    ]) {
      final client = RemoteExecutorClient(
          endpoint: Uri.parse('http://127.0.0.1:8767'),
          token: token,
          client: MockClient((_) async => response));
      await expectLater(client.handshake(), throwsA(anything));
    }
  });
  test('unsafe endpoints and invalid job identifiers cannot make requests',
      () async {
    for (final url in [
      'http://example.com',
      'https://user:password@example.com',
      'https://example.com?key=value',
      'https://example.com/other',
      'file:///tmp/a'
    ]) {
      expect(() => RemoteExecutorClient(endpoint: Uri.parse(url), token: token),
          throwsFormatException);
    }
    final client = RemoteExecutorClient(
        endpoint: Uri.parse('http://127.0.0.1:8767'),
        token: token,
        client: MockClient((_) async => throw StateError('must not request')));
    expect(() => client.job('../handshake'), throwsFormatException);
  });
  test(
      'submission preserves request and run identifiers and accepts no command field',
      () async {
    final client = RemoteExecutorClient(
        endpoint: Uri.parse('http://127.0.0.1:8767'),
        token: token,
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body),
              {'requestId': 'req-1', 'runId': 'run-1', 'task': 'diagnostic'});
          return http.Response(
              '{"jobId":"00000000000000000000000000000001"}', 201);
        }));
    await client.submit(requestId: 'req-1', runId: 'run-1', task: 'diagnostic');
  });
  testWidgets(
      'remote page starts unconnected and keeps connect disabled without consent',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RemoteExecutionPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('真实连接已通过'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('remote-connect')))
            .onPressed,
        isNull);
    expect(find.textContaining('固定握手'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
