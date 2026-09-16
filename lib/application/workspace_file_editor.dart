import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../infrastructure/tools/workspace_tools.dart';
import 'file_citation.dart';

class WorkspaceFileBuffer {
  const WorkspaceFileBuffer({
    required this.relativePath,
    required this.content,
    required this.hash,
    required this.encoding,
    required this.newline,
    required this.bytes,
  });

  final String relativePath;
  final String content;
  final String hash;
  final String encoding;
  final String newline;
  final int bytes;
}

class ConcurrentEditException implements Exception {
  const ConcurrentEditException(this.currentHash);
  final String currentHash;
  @override
  String toString() => '文件已被其他进程修改，请重新载入后再保存';
}

class WorkspaceFileEditor {
  const WorkspaceFileEditor();

  Future<WorkspaceFileBuffer> open({
    required String workspacePath,
    required String relativePath,
    int maxBytes = 1024 * 1024,
  }) async {
    final sandbox = WorkspaceSandbox(workspacePath);
    final file = File(sandbox.resolvePath(relativePath));
    if (!await file.exists()) {
      throw ArgumentError('文件不存在：$relativePath');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      throw StateError('文件过大，请先用范围读取而不是整文件打开');
    }
    final content = utf8.decode(bytes, allowMalformed: false);
    return WorkspaceFileBuffer(
      relativePath: sandbox.toRelative(file.path),
      content: content,
      hash: sha256.convert(bytes).toString(),
      encoding: 'utf-8',
      newline: content.contains('\r\n') ? 'crlf' : 'lf',
      bytes: bytes.length,
    );
  }

  Future<FileCitation> citeSelection({
    required String projectId,
    required WorkspaceFileBuffer buffer,
    int? startLine,
    int? endLine,
  }) {
    final lines = const LineSplitter().convert(buffer.content);
    final start = ((startLine ?? 1) - 1).clamp(0, lines.length);
    final end = (endLine ?? startLine ?? lines.length).clamp(start + 1, lines.length);
    return Future.value(FileCitation(
      projectId: projectId,
      relativePath: buffer.relativePath,
      contentHash: buffer.hash,
      startLine: startLine,
      endLine: endLine,
      excerpt: lines.sublist(start, end).join('\n'),
    ));
  }

  Future<WorkspaceFileBuffer> save({
    required String workspacePath,
    required WorkspaceFileBuffer original,
    required String content,
  }) async {
    final sandbox = WorkspaceSandbox(workspacePath);
    final file = File(sandbox.resolvePath(original.relativePath));
    if (await file.exists()) {
      final current = sha256.convert(await file.readAsBytes()).toString();
      if (current != original.hash) {
        throw ConcurrentEditException(current);
      }
    }
    final normalized = original.newline == 'crlf'
        ? content.replaceAll('\n', '\r\n').replaceAll('\r\r\n', '\r\n')
        : content.replaceAll('\r\n', '\n');
    final temp = File('${file.path}.nexus-tmp');
    await temp.writeAsString(normalized, flush: true);
    await temp.rename(file.path);
    return open(workspacePath: workspacePath, relativePath: original.relativePath);
  }
}
