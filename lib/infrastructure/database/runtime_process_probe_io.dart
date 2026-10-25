import 'dart:ffi';
import 'dart:io';
import 'runtime_process_identity.dart';

final RuntimeProcessProbe defaultRuntimeProcessProbe =
    NativeRuntimeProcessProbe();

/// Read-only OS evidence; no signals, process termination or shell commands.
class NativeRuntimeProcessProbe implements RuntimeProcessProbe {
  static final _self = _identity();
  @override
  RuntimeProcessIdentity? get current => _self;

  static RuntimeProcessIdentity? _identity() {
    final state = _birth(pid);
    return state.$1 == true && state.$2 != null
        ? RuntimeProcessIdentity(Platform.operatingSystem, pid, state.$2!)
        : null;
  }

  @override
  bool? isAlive(RuntimeProcessIdentity identity) {
    if (identity.platform != Platform.operatingSystem) return null;
    final state = _birth(identity.pid);
    if (state.$1 == false) return false;
    if (state.$1 != true || state.$2 == null) return null;
    return state.$2 == identity.birth;
  }

  static (bool?, String?) _birth(int processId) {
    if (processId <= 0 || processId > 0x7fffffff) return (null, null);
    try {
      if (Platform.isWindows) return _windowsBirth(processId);
      if (Platform.isAndroid || Platform.isLinux) {
        // Prove procfs is mounted/readable before interpreting ENOENT as dead.
        if (!File('/proc/self/stat').existsSync()) return (null, null);
        try {
          final stat = File('/proc/$processId/stat').readAsStringSync();
          // comm (field 2) may itself contain spaces and parentheses.
          final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
          if (fields.length <= 19 || int.tryParse(fields[19]) == null) {
            return (null, null);
          }
          if (fields[0] == 'Z' || fields[0] == 'X') return (false, null);
          return (true, fields[19]); // starttime: field 22, since system boot.
        } on FileSystemException catch (error) {
          return error.osError?.errorCode == 2 ? (false, null) : (null, null);
        }
      }
    } catch (_) {/* An inaccessible OS probe must stay fail-closed. */}
    return (null, null);
  }
}

final class _Kernel {
  static final library = DynamicLibrary.open('kernel32.dll');
  static final open = library.lookupFunction<
      Pointer<Void> Function(Uint32, Int32, Uint32),
      Pointer<Void> Function(int, int, int)>('OpenProcess');
  static final close = library.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('CloseHandle');
  static final lastError =
      library.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
  static final heap = library.lookupFunction<Pointer<Void> Function(),
      Pointer<Void> Function()>('GetProcessHeap');
  static final alloc = library.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
      Pointer<Void> Function(Pointer<Void>, int, int)>('HeapAlloc');
  static final free = library.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
      int Function(Pointer<Void>, int, Pointer<Void>)>('HeapFree');
  static final times = library.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>,
          Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>,
          Pointer<Void>)>('GetProcessTimes');
  static final exitCode = library.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint32>)>('GetExitCodeProcess');
}

(bool?, String?) _windowsBirth(int processId) {
  // PROCESS_QUERY_LIMITED_INFORMATION, not termination or VM-read permission.
  final handle = _Kernel.open(0x1000, 0, processId);
  if (handle == nullptr) {
    // ERROR_INVALID_PARAMETER means this positive PID does not exist. Access
    // denied or any other failure is unknown, never evidence of termination.
    return _Kernel.lastError() == 87 ? (false, null) : (null, null);
  }
  Pointer<Void> buffer = nullptr;
  final heap = _Kernel.heap();
  try {
    buffer = _Kernel.alloc(heap, 0, 40);
    if (buffer == nullptr) return (null, null);
    final words = buffer.cast<Uint64>();
    final exit = (words + 4).cast<Uint32>();
    if (_Kernel.exitCode(handle, exit) == 0) return (null, null);
    if (exit.value != 259) return (false, null); // STILL_ACTIVE
    if (_Kernel.times(handle, buffer, (words + 1).cast(), (words + 2).cast(),
            (words + 3).cast()) ==
        0) {
      return (null, null);
    }
    return (true, words.value.toString()); // process creation FILETIME
  } finally {
    if (buffer != nullptr) _Kernel.free(heap, 0, buffer);
    _Kernel.close(handle);
  }
}
