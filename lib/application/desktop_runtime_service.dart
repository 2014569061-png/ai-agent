import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../infrastructure/terminal/linux_runtime.dart';
import '../infrastructure/terminal/linux_runtime_factory.dart';

final desktopRuntimeProvider = FutureProvider.autoDispose<LinuxRuntimeInfo>(
  (ref) => createDefaultLinuxRuntime().inspect(),
);
