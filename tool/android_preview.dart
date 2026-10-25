// Runs Flutter's machine protocol so external edits (including Codex edits)
// trigger hot reload without an editor extension or additional dependencies.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final attach = arguments.length == 4 && arguments[2] == '--attach';
  if (arguments.length != 2 && !attach) {
    stderr.writeln(
        'Usage: dart android_preview.dart <flutter.bat> <device-id> [--attach <loopback-debug-url>]');
    exitCode = 64;
    return;
  }
  if (attach) {
    final uri = Uri.tryParse(arguments[3]);
    if (uri == null || uri.scheme != 'http' || uri.host != '127.0.0.1') {
      stderr
          .writeln('Attach requires the existing loopback debug service URL.');
      exitCode = 64;
      return;
    }
    stdout.writeln(
        '[preview] Attaching to the running app without reinstalling or clearing data.');
  }
  final process = await Process.start(
    arguments[0],
    [
      attach ? 'attach' : 'run',
      '--machine',
      if (attach) ...[
        '--debug-url',
        arguments[3]
      ] else ...[
        '--debug',
        '--no-pub'
      ],
      '-d',
      arguments[1],
    ],
    runInShell: Platform.isWindows,
  );
  String? appId;
  var started = false;
  var sequence = 0;
  var closing = false;
  final requests = <int, Completer<Map<String, dynamic>>>{};

  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, dynamic>? parameters,
  ]) {
    final id = ++sequence;
    final completion = Completer<Map<String, dynamic>>();
    requests[id] = completion;
    process.stdin.writeln(jsonEncode([
      {'id': id, 'method': method, 'params': parameters ?? <String, dynamic>{}},
    ]));
    return completion.future;
  }

  Future<void> reload({bool restart = false}) async {
    if (!started || closing) return;
    stdout.writeln(
        restart ? '[preview] Restarting...' : '[preview] Hot reload...');
    final response = await request('app.restart', {
      'appId': appId,
      'fullRestart': restart,
      'pause': false,
      'reason': 'Source files changed',
      'debounce': true,
    });
    final result = response['result'];
    if (response.containsKey('error') ||
        (result is Map && result['code'] != 0)) {
      stderr.writeln('[preview] Reload failed: ${response['error'] ?? result}');
      stderr
          .writeln('[preview] Fix compilation errors, or enter R to restart.');
    } else {
      stdout
          .writeln('[preview] ${restart ? 'Restart' : 'Hot reload'} complete.');
    }
  }

  final output = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    dynamic messages;
    try {
      messages = jsonDecode(line);
    } on FormatException {
      stdout.writeln(line);
      return;
    }
    if (messages is! List) {
      stdout.writeln(line);
      return;
    }
    for (final dynamic item in messages) {
      if (item is! Map<String, dynamic>) continue;
      if (item.containsKey('id')) {
        requests.remove(item['id'])?.complete(item);
        continue;
      }
      final params = item['params'] as Map<String, dynamic>? ?? {};
      switch (item['event']) {
        case 'app.start':
          appId = params['appId'] as String;
        case 'app.debugPort':
          final raw = params['wsUri'];
          final uri = raw is String ? Uri.tryParse(raw) : null;
          if (uri != null && uri.scheme == 'ws' && uri.host == '127.0.0.1') {
            final directory = Directory('local/android-preview');
            directory.createSync(recursive: true);
            // Debug authentication URL stays local; never print/export it.
            File('${directory.path}/vm-service.json').writeAsStringSync(
              jsonEncode({
                'wsUri': uri.toString(),
                'deviceId': arguments[1],
                'recordedAt': DateTime.now().toUtc().toIso8601String()
              }),
            );
          }
        case 'app.started':
          started = true;
          stdout.writeln(
              '[preview] Ready. Edits under lib/, assets/, shaders/ reload automatically.');
          stdout.writeln('[preview] Enter r = reload, R = restart, q = quit.');
        case 'app.log':
        case 'daemon.logMessage':
          stdout.writeln(params['log'] ?? params['message'] ?? '');
        case 'app.progress':
          if (params['message'] != null) stdout.writeln(params['message']);
        case 'app.stop':
          started = false;
          if (params['error'] != null) stderr.writeln(params['error']);
      }
    }
  });
  final errors = process.stderr.listen(stderr.add);

  // Polling also detects atomic saves and new directories reliably on Windows.
  Future<Map<String, String>> snapshot() async {
    final files = <String, String>{};
    for (final root in ['lib', 'assets', 'shaders']) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      await for (final entry
          in directory.list(recursive: true, followLinks: false)) {
        if (entry is! File) continue;
        try {
          final stat = await entry.stat();
          files[entry.path] =
              '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
        } on FileSystemException {
          // An editor may replace a file during the scan; the next scan catches it.
        }
      }
    }
    return files;
  }

  var previous = await snapshot();
  var scanning = false;
  Timer? debounce;
  final watcher = Timer.periodic(const Duration(milliseconds: 700), (_) async {
    if (scanning || closing) return;
    scanning = true;
    try {
      // A later Codex chat may no longer own the original PTY. Keep restart
      // available without spawning a second Flutter debug session.
      final control = File('local/android-preview/reload.request');
      if (started && control.existsSync()) {
        final command = control.readAsStringSync().trim();
        control.deleteSync();
        if (command == 'R' || command == 'r') {
          await reload(restart: command == 'R');
        }
      }
      final current = await snapshot();
      if (current.length != previous.length ||
          current.entries.any((entry) => previous[entry.key] != entry.value)) {
        previous = current;
        debounce?.cancel();
        debounce =
            Timer(const Duration(milliseconds: 700), () => unawaited(reload()));
      }
    } finally {
      scanning = false;
    }
  });
  final input = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    if (line.trim() == 'q' && !closing) {
      closing = true;
      unawaited(request('daemon.shutdown'));
    } else if (line.trim() == 'r' || line.trim() == 'R') {
      unawaited(reload(restart: line.trim() == 'R'));
    }
  });
  final interrupt = ProcessSignal.sigint.watch().listen((_) {
    if (!closing) {
      closing = true;
      unawaited(request('daemon.shutdown'));
    }
  });
  exitCode = await process.exitCode;
  closing = true;
  watcher.cancel();
  debounce?.cancel();
  for (final pending in requests.values) {
    pending.complete({'error': 'Flutter process exited.'});
  }
  await output.cancel();
  await errors.cancel();
  await input.cancel();
  await interrupt.cancel();
}
