import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'linux_runtime.dart';

/// Runs an ARM64 Alpine user space through the PRoot binary bundled in the APK.
///
/// The native bridge owns the Android process lifecycle. This adapter owns the
/// Flutter asset lifecycle, including integrity verification and atomic rootfs
/// installation into application-private storage.
class BuiltinProotRuntimeAdapter implements LinuxRuntimeAdapter {
  BuiltinProotRuntimeAdapter({
    this.maxOutputBytes = 128 * 1024,
    this.rootfsAssetPath = _defaultRootfsAssetPath,
    MethodChannel? bridge,
    Future<Directory> Function()? applicationSupportDirectory,
    AssetBundle? assetBundle,
  })  : _bridge = bridge ?? const MethodChannel(_channelName),
        _applicationSupportDirectory =
            applicationSupportDirectory ?? getApplicationSupportDirectory,
        _assetBundle = assetBundle ?? rootBundle;

  static const _channelName = 'nexus/builtin_linux';
  static const _defaultRootfsAssetPath =
      'assets/linux/alpine-minirootfs-3.22.5-aarch64.tar.gz';
  static const _tallocAssetPath = 'assets/linux/libtalloc.so.2';
  static const _rootfsVersion = 'alpine-3.22.5-aarch64';
  static const _rootfsSha256 =
      '3fbc6285032ed46821b511292633d7b2a6306a2e254f590e92bdafff56cf2f70';
  static const _tallocSha256 =
      '3c9b207c0a6ea2896b7523e03f55d9ab0d9e88baa115d4c32b84058ff4246fbb';

  final int maxOutputBytes;
  final String rootfsAssetPath;
  final MethodChannel _bridge;
  final Future<Directory> Function() _applicationSupportDirectory;
  final AssetBundle _assetBundle;

  bool _running = false;
  Future<String>? _preparingRootfs;

  @override
  LinuxRuntimeKind get kind => LinuxRuntimeKind.builtinProot;

  @override
  bool get supportsShellSyntax => true;

  @override
  bool get supportsInterpreterEvaluation => true;

  @override
  bool get isRunning => _running;

  @override
  Future<LinuxRuntimeInfo> inspect() async {
    if (!Platform.isAndroid) {
      return const LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.builtinProot,
        label: '内置 PRoot',
        available: false,
        detail: '内置 PRoot 仅在 Android ARM64 上可用。',
      );
    }

    try {
      final raw = await _bridge.invokeMethod<Map<dynamic, dynamic>>('inspect');
      final available = raw?['available'] == true;
      return LinuxRuntimeInfo(
        kind: kind,
        label: '内置 Alpine Linux',
        available: available,
        detail: raw?['detail']?.toString() ??
            (available ? 'PRoot ARM64 运行时已就绪。' : 'PRoot 原生资源不完整。'),
        supportsInteractive: false,
        supportsShellSyntax: true,
        requiresExternalApp: false,
      );
    } on MissingPluginException {
      return const LinuxRuntimeInfo(
        kind: LinuxRuntimeKind.builtinProot,
        label: '内置 Alpine Linux',
        available: false,
        detail: '当前平台没有注册内置 Linux 原生桥。',
      );
    } catch (error) {
      return LinuxRuntimeInfo(
        kind: kind,
        label: '内置 Alpine Linux',
        available: false,
        detail: '内置 PRoot 检测失败：$error',
      );
    }
  }

  @override
  Future<CommandResult> run(
    LinuxCommandRequest request, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    if (!Platform.isAndroid) {
      return const CommandResult(
        output: '[builtin-proot] 该运行时仅支持 Android。',
        exitCode: 127,
      );
    }

    _running = true;
    try {
      final rootfsPath = await _ensureRootfs();
      final runtimeLibraryPath =
          p.join(Directory(rootfsPath).parent.path, 'native-libs');
      final raw = await _bridge.invokeMethod<Map<dynamic, dynamic>>('run', {
        'command': request.commandLine,
        'workingDirectory': workingDirectory,
        'rootfsPath': rootfsPath,
        'runtimeLibraryPath': runtimeLibraryPath,
        'timeoutMs': timeout.inMilliseconds,
        'maxOutputBytes': maxOutputBytes,
      }).timeout(timeout + const Duration(seconds: 5));
      return _decodeResult(raw);
    } on TimeoutException {
      stop();
      return CommandResult(
        output: '[builtin-proot] 命令执行超时（${timeout.inSeconds}s）。',
        exitCode: 124,
        timedOut: true,
      );
    } on MissingPluginException {
      return const CommandResult(
        output: '[builtin-proot] Android 原生桥不可用。',
        exitCode: 127,
      );
    } on PlatformException catch (error) {
      return CommandResult(
        output: '[builtin-proot] 原生进程启动失败：${error.message ?? error.code}',
        exitCode: 127,
      );
    } catch (error) {
      return CommandResult(
        output: '[builtin-proot] 运行时准备失败：$error',
        exitCode: 127,
      );
    } finally {
      _running = false;
    }
  }

  @override
  void stop() {
    unawaited(_bridge.invokeMethod<void>('stop'));
  }

  Future<String> _ensureRootfs() {
    final inFlight = _preparingRootfs;
    if (inFlight != null) return inFlight;

    final future = _prepareRootfs();
    _preparingRootfs = future;
    future.then<void>(
      (_) {
        if (identical(_preparingRootfs, future)) _preparingRootfs = null;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_preparingRootfs, future)) _preparingRootfs = null;
      },
    );
    return future;
  }

  Future<String> _prepareRootfs() async {
    final supportDirectory = await _applicationSupportDirectory();
    final runtimeDirectory =
        Directory(p.join(supportDirectory.path, 'linux-runtime'));
    await runtimeDirectory.create(recursive: true);

    final rootfsDirectory =
        Directory(p.join(runtimeDirectory.path, 'alpine-rootfs'));
    await _ensureNativeLibraries(runtimeDirectory);
    final marker = File(
      p.join(runtimeDirectory.path, '$_rootfsVersion.ready'),
    );
    if (await marker.exists() && _isValidRootfs(rootfsDirectory)) {
      return rootfsDirectory.path;
    }

    if (await marker.exists()) {
      await marker.delete();
    }

    final data = await _assetBundle.load(rootfsAssetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final digest = sha256.convert(bytes).toString();
    if (digest != _rootfsSha256) {
      throw StateError(
        'Alpine rootfs 校验失败：期望 $_rootfsSha256，实际 $digest',
      );
    }

    final token = DateTime.now().microsecondsSinceEpoch;
    final stagingDirectory = Directory(
      p.join(runtimeDirectory.path, 'alpine-rootfs.staging-$token'),
    );

    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete(recursive: true);
    }
    await stagingDirectory.create(recursive: true);

    try {
      final tarBytes = const GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(tarBytes);
      _rewriteAbsoluteSymlinks(archive);
      await extractArchiveToDisk(archive, stagingDirectory.path);
      if (!_isValidRootfs(stagingDirectory)) {
        throw StateError('Alpine rootfs 解压后缺少 /bin/sh 或 musl loader。');
      }

      if (await rootfsDirectory.exists()) {
        await rootfsDirectory.delete(recursive: true);
      }
      await stagingDirectory.rename(rootfsDirectory.path);
      await marker.writeAsString(_rootfsVersion, flush: true);
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
    }

    return rootfsDirectory.path;
  }

  bool _isValidRootfs(Directory directory) {
    return File(p.join(directory.path, 'bin/sh')).existsSync() &&
        File(p.join(directory.path, 'lib/ld-musl-aarch64.so.1')).existsSync();
  }

  /// Alpine's minirootfs uses absolute links such as /bin/sh -> /bin/busybox.
  /// Convert them to rootfs-local relative links before using archive_io's
  /// traversal-safe extractor; otherwise those links would be discarded.
  void _rewriteAbsoluteSymlinks(Archive archive) {
    final posix = p.Context(style: p.Style.posix);
    for (final entry in archive) {
      final target = entry.symbolicLink;
      if (target == null || !target.startsWith('/')) continue;
      final linkName = posix.normalize(entry.name);
      final linkDirectory = posix.dirname(linkName);
      final targetName = posix.normalize(target.substring(1));
      entry.symbolicLink = posix.relative(targetName, from: linkDirectory);
    }
  }

  Future<void> _ensureNativeLibraries(Directory runtimeDirectory) async {
    final nativeDirectory =
        Directory(p.join(runtimeDirectory.path, 'native-libs'));
    await nativeDirectory.create(recursive: true);
    final talloc = File(p.join(nativeDirectory.path, 'libtalloc.so.2'));
    if (await talloc.exists() && await talloc.length() > 0) return;

    final data = await _assetBundle.load(_tallocAssetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final digest = sha256.convert(bytes).toString();
    if (digest != _tallocSha256) {
      throw StateError(
        'libtalloc 校验失败：期望 $_tallocSha256，实际 $digest',
      );
    }

    final partial = File('${talloc.path}.part');
    await partial.writeAsBytes(bytes, flush: true);
    if (await talloc.exists()) await talloc.delete();
    await partial.rename(talloc.path);
  }

  CommandResult _decodeResult(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return const CommandResult(
        output: '[builtin-proot] 原生桥没有返回执行结果。',
        exitCode: 127,
      );
    }
    var output = raw['output']?.toString() ?? '';
    if (output.length > maxOutputBytes) {
      output = output.substring(output.length - maxOutputBytes);
      output = '[输出已截断]\n$output';
    }
    final exitCode = (raw['exitCode'] as num?)?.toInt() ?? 127;
    return CommandResult(
      output: output,
      exitCode: exitCode,
      timedOut: raw['timedOut'] == true || exitCode == 124,
    );
  }
}
