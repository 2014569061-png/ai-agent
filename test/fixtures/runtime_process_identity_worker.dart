import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mobile_agent/infrastructure/database/runtime_process_probe.dart';

/// Owned, data-free child used to prove OS-level death, not heartbeat expiry.
Future<void> main() async {
  final identity = runtimeProcessProbe.current;
  if (identity == null) {
    stderr.writeln('process identity unavailable');
    exit(2);
  }
  stdin.listen((_) => exit(0), onDone: () => exit(0));
  stdout.writeln(jsonEncode(identity.toJson()));
  await stdout.flush();
  Timer.periodic(const Duration(minutes: 1), (_) {});
}
