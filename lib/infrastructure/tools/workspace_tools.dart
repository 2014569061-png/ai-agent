import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import '../observability/unified_diff.dart';
import '../files/bounded_text_reader.dart';
import '../files/workspace_fs.dart';
import '../files/patch_journal.dart';
import 'tool_registry.dart';

/// 工作区沙盒辅助类：防止路径穿越超出工作区根目录
class WorkspaceSandbox {
  WorkspaceSandbox(this.rootPath,
      {WorkspaceFs? fs, this.requireReadBeforeWrite = false})
      : fs = fs ?? const LocalWorkspaceFs();
  final String rootPath;

  /// 文件工具经由它访问文件（能力 seam）；路径校验仍在本类完成。
  final WorkspaceFs fs;

  /// Enabled for agent tool registries; UI editors own their own baselines.
  final bool requireReadBeforeWrite;
  final _readHashes = <String, String>{};

  void forgetReads() => _readHashes.clear();

  PatchJournal get patchJournal => PatchJournal(
      root: rootPath,
      fs: fs,
      resolve: (path) => resolvePath(path, allowRoot: false));

  Future<ToolResult?> prepareForWrite() async {
    final result = await patchJournal.recover();
    if (result != null) forgetReads();
    return result;
  }

  String _key(String path) => Platform.isWindows ? path.toLowerCase() : path;

  void rememberRead(String path, String content) {
    final key = _key(path);
    _readHashes.remove(key);
    _readHashes[key] = sha256.convert(utf8.encode(content)).toString();
    if (_readHashes.length > 128) _readHashes.remove(_readHashes.keys.first);
  }

  ToolResult? checkFresh(String path, String content) {
    if (!requireReadBeforeWrite) return null;
    final expected = _readHashes[_key(path)];
    if (expected == null) {
      return ToolResult.failure(
          code: ToolCodes.readRequired,
          message: '修改已有文件前必须先调用 read_file 读取当前文件，再基于读取结果编辑。');
    }
    if (expected != sha256.convert(utf8.encode(content)).toString()) {
      return ToolResult.failure(
          code: ToolCodes.revisionConflict,
          message: '文件在读取后已变化，本次未修改。请重新 read_file 并根据最新内容重新生成修改。');
    }
    return null;
  }

  /// 真实根目录缓存（解析符号链接后的 realpath，惰性求值一次）。
  String? _realRoot;

  /// 解析并验证绝对路径，确保在根目录内
  String resolvePath(String relativePath, {bool allowRoot = true}) {
    // 规范化路径
    final normalizedRelative = relativePath.replaceAll('\\', '/').trim();
    final fullPath = p.normalize(p.join(rootPath, normalizedRelative));
    final normalizedRoot = p.normalize(rootPath);
    final relative = p.relative(fullPath, from: normalizedRoot);
    if (!allowRoot && relative == '.') {
      throw ArgumentError('禁止删除、移动或替换工作区根目录');
    }

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
    _realRoot ??= Directory(rootPath).existsSync()
        ? Directory(rootPath).resolveSymbolicLinksSync()
        : p.normalize(rootPath);
    bool outsideRoot(String path) {
      try {
        final relative = p.relative(path, from: _realRoot!);
        return p.isAbsolute(relative) ||
            relative == '..' ||
            relative.startsWith('..${p.separator}');
      } catch (_) {
        // Different Windows volumes and unresolvable paths are outside by
        // default; never turn a failed containment check into an allow.
        return true;
      }
    }

    var probe = fullPath;
    while (true) {
      // followLinks:false is important here: a dangling link reports notFound
      // when followed, which used to make us skip over the link and validate
      // only its in-workspace parent before a later write created an outside
      // target through it.
      if (FileSystemEntity.typeSync(probe, followLinks: false) ==
          FileSystemEntityType.link) {
        final String realLink;
        try {
          realLink = Link(probe).resolveSymbolicLinksSync();
        } catch (_) {
          throw ArgumentError('非法路径访问：无法安全解析符号链接');
        }
        if (outsideRoot(realLink)) {
          throw ArgumentError('非法路径访问：路径经由符号链接超出工作区根目录');
        }
      }

      if (FileSystemEntity.typeSync(probe) != FileSystemEntityType.notFound) {
        break;
      }
      final parent = p.dirname(probe);
      if (parent == probe) return; // 到达文件系统根仍不存在，无链接可解析
      probe = parent;
    }
    final realProbe = Directory(probe).resolveSymbolicLinksSync();
    if (outsideRoot(realProbe)) {
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
    traits: ToolTraits.workspaceRead,
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
      final fs = sandbox.fs;
      if (await fs.kindOf(fullPath) != WorkspaceEntryKind.file) {
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '文件不存在：$path',
        );
      }

      final content = await fs.readText(fullPath);
      recordFile(operation: 'read', path: path, after: content);
      sandbox.rememberRead(fullPath, content);
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
    } on TextFileTooLarge catch (e) {
      return ToolResult.failure(code: ToolCodes.tooLarge, message: '$e');
    } on FormatException catch (e) {
      return ToolResult.failure(code: ToolCodes.invalidFormat, message: '$e');
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
    traits: ToolTraits.workspaceWrite,
    description: '创建新文件或覆写文件。覆写已有文件前必须 read_file；读取后有外部变更时须重读。自动创建父目录。',
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
    final recovery = await sandbox.prepareForWrite();
    if (recovery != null) {
      lastMetadata = {'operation': 'patch_recovery', ...?recovery.data};
      return recovery;
    }
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

    final fs = sandbox.fs;
    // committed 之前抛错说明还没碰过磁盘（effect=none）；
    // 之后抛错必须按“可能已经写进去了”上报，让模型先读再决定是否重试。
    var committed = false;
    try {
      final exists = await fs.kindOf(fullPath) == WorkspaceEntryKind.file;
      final before = exists ? await fs.readText(fullPath) : '';
      if (exists) {
        final conflict = sandbox.checkFresh(fullPath, before);
        if (conflict != null) return conflict;
      }

      // 自动创建父目录
      await fs.writeText(fullPath, content);
      committed = true;
      sandbox.rememberRead(fullPath, content);
      recordFile(
          operation: exists ? 'write' : 'create',
          path: path,
          before: before,
          after: content);
      return ToolResult.success(
        message: '成功写入文件：$path (${content.length} 字符)',
        data: {
          'path': path,
          'chars': content.length,
          'created': !exists,
        },
        effect: ToolEffect.applied,
      );
    } on TextFileTooLarge catch (e) {
      return ToolResult.failure(code: ToolCodes.tooLarge, message: '$e');
    } on FormatException catch (e) {
      return ToolResult.failure(code: ToolCodes.invalidFormat, message: '$e');
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
    traits: ToolTraits.workspaceWrite,
    description: '先 read_file，再精确替换唯一匹配的文本。文件在读取后有变化时拒绝编辑，须重读。',
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
    final recovery = await sandbox.prepareForWrite();
    if (recovery != null) {
      lastMetadata = {'operation': 'patch_recovery', ...?recovery.data};
      return recovery;
    }
    final path = arguments['path'];
    final target = arguments['targetContent'];
    final replacement = arguments['replacementContent'];
    if (path is! String || path.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'path 必须是非空字符串',
      );
    }
    if (target is! String || target.isEmpty || replacement is! String) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'targetContent 必须是非空字符串，replacementContent 必须是字符串',
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

    final fs = sandbox.fs;
    var committed = false;
    try {
      if (await fs.kindOf(fullPath) != WorkspaceEntryKind.file) {
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '编辑失败：文件不存在 $path',
        );
      }

      final content = await fs.readText(fullPath);
      final conflict = sandbox.checkFresh(fullPath, content);
      if (conflict != null) return conflict;
      final firstMatch = content.indexOf(target);
      if (firstMatch < 0) {
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '编辑失败：未在文件中找到指定的 targetContent 匹配块，'
              '请重新读取文件核对内容。',
        );
      }

      // Detect overlapping matches too (for example 'aa' in 'aaa').
      if (content.indexOf(target, firstMatch + 1) >= 0) {
        return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: 'targetContent 匹配不唯一，请提供更多上下文后重试',
        );
      }
      final newContent = content.replaceFirst(target, replacement);
      await fs.writeText(fullPath, newContent);
      committed = true;
      sandbox.rememberRead(fullPath, newContent);
      recordFile(
          operation: 'edit', path: path, before: content, after: newContent);
      return ToolResult.success(
        message: '成功修改文件：$path',
        data: {'path': path, 'chars': newContent.length},
        effect: ToolEffect.applied,
      );
    } on TextFileTooLarge catch (e) {
      return ToolResult.failure(code: ToolCodes.tooLarge, message: '$e');
    } on FormatException catch (e) {
      return ToolResult.failure(code: ToolCodes.invalidFormat, message: '$e');
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
    traits: ToolTraits.workspaceRead,
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
      final fs = sandbox.fs;
      final displayPath = relativePath.isEmpty ? '.' : relativePath;

      if (await fs.kindOf(fullPath) != WorkspaceEntryKind.directory) {
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
      await for (final entity in fs.list(fullPath, recursive: recursive)) {
        final rel = sandbox.toRelative(entity.path);
        final isDir = entity.isDirectory;
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
    traits: ToolTraits(
      readOnly: true,
      scopes: {ToolEffectScope.workspace},
      fileOperation: true,
    ),
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
        'pathPrefix': {'type': 'string', 'description': '可选的相对路径前缀，限制搜索范围'},
        'offset': {'type': 'integer', 'description': '跳过前 N 条命中，用于分页'},
        'limit': {'type': 'integer', 'description': '返回条数上限，默认 50，最大 100'},
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
    final pathPrefix = arguments['pathPrefix']?.toString();
    final offset = (arguments['offset'] as num?)?.toInt() ?? 0;
    final limit = ((arguments['limit'] as num?)?.toInt() ?? 50).clamp(1, 100);
    try {
      final fs = sandbox.fs;

      if (await fs.kindOf(sandbox.rootPath) != WorkspaceEntryKind.directory) {
        recordMetadata({
          'operation': 'search',
          'path': pathPrefix ?? '.',
          'query': query,
          'exists': false,
        });
        return ToolResult.failure(
          code: ToolCodes.notFound,
          message: '工作区目录不存在',
        );
      }

      final results = <String>[];
      var skipped = 0;
      Future<void> walk(String current) async {
        if (results.length >= limit) return;
        await for (final entity in fs.list(current)) {
          if (results.length >= limit) return;
          if (entity.isDirectory) {
            final name = p.basename(entity.path);
            if (const {
              '.git',
              '.dart_tool',
              'build',
              'node_modules',
              'dist',
              '.idea',
              '.vscode',
              '.nexus',
              '.gradle',
              '.venv',
              '__pycache__',
              'target',
            }.contains(name)) {
              continue;
            }
            await walk(entity.path);
            continue;
          }
          if (!entity.isFile) continue;
          if (BoundedTextReader.binaryExtensions
              .contains(p.extension(entity.path).toLowerCase())) {
            continue;
          }
          if (ext != null && !entity.path.endsWith(ext)) continue;
          final rel = sandbox.toRelative(entity.path);
          if (pathPrefix != null &&
              pathPrefix.isNotEmpty &&
              !rel.startsWith(pathPrefix.replaceAll('\\', '/'))) {
            continue;
          }
          try {
            final content = await fs.readText(entity.path,
                maxBytes: BoundedTextReader.maxSearchBytes);
            if (!content.contains(query)) continue;
            final lines = const LineSplitter().convert(content);
            for (var i = 0; i < lines.length; i++) {
              if (!lines[i].contains(query)) continue;
              if (skipped < offset) {
                skipped++;
                continue;
              }
              final line = lines[i].trim();
              final preview =
                  line.length > 500 ? '${line.substring(0, 500)}…' : line;
              results.add('$rel:${i + 1}: $preview');
              if (results.length >= limit) return;
            }
          } catch (_) {
            // 单个文件读不了（二进制、编码异常、权限不足）时跳过它，不能让整个
            // 搜索失败 —— 搜索结果本来就是「尽力而为」的检索辅助。
            // 代价：结果里不会出现这个文件，调用方无法区分「没有匹配」与
            // 「这个文件没被搜」。若将来出现「搜不到明明存在的字符串」类问题，
            // 这里是第一嫌疑点。
          }
        }
      }

      await walk(sandbox.rootPath);

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
        'truncated': results.length >= limit,
        'offset': offset,
        'limit': limit,
        if (pathPrefix != null) 'pathPrefix': pathPrefix,
      });
      return ToolResult.text(results.join('\n'), extra: {
        'query': query,
        'matchCount': results.length,
        'truncated': results.length >= limit,
        'offset': offset,
        'limit': limit,
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
    traits: ToolTraits.workspaceWrite,
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
    final recovery = await sandbox.prepareForWrite();
    if (recovery != null) {
      lastMetadata = {'operation': 'patch_recovery', ...?recovery.data};
      return recovery;
    }
    final path = arguments['path'];
    if (path is! String || path.isEmpty) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: 'path 必须是非空字符串',
      );
    }
    final String fullPath;
    try {
      fullPath = sandbox.resolvePath(path, allowRoot: false);
    } on ArgumentError catch (e) {
      return ToolResult.failure(
        code: ToolCodes.sandboxViolation,
        message: '路径越出工作区：${e.message}',
      );
    }

    final fs = sandbox.fs;
    var committed = false;
    try {
      final kind = await fs.kindOf(fullPath);
      if (kind == WorkspaceEntryKind.file) {
        // 二进制文件读不成字符串也必须能删，否则删除会被前置读取卡死。
        String? before;
        try {
          before = await fs.readText(fullPath);
        } catch (_) {
          before = null;
        }
        await fs.deleteFile(fullPath);
        committed = true;
        recordFile(operation: 'delete', path: path, before: before ?? '');
        return ToolResult.success(
          message: '成功删除文件：$path',
          data: {'path': path, 'kind': 'file', 'recoverable': false},
          effect: ToolEffect.applied,
        );
      } else if (kind == WorkspaceEntryKind.directory) {
        await fs.deleteEmptyDirectory(fullPath);
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
    traits: ToolTraits(
      readOnly: false,
      scopes: {ToolEffectScope.workspace},
      pathArguments: ['path', 'newPath'],
      fileOperation: true,
    ),
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
    final recovery = await sandbox.prepareForWrite();
    if (recovery != null) {
      lastMetadata = {'operation': 'patch_recovery', ...?recovery.data};
      return recovery;
    }
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
      sourcePath = sandbox.resolvePath(oldPath, allowRoot: false);
      targetPath = sandbox.resolvePath(newPath, allowRoot: false);
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

      final fs = sandbox.fs;
      final sourceKind = await fs.kindOf(sourcePath);
      if (sourceKind == WorkspaceEntryKind.notFound) {
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
      if (await fs.kindOf(targetPath) != WorkspaceEntryKind.notFound) {
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

      final targetParent = p.dirname(targetPath);
      if (await fs.kindOf(targetParent) != WorkspaceEntryKind.directory) {
        await fs.ensureDirectory(targetParent);
        touched = true;
      }

      String? content;
      if (sourceKind == WorkspaceEntryKind.file) {
        try {
          content = await fs.readText(sourcePath);
        } catch (_) {
          content = null;
        }
      }
      await fs.rename(sourcePath, targetPath);
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
