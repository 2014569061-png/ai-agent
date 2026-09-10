import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/domain/tool_result.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';

void main() {
  late Directory tempDir;
  late WorkspaceSandbox sandbox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('workspace_test_');
    sandbox = WorkspaceSandbox(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('WorkspaceSandbox 沙盒安全测试', () {
    test('允许解析正常相对路径', () {
      final resolved = sandbox.resolvePath('src/main.js');
      expect(resolved.startsWith(tempDir.path), isTrue);
    });

    test('拦截 .. 路径穿越攻击', () {
      expect(
        () => sandbox.resolvePath('../../secret.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('拦截相邻目录的根路径前缀碰撞', () {
      expect(
        () => sandbox.resolvePath(
            '../${tempDir.path.split(Platform.pathSeparator).last}2/secret.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('WorkspaceTools 文件读写测试', () {
    test('write_file 创建新文件并自动创建父目录', () async {
      final writeTool = WriteFileTool(sandbox: sandbox);
      final result = await writeTool.execute({
        'path': 'web/index.html',
        'content': '<h1>Hello World</h1>',
      });
      expect(result.ok, isTrue);
      expect(result.message, contains('成功写入文件'));
      expect(result.effect, ToolEffect.applied);
      expect(result.data?['path'], 'web/index.html');

      final file = File('${tempDir.path}/web/index.html');
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), '<h1>Hello World</h1>');
    });

    test('read_file 支持行切片读取', () async {
      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('Line 1\nLine 2\nLine 3\nLine 4');

      final readTool = ReadFileTool(sandbox: sandbox);
      final fullResult = await readTool.execute({'path': 'test.txt'});
      expect(fullResult.ok, isTrue);
      expect(fullResult.data?['text'], 'Line 1\nLine 2\nLine 3\nLine 4');

      final sliceResult = await readTool.execute({
        'path': 'test.txt',
        'startLine': 2,
        'endLine': 3,
      });
      expect(sliceResult.ok, isTrue);
      expect(sliceResult.data?['text'], '2: Line 2\n3: Line 3');
    });

    test('edit_file 精确局部代码替换', () async {
      final file = File('${tempDir.path}/app.js');
      await file
          .writeAsString('const a = 10;\nconst b = 20;\nconsole.log(a + b);');

      final editTool = EditFileTool(sandbox: sandbox);
      final result = await editTool.execute({
        'path': 'app.js',
        'targetContent': 'const b = 20;',
        'replacementContent': 'const b = 30;',
      });
      expect(result.ok, isTrue);
      expect(result.message, contains('成功修改文件'));
      expect(result.effect, ToolEffect.applied);

      final newContent = await file.readAsString();
      expect(newContent, 'const a = 10;\nconst b = 30;\nconsole.log(a + b);');
    });

    test('list_directory 扫描文件树', () async {
      await File('${tempDir.path}/index.html').writeAsString('html');
      await Directory('${tempDir.path}/css').create();
      await File('${tempDir.path}/css/style.css').writeAsString('css');

      final listTool = ListDirectoryTool(sandbox: sandbox);
      final result = await listTool.execute({'recursive': true});
      expect(result.ok, isTrue);
      expect(result.data?['text'], contains('index.html'));
      expect(result.data?['text'], contains('style.css'));
    });

    test('search_files 全文关键字检索', () async {
      await File('${tempDir.path}/main.dart')
          .writeAsString('void main() {\n  print("NEXUS AGENT");\n}');
      await File('${tempDir.path}/other.dart').writeAsString('// nothing here');

      final searchTool = SearchFilesTool(sandbox: sandbox);
      final result = await searchTool.execute({'query': 'NEXUS AGENT'});
      expect(result.ok, isTrue);
      expect(
          result.data?['text'], contains('main.dart:2: print("NEXUS AGENT");'));
      expect(searchTool.lastMetadata['operation'], 'search');
      expect(searchTool.lastMetadata['matchCount'], 1);
    });

    test('list_directory and move_file expose file-operation metadata',
        () async {
      await Directory('${tempDir.path}/src').create();
      final source = File('${tempDir.path}/src/main.dart');
      await source.writeAsString('void main() {}\n');

      final listTool = ListDirectoryTool(sandbox: sandbox);
      await listTool.execute({'path': 'src'});
      expect(listTool.lastMetadata['operation'], 'list');
      expect(listTool.lastMetadata['path'], 'src');
      expect(listTool.lastMetadata['entryCount'], 1);

      final moveTool = MoveFileTool(sandbox: sandbox);
      expect(moveTool.manifest.risk, ToolRisk.requiresConfirmation);
      final result = await moveTool.execute({
        'path': 'src/main.dart',
        'newPath': 'lib/main.dart',
      });
      expect(result.ok, isTrue);
      expect(result.message, contains('->'));
      expect(result.effect, ToolEffect.applied);
      expect(await source.exists(), isFalse);
      final target = File('${tempDir.path}/lib/main.dart');
      expect(await target.readAsString(), 'void main() {}\n');
      expect(moveTool.lastMetadata['operation'], 'move');
      expect(moveTool.lastMetadata['oldPath'], 'src/main.dart');
      expect(moveTool.lastMetadata['path'], 'lib/main.dart');
      expect(moveTool.lastMetadata['moved'], isTrue);
    });

    test('delete_file 删除文件', () async {
      final file = File('${tempDir.path}/temp.txt');
      await file.writeAsString('temp');

      final deleteTool = DeleteFileTool(sandbox: sandbox);
      expect(deleteTool.manifest.risk, ToolRisk.dangerous);

      final result = await deleteTool.execute({'path': 'temp.txt'});
      expect(result.ok, isTrue);
      expect(result.message, contains('成功删除文件'));
      expect(result.effect, ToolEffect.applied);
      expect(await file.exists(), isFalse);
    });

    test('delete_file 删除不存在的文件返回 notFound 且无副作用', () async {
      final deleteTool = DeleteFileTool(sandbox: sandbox);

      final result = await deleteTool.execute({'path': 'missing.txt'});

      expect(result.ok, isFalse);
      expect(result.code, ToolCodes.notFound);
      expect(result.effect, ToolEffect.none);
    });

    test('文件工具拒绝越出工作区的路径', () async {
      final readTool = ReadFileTool(sandbox: sandbox);

      final result = await readTool.execute({'path': '../outside.txt'});

      expect(result.ok, isFalse);
      expect(result.code, ToolCodes.sandboxViolation);
    });
  });
}
