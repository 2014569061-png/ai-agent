// Runs the handoff gates against the existing preview. No model requests or
// production data writes: every extension owns an isolated fixture database.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

Future<Map<String, String>> sourceHashes() async {
  final files = <File>[];
  await for (final item
      in Directory('lib').list(recursive: true, followLinks: false)) {
    if (item is File && item.path.endsWith('.dart')) files.add(item);
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final file in files)
      file.path.replaceAll('\\', '/'):
          sha256.convert(await file.readAsBytes()).toString()
  };
}

Future<void> main(List<String> args) async {
  final initialSources = await sourceHashes();
  final state = jsonDecode(
          await File('local/android-preview/vm-service.json').readAsString())
      as Map<String, dynamic>;
  final uri = Uri.parse(state['wsUri'] as String);
  if (uri.scheme != 'ws' ||
      uri.host != '127.0.0.1' ||
      !(state['deviceId'] as String).startsWith('emulator-')) {
    throw StateError('An existing local emulator preview is required');
  }
  final ws = await WebSocket.connect(uri.toString());
  var sequence = 0;
  final pending = <String, Completer<Map<String, dynamic>>>{};
  final subscription = ws.listen((raw) {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    final completer = pending.remove(message['id']?.toString());
    if (completer == null) return;
    if (message['error'] != null) {
      // Do not print the connection URL or arbitrary service error payloads.
      completer.completeError(
          StateError('VM RPC failed: ${message['error']['code']}'));
    } else {
      completer.complete(Map<String, dynamic>.from(message['result'] as Map));
    }
  });
  Future<Map<String, dynamic>> rpc(String method,
      [Map<String, dynamic> params = const {}]) async {
    final id = '${++sequence}';
    final completer = Completer<Map<String, dynamic>>();
    pending[id] = completer;
    ws.add(jsonEncode(
        {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    try {
      return await completer.future.timeout(method.endsWith('Contract')
          ? const Duration(minutes: 5)
          : const Duration(seconds: 60));
    } finally {
      pending.remove(id);
    }
  }

  final report = <String, dynamic>{
    'verifiedAt': DateTime.now().toUtc().toIso8601String(),
    'executionTarget': state['deviceId'],
    'fixtureOnly': true,
    'modelCalls': 0,
    'realUserDataMutations': 0,
    'notFinalReleaseSignOff': true,
    'contracts': <String, dynamic>{},
    'ui': <Map<String, dynamic>>[],
    'passed': false,
    'sourceSha256': initialSources,
  };
  var opened = false;
  var allPassed = true;
  try {
    final vm = await rpc('getVM');
    final isolates = (vm['isolates'] as List).cast<Map<String, dynamic>>();
    final isolate = isolates.firstWhere((i) => i['name'] == 'main');
    final base = <String, dynamic>{'isolateId': isolate['id']};
    for (final suite in args.contains('--ui-only')
        ? <String>[]
        : [
            'artifactActionsContract',
            'personalContextSqlContract',
            'planProtocolContract',
            'memoryScopeContract',
            'memoryKnowledgeContract',
            'conversationResultsContract',
          ]) {
      final result = await rpc('ext.nexus.$suite', base);
      final cases = result['cases'] as List? ?? const [];
      final total = result['total'] ?? cases.length;
      final passed =
          result['passed'] ?? cases.where((c) => c['passed'] == true).length;
      const minimumCases = {
        'artifactActionsContract': 36,
        'personalContextSqlContract': 69,
        'planProtocolContract': 228,
        'memoryScopeContract': 28,
        'memoryKnowledgeContract': 12,
        'conversationResultsContract': 40
      };
      final ok = total is int &&
          total >= minimumCases[suite]! &&
          cases.length == total &&
          passed == total &&
          cases.every((c) => c['passed'] == true);
      (report['contracts'] as Map)[suite] = result;
      allPassed = allPassed && ok;
      stdout.writeln('$suite: $passed/$total ${ok ? "PASS" : "FAIL"}');
      if (!ok) {
        stdout.writeln(cases.where((c) => c['passed'] != true).toList());
      }
    }
    final meta =
        await rpc('ext.nexus.pageCoverageUi', {...base, 'mode': 'list'});
    final selectedPages =
        args.where((a) => a.startsWith('--pages=')).firstOrNull;
    final pages = selectedPages != null
        ? selectedPages.substring(8).split(',')
        : args.contains('--all-pages')
            ? (meta['pages'] as List).cast<String>()
            : [
                'mobile_workflows',
                'scheduled_tasks',
                'artifact_center',
                'provider_template_import',
                'remote_execution',
                'dashboard',
                'personal_context',
                'knowledge',
                'extensions',
                'research_artifacts'
              ];
    await rpc('ext.nexus.pageCoverageUi', {...base, 'mode': 'open'});
    opened = true;
    final modes = [
      {'width': '360', 'height': '0', 'scale': '1.6', 'dark': 'false'},
      {'width': '360', 'height': '0', 'scale': '2.0', 'dark': 'false'},
      {'width': '360', 'height': '0', 'scale': '1.6', 'dark': 'true'},
      {'width': '640', 'height': '360', 'scale': '1.6', 'dark': 'true'},
    ];
    for (final mode in modes) {
      for (final page in pages) {
        final result = await rpc('ext.nexus.pageCoverageUi',
            {...base, 'mode': 'show', 'page': page, 'waitMs': '500', ...mode});
        final ok = result['uiErrors'] == 0 &&
            (result['errors'] as List?)?.isEmpty == true &&
            result['width'] == double.parse(mode['width']!) &&
            result['height'] == double.parse(mode['height']!) &&
            result['scale'] == double.parse(mode['scale']!) &&
            result['dark'] == (mode['dark'] == 'true');
        (report['ui'] as List).add({...result, 'passed': ok});
        if (args.contains('--screenshots') &&
            const {
              'scheduled_tasks',
              'mobile_workflows',
              'dashboard',
              'artifact_center',
              'extensions',
              'terminal',
            }.contains(page)) {
          final capture = await Process.run(
              'local/android-sdk/platform-tools/adb.exe',
              [
                '-s',
                state['deviceId'] as String,
                'exec-out',
                'screencap',
                '-p'
              ],
              stdoutEncoding: null);
          if (capture.exitCode != 0) {
            throw StateError('Emulator capture failed');
          }
          await File(
                  'local/temp/mobile-handoff-$page-${mode['width']}w-${mode['scale']}x-${mode['dark']}-20261020.png')
              .writeAsBytes(capture.stdout as List<int>);
        }
        allPassed = allPassed && ok;
        if (!ok) stdout.writeln('UI FAIL $page: ${result['errors']}');
      }
      stdout.writeln(
          'UI ${mode['width']}x${mode['height']} scale=${mode['scale']} dark=${mode['dark']}: ${pages.length} checked');
    }
    // The global sheet wrapper is shared by every affected mobile page.
    final selectedSheets =
        args.where((a) => a.startsWith('--sheets=')).firstOrNull;
    for (final mode in modes) {
      for (final sheet in selectedSheets != null
          ? selectedSheets.substring(9).split(',')
          : (meta['sheets'] as List).cast<String>()) {
        stdout.writeln(
            'Checking sheet $sheet ${mode['width']}w scale=${mode['scale']}');
        final result = await rpc('ext.nexus.pageCoverageUi', {
          ...base,
          'mode': 'sheet',
          'sheet': sheet,
          'waitMs': '500',
          ...mode
        });
        final ok = result['uiErrors'] == 0 &&
            (result['errors'] as List?)?.isEmpty == true;
        (report['ui'] as List).add({...result, 'passed': ok});
        allPassed = allPassed && ok;
        if (!ok) stdout.writeln('Sheet FAIL $sheet: ${result['errors']}');
      }
    }
    report['passed'] = allPassed;
  } catch (error) {
    report['errorType'] = error.runtimeType.toString();
    allPassed = false;
    stderr.writeln('Verification interrupted: ${error.runtimeType}');
  } finally {
    if (opened) {
      try {
        final vm = await rpc('getVM');
        final isolate =
            (vm['isolates'] as List).firstWhere((i) => i['name'] == 'main');
        await rpc('ext.nexus.pageCoverageUi',
            {'isolateId': isolate['id'], 'mode': 'close'});
      } catch (_) {
        report['fixtureCleanupFailed'] = true;
        report['passed'] = false;
        allPassed = false;
      }
    }
    report['sourcesUnchanged'] =
        jsonEncode(await sourceHashes()) == jsonEncode(initialSources);
    if (report['sourcesUnchanged'] != true) {
      report['passed'] = false;
      allPassed = false;
    }
    final out = File(args.contains('--ui-only')
        ? 'local/temp/mobile-handoff-ui-verification-20261020.json'
        : 'local/temp/mobile-handoff-verification-20261020.json');
    await out.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n');
    stdout.writeln('Report: ${out.path}');
    await subscription.cancel();
    await ws.close();
  }
  exitCode = allPassed ? 0 : 1;
}
