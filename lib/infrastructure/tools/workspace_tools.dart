import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models.dart';
import 'tool_registry.dart';

/// 工作区沙盒辅助类：防止路径穿越超出工作区根目录
class WorkspaceSandbox {
  WorkspaceSandbox(this.rootPath);
  final String rootPath;

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
    return fullPath;
  }

  /// 获取相对路径展示
  String toRelative(String fullPath) {
    return p.relative(fullPath, from: rootPath).replaceAll('\\', '/');
  }
}

/// 1. 读取文件工具
class ReadFileTool implements AgentTool {
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
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      final path = arguments['path'] as String;
      final fullPath = sandbox.resolvePath(path);
      final file = File(fullPath);

      if (!await file.exists()) {
        return '文件不存在：$path';
      }

      final content = await file.readAsString();
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
        return numbered.join('\n');
      }

      // 如果全量文件很大（超过 2000 行），提示行数并返回前 500 行
      if (lines.length > 2000) {
        final preview = lines.take(500).join('\n');
        return '$preview\n\n... [文件内容过长，共 ${lines.length} 行，已截断。请使用 startLine 和 endLine 分段查看]';
      }

      return content;
    } catch (e) {
      return '读取文件失败：$e';
    }
  }
}

/// 2. 写入/创建文件工具
class WriteFileTool implements AgentTool {
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
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      final path = arguments['path'] as String;
      final content = arguments['content'] as String;
      final fullPath = sandbox.resolvePath(path);
      final file = File(fullPath);

      // 自动创建父目录
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      await file.writeAsString(content);
      return '成功写入文件：$path (${content.length} 字符)';
    } catch (e) {
      return '写入文件失败：$e';
    }
  }
}

/// 3. 局部精确编辑文件工具
class EditFileTool implements AgentTool {
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
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      final path = arguments['path'] as String;
      final target = arguments['targetContent'] as String;
      final replacement = arguments['replacementContent'] as String;
      final fullPath = sandbox.resolvePath(path);
      final file = File(fullPath);

      if (!await file.exists()) {
        return '编辑失败：文件不存在 $path';
      }

      final content = await file.readAsString();
      if (!content.contains(target)) {
        return '编辑失败：未在文件中找到指定的 targetContent 匹配块，请重新读取文件核对内容。';
      }

      // 仅替换一次
      final newContent = content.replaceFirst(target, replacement);
      await file.writeAsString(newContent);
      return '成功修改文件：$path';
    } catch (e) {
      return '编辑文件失败：$e';
    }
  }
}

/// 4. 扫描目录结构工具
class ListDirectoryTool implements AgentTool {
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
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      final relativePath = arguments['path'] as String? ?? '';
      final recursive = arguments['recursive'] as bool? ?? false;
      final fullPath = sandbox.resolvePath(relativePath);
      final dir = Directory(fullPath);

      if (!await dir.exists()) {
        return '目录不存在：$relativePath';
      }

      final entries = <String>[];
      final lister = dir.list(recursive: recursive, followLinks: false);

      await for (final entity in lister) {
        final rel = sandbox.toRelative(entity.path);
        final isDir = entity is Directory;
        entries.add('${isDir ? "📁 [目录]" : "📄 [文件]"} $rel');
      }

      if (entries.isEmpty) {
        return '目录为空：$relativePath';
      }

      entries.sort();
      return entries.join('\n');
    } catch (e) {
      return '列出目录失败：$e';
    }
  }
}

/// 5. 代码搜索工具
class SearchFilesTool implements AgentTool {
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
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      final query = arguments['query'] as String;
      final ext = arguments['fileExtension'] as String?;
      final dir = Directory(sandbox.rootPath);

      if (!await dir.exists()) {
        return '工作区目录不存在';
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
        return '未搜索到匹配项："$query"';
      }

      return results.join('\n');
    } catch (e) {
      return '搜索失败：$e';
    }
  }
}

/// 6. 删除文件工具（高风险）
class DeleteFileTool implements AgentTool {
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
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      final path = arguments['path'] as String;
      final fullPath = sandbox.resolvePath(path);
      final file = File(fullPath);
      final dir = Directory(fullPath);

      if (await file.exists()) {
        await file.delete();
        return '成功删除文件：$path';
      } else if (await dir.exists()) {
        await dir.delete();
        return '成功删除目录：$path';
      } else {
        return '文件或目录不存在：$path';
      }
    } catch (e) {
      return '删除失败：$e';
    }
  }
}
