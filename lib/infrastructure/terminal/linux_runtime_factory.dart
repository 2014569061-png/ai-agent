import 'dart:io';

import 'adaptive_linux_runtime_adapter.dart';
import 'android_shell_runtime_adapter.dart';
import 'builtin_proot_runtime_adapter.dart';
import 'host_process_runtime_adapter.dart';
import 'linux_runtime.dart';
import 'termux_runtime_adapter.dart';

/// 创建当前平台的默认 Linux Runtime。
///
/// Android 按“内置 PRoot → Termux → Android Shell”顺序选择，桌面端继续使用
/// 本机进程 Adapter；TerminalCommandService 与 Agent 层无需感知平台分支。
LinuxRuntimeAdapter createDefaultLinuxRuntime() {
  if (Platform.isAndroid) {
    return AdaptiveLinuxRuntimeAdapter([
      BuiltinProotRuntimeAdapter(),
      TermuxRuntimeAdapter(),
      AndroidShellRuntimeAdapter(),
    ]);
  }
  return HostProcessRuntimeAdapter();
}
