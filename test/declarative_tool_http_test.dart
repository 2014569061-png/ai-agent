import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/network_access_policy.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/plugins/plugin_store.dart';

void main() {
  for (final method in ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE']) {
    test('declarative HTTP preserves $method and its effect classification',
        () async {
      final adapter = _RecordingAdapter();
      final tool = DeclarativeTool.fromManifest(
        {
          'name': 'http_fixture',
          'request': {
            'url': 'https://public.invalid/resource',
            'method': method
          },
        },
        policy: NetworkAccessPolicy(
            lookupHost: (_) async => [InternetAddress('8.8.8.8')]),
        clientFactory: () => Dio()..httpClientAdapter = adapter,
      );
      final result = await tool.execute({'item': 'fixture'});
      expect(result.ok, isTrue, reason: result.message);
      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.method, method);
      final readOnly = method == 'GET' || method == 'HEAD';
      expect(result.effect, readOnly ? ToolEffect.none : ToolEffect.applied);
      expect(readOnly ? request.queryParameters : request.data,
          {'item': 'fixture'});
      expect(request.followRedirects, isFalse);
      expect(adapter.closed, isTrue);
    });
  }

  test('unsupported methods fail before DNS or sending a request', () async {
    var lookups = 0;
    final adapter = _RecordingAdapter();
    final tool = DeclarativeTool.fromManifest(
      {
        'request': {'url': 'https://public.invalid/', 'method': 'TRACE'},
      },
      policy: NetworkAccessPolicy(lookupHost: (_) async {
        lookups++;
        return [InternetAddress('8.8.8.8')];
      }),
      clientFactory: () => Dio()..httpClientAdapter = adapter,
    );
    final result = await tool.execute({});
    expect(result.code, ToolCodes.invalidArguments);
    expect(result.effect, ToolEffect.none);
    expect(lookups, 0);
    expect(adapter.requests, isEmpty);
  });

  test('a hostname resolving to any private address never sends a request',
      () async {
    final adapter = _RecordingAdapter();
    final tool = DeclarativeTool.fromManifest(
      {
        'request': {'url': 'https://public.invalid/', 'method': 'DELETE'},
      },
      policy: NetworkAccessPolicy(
          lookupHost: (_) async => [
                InternetAddress('8.8.8.8'),
                InternetAddress('127.0.0.1'),
              ]),
      clientFactory: () => Dio()..httpClientAdapter = adapter,
    );
    final result = await tool.execute({});
    expect(result.ok, isFalse);
    expect(result.effect, ToolEffect.none);
    expect(adapter.requests, isEmpty);
  });

  for (final host in [
    '0.1.2.3',
    '192.0.0.8',
    '198.18.0.1',
    '198.19.255.1',
    '224.0.0.1',
    '255.255.255.255',
    '[::]',
    '[ff02::1]',
    'foo.metadata.google.internal',
    'metadata.google.internal.'
  ]) {
    test('network policy blocks special-use destination $host', () {
      expect(const NetworkAccessPolicy().inspect('http://$host/').allowed,
          isFalse);
    });
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool closed = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString('{"ok":true}', 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}
