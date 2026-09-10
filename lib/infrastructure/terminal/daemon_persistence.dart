import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 后台终端任务的最小持久化记录。
///
/// 记录只保存恢复所需的元数据，不保存命令输出；输出单独写入日志文件，避免
/// daemon 列表膨胀，也避免把完整 stdout 带进数据库备份。
class TerminalDaemonRecord {
  const TerminalDaemonRecord({
    required this.daemonId,
    required this.sessionId,
    required this.command,
    required this.cwd,
    required this.ownerToken,
    required this.startedAt,
    required this.runtimeKind,
    this.pid,
    this.logPath,
    this.completed = false,
    this.exitCode,
    this.timedOut = false,
    this.error,
  });

  final String daemonId;
  final String sessionId;
  final String command;
  final String cwd;
  final String ownerToken;
  final DateTime startedAt;
  final String runtimeKind;
  final int? pid;
  final String? logPath;
  final bool completed;
  final int? exitCode;
  final bool timedOut;
  final String? error;

  TerminalDaemonRecord copyWith({
    int? pid,
    String? logPath,
    bool? completed,
    int? exitCode,
    bool? timedOut,
    String? error,
  }) {
    return TerminalDaemonRecord(
      daemonId: daemonId,
      sessionId: sessionId,
      command: command,
      cwd: cwd,
      ownerToken: ownerToken,
      startedAt: startedAt,
      runtimeKind: runtimeKind,
      pid: pid ?? this.pid,
      logPath: logPath ?? this.logPath,
      completed: completed ?? this.completed,
      exitCode: exitCode ?? this.exitCode,
      timedOut: timedOut ?? this.timedOut,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() => {
        'daemonId': daemonId,
        'sessionId': sessionId,
        'command': command,
        'cwd': cwd,
        'ownerToken': ownerToken,
        'startedAt': startedAt.toIso8601String(),
        'runtimeKind': runtimeKind,
        if (pid != null) 'pid': pid,
        if (logPath != null) 'logPath': logPath,
        'completed': completed,
        if (exitCode != null) 'exitCode': exitCode,
        'timedOut': timedOut,
        if (error != null) 'error': error,
      };

  static TerminalDaemonRecord? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final daemonId = map['daemonId']?.toString();
    final sessionId = map['sessionId']?.toString();
    final command = map['command']?.toString();
    final cwd = map['cwd']?.toString();
    final ownerToken = map['ownerToken']?.toString();
    final startedAt = DateTime.tryParse(map['startedAt']?.toString() ?? '');
    final runtimeKind = map['runtimeKind']?.toString();
    if ([daemonId, sessionId, command, cwd, ownerToken, runtimeKind]
            .any((value) => value == null || value.isEmpty) ||
        startedAt == null) {
      return null;
    }
    return TerminalDaemonRecord(
      daemonId: daemonId!,
      sessionId: sessionId!,
      command: command!,
      cwd: cwd!,
      ownerToken: ownerToken!,
      startedAt: startedAt,
      runtimeKind: runtimeKind!,
      pid: (map['pid'] as num?)?.toInt(),
      logPath: map['logPath']?.toString(),
      completed: map['completed'] == true,
      exitCode: (map['exitCode'] as num?)?.toInt(),
      timedOut: map['timedOut'] == true,
      error: map['error']?.toString(),
    );
  }
}

/// 终端 daemon 的轻量文件存储。
///
/// 默认放在应用私有 support 目录；测试和桌面端可显式传入文件路径。写入使用
/// 临时文件 + rename，避免 App 被系统回收时留下半截 JSON。
class TerminalDaemonPersistence {
  TerminalDaemonPersistence({String? filePath}) : _filePath = filePath;

  static const _version = 1;
  final String? _filePath;
  Future<String>? _resolvedPath;

  Future<String> get path async {
    final existing = _resolvedPath;
    if (existing != null) return existing;
    final future = _resolvePath();
    _resolvedPath = future;
    return future;
  }

  Future<List<TerminalDaemonRecord>> load() async {
    try {
      final file = File(await path);
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const [];
      final rows = decoded['daemons'];
      if (rows is! List) return const [];
      return rows
          .map(TerminalDaemonRecord.fromJson)
          .whereType<TerminalDaemonRecord>()
          .take(8)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(Iterable<TerminalDaemonRecord> records) async {
    final file = File(await path);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.part');
    final payload = jsonEncode({
      'version': _version,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'daemons': records.take(8).map((record) => record.toJson()).toList(),
    });
    await temp.writeAsString(payload, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<String> logPath(String daemonId) async {
    final metadataPath = await path;
    return p.join(p.dirname(metadataPath), 'terminal-daemon-$daemonId.log');
  }

  Future<String> _resolvePath() async {
    final explicit = _filePath?.trim();
    if (explicit != null && explicit.isNotEmpty) return p.normalize(explicit);
    final directory = await getApplicationSupportDirectory();
    return p.join(directory.path, 'terminal-daemons.json');
  }
}
