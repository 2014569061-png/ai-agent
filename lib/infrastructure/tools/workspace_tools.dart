import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import '../observability/unified_diff.dart';
import 'tool_registry.dart';

/// 工作区沙盒辅助类：防止路径穿越超出工作区根目录
class WorkspaceSandbox {
  WorkspaceSandbox(this.rootPath);
  final String rootPath;

  /// 真实根目录缓存（解析符号链接后的 realpath，惰性求值一次）。
  String? _realRoot;

  /// 解析并验证绝对路径，确保在根目录内
  String resolvePath(String relativePath) {
    // 规范化路径
    final normalizedRelative = relativePath.replaceAll('\\', '/').trim();
    final fullPath = p.normalize(p.join(rootPath, normalizedRelative));
    final normalizedRoot = p.normalize(rootPath);
    final relative = p.relative(fullPath, from: normalizedRoot);

    if (relative == '..' || relative.startsWith('..${p.separator}')) {
      throw ArgumentError('非法路径访问：禁止超出当前工作区根目录');
    }
    _guardSymlinkEscape(fullPath);
    return fullPath;
  }

  /// B-5：词法校验挡不住符号链接 —— 工作区内指向外部的 symlink 能骗过纯字符串
  /// 的 normalize。对目标（尚不存在时取其最近的已存在祖先）做 realpath 解析后
  /// 再验一次真实边界。每次调用只多 1-2 次系统调用，不值得引入缓存失效逻辑。
  void _guardSymlinkEscape(String fullPath) {
    var probe = fullPath;
    while (FileSystemEntity.typeSync(probe) == FileSystemEntityType.notFound) {
      final parent = p.dirname(probe);
      if (parent == probe) return; // 到达文件系统根仍不存在，无链接可解析
      probe = parent;
    }
    _realRoot ??= Directory(rootPath).existsSync()
        ? Directory(rootPath).resolveSymbolicLinksSync()
        : p.normalize(rootPath);
    final realProbe = Directory(probe).resolveSymbolicLinksSync();
    final realRelative = p.relative(realProbe, from: _realRoot!);
    if (realRelative == '..' || realRelative.startsWith('..${p.separator}')) {
      throw ArgumentError('非法路径访问：路径经由符号链接超出工作区根目录');
    }
  }

  /// 获取相对路径展示
  String toRelative(String fullPath) {
    return p.relative(fullPath, from: rootPath).replaceAll('\\', '/');
  }
}

mixin _FileMetadata implements ToolExecutionMetadata {
  @override
  Map<String, dynamic> lastMetadata = const {};

  void clearMetadata() => lastMetadata = const {};

  void recordMetadata(Map<String, dynamic> metadata) {
    lastMetadata = Map<String, dynamic>.unmodifiable(metadata);
  }

  void recordFile(
      {required String operation,
      required String path,
      String before = '',
      String after = ''}) {
    if (operation == 'read') {
      final result = buildUnifiedDiff('', after);
      lastMetadata = {
        'operation': operation,
        'path': path,
        'bytesBefore': 0,
        'bytesAfter': result.bytesAfter,
        'linesAdded': 0,
        'linesRemoved': 0,
        'contentHashAfter': result.contentHashAfter,
      };
      return;
    }
    final result = buildUnifiedDiff(
      before,
      after,
      oldPath: 'a/$path',
      newPath: 'b/$path',
    );
    lastMetadata = result.toMetadata(operation: operation, path: path);
  }

  void recordMove({
    required String oldPath,
    required String newPath,
    String? content,
  }) {
    if (content == null) {
      recordMetadata({
        'operation': 'move',
        'path': newPath,
        'oldPath': oldPath,
        'moved': true,
      });
      return;
    }
    final result = buildUnifiedDiff(
      content,
      content,
      oldPath: 'a/$oldPath',
      newPath: 'b/$newPath',
    );
    recordMetadata({
      ...result.toMetadata(operation: 'move', path: newPath),
      'oldPath': oldPath,
      'moved': true,
    });
  }
}

/// 1. 读取文件工具
class ReadFileTool with _FileMetadata implements AgentTool {
  ReadFileTool({required this.sandbox});
  final WorkspaceSandbox sandbox;

  @override
  final manifest = const UnifiedTool(
    name: 'read_file',
    description: '读取工作区内的指定文件内容。可选择起止行号切片读取。',
    risk: ToolRisk.safe,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': '文件在工作区中的相对路径，如 src/index.js 或 index.html'
        },
        'startLine': {'type': 'integer', 'description': '起始行号（从 1 开始，可选）'},
        'endLine': {'type': 'integer', 'description': '结束行号（可选）'},
      },
      'required': ['path'],
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    clearMetadata();
    final path = arguments['path'];
    if (path is! String || path.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'path 必须是非空字符串',
      );
    }
    final String fullPath;
    try {
      fullPath = sandbox.resolvePath(path);
    } on ArgumentError catch (e) {
      return ToolResult.failure(
        code: ToolCodes.sandboxViolation,
        message: '路径越出工作区：${e.message}',
      );
    }
    try {
      final file = File(fullPath);

      if (!await file.exists()) {
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '文件不存在：$path',
        );
      }

      final content = await file.readAsString();
      recordFile(operation: 'read', path: path, after: content);
      final lines = const LineSplitter().convert(content);

      final startLine = arguments['startLine'] as int?;
      final endLine = arguments['endLine'] as int?;

      if (startLine != null || endLine != null) {
        final start = ((startLine ?? 1) - 1).clamp(0, lines.length);
        final end = (endLine ?? lines.length).clamp(start, lines.length);
        final slice = lines.sublist(start, end);
        final numbered = <String>[];
        for (var i = 0; i < slice.length; i++) {
          numbered.add('${start + i + 1}: ${slice[i]}');
        }
        return ToolResult.text(numbered.join('\n'), extra: {
          'path': path,
          'totalLines': lines.length,
          'sliced': true,
        });
      }

      // 如果全量文件很大（超过 2000 行），提示行数并返回前 500 行
      if (lines.length > 2000) {
        final preview = lines.take(500).join('\n');
        return ToolResult.text(
          '$preview\n\n... [文件内容过长，共 ${lines.length} 行，已截断。请使用 startLine 和 endLine 分段查看]',
          extra: {'path': path, 'totalLines': lines.length, 'truncated': true},
        );
      }

      return ToolResult.text(content,
          extra: {'path': path, 'totalLines': lines.length});
    } catch (e) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: '读取文件失败：$e',
      );
    }
  }
}

/// 2. 写入/创建文件工具
class WriteFileTool with _FileMetadata implements AgentTool {
  WriteFileTool({required this.sandbox});
  final WorkspaceSandbox sandbox;

  @override
  final manifest = const UnifiedTool(
    name: 'write_file',
    description: '在工作区中创建新文件或覆写文件。会自动递归创建缺失的父级目录。',
    risk: ToolRisk.requiresConfirmation,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '文件在工作区中的相对路径，如 index.html'},
        'content': {'type': 'string', 'description': '要写入的文件完整文本内容'},
      },
      'required': ['path', 'content'],
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    clearMetadata();
    final path = arguments['path'];
    final content = arguments['content'];
    if (path is! String || path.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'path 必须是非空字符串',
      );
    }
    if (content is! String) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'content 必须是字符串',
      );
    }
    final String fullPath;
    try {
      fullPath = sandbox.resolvePath(path);
    } on ArgumentError catch (e) {
      return ToolResult.failure(
        code: ToolCodes.sandboxViolation,
        message: '路径越出工作区：${e.message}',
      );
    }

    final file = File(fullPath);
    // committed 之前抛错说明还没碰过磁盘（effect=none）；
    // 之后抛错必须按“可能已经写进去了”上报，让模型先读再决定是否重试。
    var committed = false;
    try {
      final before = await file.exists() ? await file.readAsString() : '';

      // 自动创建父目录
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      await file.writeAsString(content);
      committed = true;
      recordFile(
          operation: before.isEmpty ? 'create' : 'write',
          path: path,
          before: before,
          after: content);
      return ToolResult.success(
        message: '成功写入文件：$path (${content.length} 字符)',
        data: {
          'path': path,
          'chars': content.length,
          'created': before.isEmpty,
        },
        effect: ToolEffect.applied,
      );
    } catch (e) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: committed
            ? '文件已写入但记录变更元数据失败：$e'
            : '写入过程中断：$e；文件可能已被部分修改，'
                '请先 read_file 确认当前内容再决定是否重试',
        effect: committed ? ToolEffect.applied : ToolEffect.unknown,
      );
    }
  }
}

/// 3. 局部精确编辑文件工具
class EditFileTool with _FileMetadata implements AgentTool {
  EditFileTool({required this.sandbox});
  final WorkspaceSandbox sandbox;

  @override
  final manifest = const UnifiedTool(
    name: 'edit_file',
    description: '局部替换文件中的某一段文本。适用于修改已存在文件的局部代码。',
    risk: ToolRisk.requiresConfirmation,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '文件在工作区中的相对路径'},
        'targetContent': {'type': 'string', 'description': '要被替换的原有精确文本代码块'},
        'replacementContent': {'type': 'string', 'description': '替换后的新文本代码块'},
      },
      'required': ['path', 'targetContent', 'replacementContent'],
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    clearMetadata();
    final path = arguments['path'];
    final target = arguments['targetContent'];
    final replacement = arguments['replacementContent'];
    if (path is! String || path.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'path 必须是非空字符串',
      );
    }
    if (target is! String || replacement is! String) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'targetContent 与 replacementContent 必须是字符串',
      );
    }
    final String fullPath;
    try {
      fullPath = sandbox.resolvePath(path);
    } on ArgumentError catch (e) {
      return ToolResult.failure(
        code: ToolCodes.sandboxViolation,
        message: '路径越出工作区：${e.message}',
      );
    }

    final file = File(fullPath);
    var committed = false;
    try {
      if (!await file.exists()) {
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '编辑失败：文件不存在 $path',
        );
      }

      final content = await file.readAsString();
      if (!content.contains(target)) {
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '编辑失败：未在文件中找到指定的 targetContent 匹配块，'
              '请重新读取文件核对内容。',
        );
      }

      // 仅替换一次
      final newContent = content.replaceFirst(target, replacement);
      await file.writeAsString(newContent);
      committed = true;
      recordFile(
          operation: 'edit', path: path, before: content, after: newContent);
      return ToolResult.success(
        message: '成功修改文件：$path',
        data: {'path': path, 'chars': newContent.length},
        effect: ToolEffect.applied,
      );
    } catch (e) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: committed
            ? '文件已修改但记录变更元数据失败：$e'
            : '编辑过程中断：$e；文件可能已被部分修改，'
                '请先 read_file 确认当前内容再决定是否重试',
        effect: committed ? ToolEffect.applied : ToolEffect.unknown,
      );
    }
  }
}

/// 4. 扫描目录结构工具
class ListDirectoryTool with _FileMetadata implements AgentTool {
  ListDirectoryTool({required this.sandbox});
  final WorkspaceSandbox sandbox;

  @override
  final manifest = const UnifiedTool(
    name: 'list_directory',
    description: '列出工作区内指定目录的文件和子文件夹结构。',
    risk: ToolRisk.safe,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '相对目录路径，根目录传入空字符串 "" 或 "."'},
        'recursive': {'type': 'boolean', 'description': '是否递归扫描子目录，默认为 false'},
      },
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    clearMetadata();
    final relativePath = arguments['path'] as String? ?? '';
    final recursive = arguments['recursive'] == true;
    final String fullPath;
    try {
      fullPath = sandbox.resolvePath(relativePath);
    } on ArgumentError catch (e) {
      return ToolResult.failure(
        code: ToolCodes.sandboxViolation,
        message: '路径越出工作区：${e.message}',
      );
    }
    try {
      final dir = Directory(fullPath);
      final displayPath = relativePath.isEmpty ? '.' : relativePath;

      if (!await dir.exists()) {
        recordMetadata({
          'operation': 'list',
          'path': displayPath,
          'recursive': recursive,
          'exists': false,
        });
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '目录不存在：$relativePath',
        );
      }

      final entries = <String>[];
      final lister = dir.list(recursive: recursive, followLinks: false);

      await for (final entity in lister) {
        final rel = sandbox.toRelative(entity.path);
        final isDir = entity is Directory;
        entries.add('${isDir ? "📁 [目录]" : "📄 [文件]"} $rel');
      }

      if (entries.isEmpty) {
        recordMetadata({
          'operation': 'list',
          'path': displayPath,
          'recursive': recursive,
          'entryCount': 0,
        });
        return ToolResult.success(
          message: '目录为空：$relativePath',
          data: {'path': displayPath, 'entryCount': 0},
        );
      }

      entries.sort();
      recordMetadata({
        'operation': 'list',
        'path': displayPath,
        'recursive': recursive,
        'entryCount': entries.length,
      });
      return ToolResult.text(entries.join('\n'), extra: {
        'path': displayPath,
        'entryCount': entries.length,
        'recursive': recursive,
      });
    } catch (e) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: '列出目录失败：$e',
      );
    }
  }
}

/// 5. 代码搜索工具
class SearchFilesTool with _FileMetadata implements AgentTool {
  SearchFilesTool({required this.sandbox});
  final WorkspaceSandbox sandbox;

  @override
  final manifest = const UnifiedTool(
    name: 'search_files',
    description: '在工作区的所有文本/代码文件中快速全文搜索指定关键字。',
    risk: ToolRisk.safe,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': '要搜索的关键字或文本'},
        'fileExtension': {
          'type': 'string',
          'description': '可选的文件后缀过滤，如 ".dart" 或 ".html"'
        },
      },
      'required': ['query'],
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    clearMetadata();
    final query = arguments['query'];
    if (query is! String || query.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'query 必须是非空字符串',
      );
    }
    final ext = arguments['fileExtension'] as String?;
    try {
      final dir = Directory(sandbox.rootPath);

      if (!await dir.exists()) {
        recordMetadata({
          'operation': 'search',
          'path': '.',
          'query': query,
          'exists': false,
        });
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '工作区目录不存在',
        );
      }

      final results = <String>[];
      final lister = dir.list(recursive: true, followLinks: false);

      await for (final entity in lister) {
        if (entity is File) {
          if (ext != null && !entity.path.endsWith(ext)) continue;

          // 忽略常见的编译产物和二进制目录
          if (entity.path.contains('.git') ||
              entity.path.contains('.dart_tool') ||
              entity.path.contains('build') ||
              entity.path.contains('node_modules')) {
            continue;
          }

          try {
            final content = await entity.readAsString();
            if (content.contains(query)) {
              final rel = sandbox.toRelative(entity.path);
              final lines = const LineSplitter().convert(content);
              for (var i = 0; i < lines.length; i++) {
                if (lines[i].contains(query)) {
                  results.add('$rel:${i + 1}: ${lines[i].trim()}');
                  if (results.length >= 50) break;
                }
              }
            }
          } catch (_) {
            // 忽略二进制文件读取错误
          }
        }
        if (results.length >= 50) break;
      }

      if (results.isEmpty) {
        recordMetadata({
          'operation': 'search',
          'path': '.',
          'query': query,
          'fileExtension': ext,
          'matchCount': 0,
        });
        // 搜索无命中是正常结果而非失败：模型据此换关键词，不该触发重试。
        return ToolResult.success(
          message: '未搜索到匹配项："$query"',
          data: {'query': query, 'matchCount': 0},
        );
      }

      recordMetadata({
        'operation': 'search',
        'path': '.',
        'query': query,
        'fileExtension': ext,
        'matchCount': results.length,
        'truncated': results.length >= 50,
      });
      return ToolResult.text(results.join('\n'), extra: {
        'query': query,
        'matchCount': results.length,
        'truncated': results.length >= 50,
      });
    } catch (e) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: '搜索失败：$e',
      );
    }
  }
}

/// 6. 删除文件工具（高风险）
class DeleteFileTool with _FileMetadata implements AgentTool {
  DeleteFileTool({required this.sandbox});
  final WorkspaceSandbox sandbox;

  @override
  final manifest = const UnifiedTool(
    name: 'delete_file',
    description: '删除工作区中的指定文件或空目录。此操作不可逆，需要用户确认。',
    risk: ToolRisk.dangerous,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '要删除的文件在工作区中的相对路径'},
      },
      'required': ['path'],
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    clearMetadata();
    final path = arguments['path'];
    if (path is! String || path.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'path 必须是非空字符串',
      );
    }
    final String fullPath;
    try {
      fullPath = sandbox.resolvePath(path);
    } on ArgumentError catch (e) {
      return ToolResult.failure(
        code: ToolCodes.sandboxViolation,
        message: '路径越出工作区：${e.message}',
      );
    }

    final file = File(fullPath);
    final dir = Directory(fullPath);
    var committed = false;
    try {
      if (await file.exists()) {
        // 二进制文件读不成字符串也必须能删，否则删除会被前置读取卡死。
        String? before;
        try {
          before = await file.readAsString();
        } catch (_) {
          before = null;
        }
        await file.delete();
        committed = true;
        recordFile(operation: 'delete', path: path, before: before ?? '');
        return ToolResult.success(
          message: '成功删除文件：$path',
          data: {'path': path, 'kind': 'file', 'recoverable': false},
          effect: ToolEffect.applied,
        );
      } else if (await dir.exists()) {
        await dir.delete();
        committed = true;
        recordFile(operation: 'delete', path: path);
        return ToolResult.success(
          message: '成功删除目录：$path',
          data: {'path': path, 'kind': 'directory', 'recoverable': false},
          effect: ToolEffect.applied,
        );
      } else {
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '文件或目录不存在：$path',
        );
      }
    } catch (e) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: committed
            ? '目标已删除但记录元数据失败：$e'
            : '删除过程中断：$e；目标可能已被删除，'
                '请先 list_directory 或 read_file 确认再决定是否重试',
        effect: committed ? ToolEffect.applied : ToolEffect.unknown,
      );
    }
  }
}

/// Moves a file or directory inside the workspace. The destination must not
/// already exist so an accidental overwrite cannot happen silently.
class MoveFileTool with _FileMetadata implements AgentTool {
  MoveFileTool({required this.sandbox});
  final WorkspaceSandbox sandbox;

  @override
  final manifest = const UnifiedTool(
    name: 'move_file',
    description: '在工作区内移动文件或目录，同时保留移动元数据。',
    risk: ToolRisk.requiresConfirmation,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '源文件或目录相对路径'},
        'newPath': {'type': 'string', 'description': '目标路径'},
      },
      'required': ['path', 'newPath'],
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    clearMetadata();
    final oldPath = arguments['path'];
    final newPath = arguments['newPath'];
    if (oldPath is! String || oldPath.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'path 必须是非空字符串',
      );
    }
    if (newPath is! String || newPath.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'newPath 必须是非空字符串',
      );
    }
    final String sourcePath;
    final String targetPath;
    try {
      sourcePath = sandbox.resolvePath(oldPath);
      targetPath = sandbox.resolvePath(newPath);
    } on ArgumentError catch (e) {
      return ToolResult.failure(
        code: ToolCodes.sandboxViolation,
        message: '路径越出工作区：${e.message}',
      );
    }

    // 一旦开始创建目标父目录，世界就可能已经变了；此后失败一律 unknown。
    var touched = false;
    try {
      if (sourcePath == targetPath) {
        recordMetadata({
          'operation': 'move',
          'path': newPath,
          'oldPath': oldPath,
          'moved': false,
          'reason': 'same_path',
        });
        return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: '移动路径与源路径相同',
        );
      }

      final sourceFile = File(sourcePath);
      final sourceDir = Directory(sourcePath);
      if (!await sourceFile.exists() && !await sourceDir.exists()) {
        recordMetadata({
          'operation': 'move',
          'path': newPath,
          'oldPath': oldPath,
          'moved': false,
          'reason': 'source_missing',
        });
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '源文件或目录不存在：$oldPath',
        );
      }
      if (await File(targetPath).exists() ||
          await Directory(targetPath).exists()) {
        recordMetadata({
          'operation': 'move',
          'path': newPath,
          'oldPath': oldPath,
          'moved': false,
          'reason': 'destination_exists',
        });
        return ToolResult.failure(
          code: ToolCodes.alreadyExists,
          message: '移动失败：目标路径已存在 $newPath',
        );
      }

      final targetParent = Directory(targetPath).parent;
      if (!await targetParent.exists()) {
        await targetParent.create(recursive: true);
        touched = true;
      }

      String? content;
      if (await sourceFile.exists()) {
        try {
          content = await sourceFile.readAsString();
        } catch (_) {
          content = null;
        }
        await sourceFile.rename(targetPath);
      } else {
        await sourceDir.rename(targetPath);
      }
      recordMove(oldPath: oldPath, newPath: newPath, content: content);
      return ToolResult.success(
        message: '成功移动：$oldPath -> $newPath',
        data: {'oldPath': oldPath, 'newPath': newPath},
        effect: ToolEffect.applied,
      );
    } catch (e) {
      return ToolResult.failure(
        code: ToolCodes.toolError,
        message: touched
            ? '移动过程中断：$e；目标父目录可能已创建、源可能已被改名，'
                '请先 list_directory 确认两端状态再决定是否重试'
            : '移动失败：$e',
        effect: touched ? ToolEffect.unknown : ToolEffect.none,
      );
    }
  }
}
