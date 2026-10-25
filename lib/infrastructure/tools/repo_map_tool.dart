import 'dart:convert';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/models.dart';
import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';
import '../files/workspace_fs.dart';
import '../files/git_index_selection.dart';
import 'tool_registry.dart';
import 'workspace_tools.dart';
import 'source_symbol_index.dart';

/// AST declarations, not a semantic reference resolver. Each request rereads
/// bounded source bytes; only parsing is cached, keyed by content hash.
class RepoMapTool implements AgentTool {
  RepoMapTool({required this.sandbox});
  final WorkspaceSandbox sandbox;
  final _cache = <String, Map<String, dynamic>>{};
  static const ignored = {
    '.git',
    '.dart_tool',
    '.nexus',
    'build',
    'node_modules',
    '.venv',
    'vendor',
    'Pods',
    '.gradle'
  };

  @override
  final manifest = const UnifiedTool(
    name: 'repo_map',
    description:
        '符号地图与候选调用关系：Dart 使用 AST，Python/JavaScript/TypeScript 使用词法索引。按符号名过滤，候选引用不是类型解析，索引不代替 read_file。',
    risk: ToolRisk.safe,
    traits: ToolTraits.workspaceRead,
    parametersSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '相对目录或源文件，默认根目录'},
        'query': {'type': 'string', 'description': '符号名子串，忽略大小写'},
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': 200},
      }
    },
  );

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final path = arguments['path'] ?? '.';
    final query = arguments['query'] ?? '';
    final limit = arguments['limit'] ?? 100;
    if (path is! String ||
        query is! String ||
        limit is! int ||
        limit < 1 ||
        limit > 200) {
      return ToolResult.failure(
          code: ToolCodes.invalidArguments,
          message: 'path/query 必须为字符串，limit 为 1–200 整数');
    }
    try {
      final root = sandbox.resolvePath(path);
      final gitFiles = sandbox.fs is LocalWorkspaceFs
          ? await gitIndexSelection(sandbox.rootPath)
          : null;
      final gitDirectories = <String>{'.'};
      for (final file in gitFiles ?? const <String>{}) {
        var directory = p.posix.dirname(file);
        while (directory != '.' && directory != '/') {
          gitDirectories.add(directory);
          directory = p.posix.dirname(directory);
        }
      }
      final pending = <String>[root];
      final symbols = <Map<String, dynamic>>[];
      final references = <Map<String, dynamic>>[];
      final languages = <String>{};
      final skipped = <String>[];
      var scanned = 0;
      var visited = 0;
      var bytes = 0;
      var truncated = false;
      while (pending.isNotEmpty) {
        if (++visited > 2000 ||
            scanned >= 400 ||
            bytes >= 4 * 1024 * 1024 ||
            symbols.length >= 5000) {
          truncated = true;
          break;
        }
        final next = pending.removeLast();
        final relative = sandbox.toRelative(next);
        sandbox.resolvePath(relative);
        final kind = await sandbox.fs.kindOf(next);
        if (kind == WorkspaceEntryKind.directory) {
          if (gitFiles != null &&
              !gitDirectories.contains(relative.replaceAll('\\', '/'))) {
            continue;
          }
          final children = <String>[];
          await for (final entry in sandbox.fs.list(next)) {
            if (children.length + visited > 2000) {
              truncated = true;
              break;
            }
            if (entry.isLink || ignored.contains(p.basename(entry.path))) {
              continue;
            }
            children.add(entry.path);
          }
          children.sort((a, b) => b.compareTo(a));
          pending.addAll(children);
          continue;
        }
        final language = switch (p.extension(next).toLowerCase()) {
          '.dart' => 'dart',
          '.py' => 'python',
          '.js' || '.mjs' || '.cjs' => 'javascript',
          '.ts' || '.mts' || '.cts' => 'typescript',
          _ => null,
        };
        if (kind != WorkspaceEntryKind.file ||
            language == null ||
            (gitFiles != null &&
                !gitFiles.contains(relative.replaceAll('\\', '/'))) ||
            next.endsWith('.g.dart') ||
            next.endsWith('.freezed.dart')) {
          continue;
        }
        try {
          final source = await sandbox.fs.readText(next, maxBytes: 256 * 1024);
          bytes += utf8.encode(source).length;
          scanned++;
          final hash = sha256.convert(utf8.encode(source)).toString();
          final cacheKey = '$language:$hash';
          final parsed = _cache[cacheKey] ??
              await Isolate.run<Map<String, dynamic>>(() => language == 'dart'
                  ? parseDartSymbols(source)
                  : parseSourceSymbols(source, language));
          _cache[cacheKey] = parsed;
          languages.add(language);
          truncated = truncated || parsed['truncated'] == true;
          if (_cache.length > 128) _cache.remove(_cache.keys.first);
          for (final symbol in parsed['symbols'] as List) {
            final item = symbol as Map<String, dynamic>;
            if (symbols.length >= 5000) {
              truncated = true;
              break;
            }
            symbols.add({
              ...item,
              'path': relative,
              'language': language,
              'precision': parsed['precision'] ?? 'ast',
              'contentHash': hash,
              'parseErrors': parsed['parseErrors']
            });
          }
          for (final reference in parsed['references'] as List? ?? const []) {
            if (references.length >= 20000) {
              truncated = true;
              break;
            }
            references.add({
              ...reference as Map<String, dynamic>,
              'path': relative,
              'language': language
            });
          }
        } catch (_) {
          if (skipped.length < 30) skipped.add(relative);
        }
      }
      final candidates = buildReferenceCandidates(symbols, references);
      final filtered = symbols
          .where((s) =>
              (s['name'] as String).toLowerCase().contains(query.toLowerCase()))
          .toList();
      filtered.sort((a, b) {
        final exactA =
            a['name'].toString().toLowerCase() == query.toLowerCase() ? 1 : 0;
        final exactB =
            b['name'].toString().toLowerCase() == query.toLowerCase() ? 1 : 0;
        if (exactA != exactB) return exactB.compareTo(exactA);
        final rank = (b['candidateReferences'] as int? ?? 0)
            .compareTo(a['candidateReferences'] as int? ?? 0);
        if (rank != 0) return rank;
        final pathOrder = (a['path'] as String).compareTo(b['path'] as String);
        return pathOrder != 0
            ? pathOrder
            : (a['line'] as int).compareTo(b['line'] as int);
      });
      final visibleCandidates = candidates
          .where((r) =>
              (r['name'] as String).toLowerCase().contains(query.toLowerCase()))
          .toList();
      return ToolResult.success(
          message: '已扫描 $scanned 个源文件，找到 ${filtered.length} 个匹配声明',
          data: {
            'symbols': filtered.take(limit).toList(),
            'references': visibleCandidates.take(200).toList(),
            'referencesTruncated':
                visibleCandidates.length > 200 || candidates.length >= 1000,
            'scannedFiles': scanned,
            'ignoreMode':
                gitFiles == null ? 'builtin_fallback' : 'git_standard',
            'truncated': truncated || filtered.length > limit,
            'skippedFiles': skipped,
            'language': languages.length == 1 ? languages.single : 'mixed',
            'languages': languages.toList()..sort(),
            'scope': 'declarations_and_candidate_references',
            'hint': '引用仅按名称匹配，同名目标可能歧义；词法索引不覆盖所有语言语法。使用 read_file 核实当前代码后再编辑。'
          });
    } on ArgumentError {
      return ToolResult.failure(
          code: ToolCodes.sandboxViolation, message: '索引路径越出工作区');
    } catch (_) {
      return ToolResult.failure(
          code: ToolCodes.ioError, message: '无法索引该路径，请检查目录权限');
    }
  }
}

Map<String, dynamic> parseDartSymbols(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final symbols = <Map<String, dynamic>>[];
  final references = <Map<String, dynamic>>[];
  void walk(AstNode node, String? owner) {
    if (node is MethodInvocation && references.length < 2000) {
      references.add({
        'name': node.methodName.name,
        'line': parsed.lineInfo.getLocation(node.offset).lineNumber
      });
    }
    final declaration = switch (node) {
      ClassDeclaration n => (n.namePart.beginToken.lexeme, 'class'),
      EnumDeclaration n => (n.namePart.beginToken.lexeme, 'enum'),
      MixinDeclaration n => (n.name.lexeme, 'mixin'),
      ExtensionDeclaration n => (n.name?.lexeme ?? '<anonymous>', 'extension'),
      FunctionDeclaration n => (n.name.lexeme, 'function'),
      MethodDeclaration n => (n.name.lexeme, 'method'),
      _ => null,
    };
    var childOwner = owner;
    if (declaration != null) {
      symbols.add({
        'name': declaration.$1,
        'kind': declaration.$2,
        'line': parsed.lineInfo.getLocation(node.offset).lineNumber,
        'endLine': parsed.lineInfo.getLocation(node.end).lineNumber,
        if (owner != null) 'owner': owner
      });
      childOwner = owner == null ? declaration.$1 : '$owner.${declaration.$1}';
    }
    for (final child in node.childEntities.whereType<AstNode>()) {
      walk(child, childOwner);
    }
  }

  walk(parsed.unit, null);
  return {
    'symbols': symbols,
    'references': references,
    'parseErrors': parsed.errors.length,
    'precision': 'ast',
    'truncated': references.length >= 2000
  };
}
