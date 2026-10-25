import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/tools/repo_map_tool.dart';
import 'package:mobile_agent/infrastructure/tools/source_symbol_index.dart';
import 'package:mobile_agent/infrastructure/tools/workspace_tools.dart';

void main() {
  late Directory root;
  setUp(() async =>
      root = await Directory.systemTemp.createTemp('repo-languages-'));
  tearDown(() => root.delete(recursive: true));
  Future<void> write(String path, String content) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  test('Python literals/comments do not create phantom declarations or calls',
      () {
    final parsed = parseSourceSymbols('''
# def fake(): imaginary()
doc = """class Ghost: phantom()"""
class Service:
    async def fetch(self):
        return helper()
def helper():
    return 'def quoted(): phantom()'
''', 'python');
    expect((parsed['symbols'] as List).map((s) => s['name']),
        ['Service', 'fetch', 'helper']);
    expect((parsed['references'] as List).map((s) => s['name']), ['helper']);
    expect((parsed['symbols'] as List)[1]['line'], 4);
  });
  test(
      'JS regex/template/comment text is excluded and TS declarations retained',
      () {
    final parsed = parseSourceSymbols(r'''
// function Fake() {}
const pattern = /function Ghost\(\)/;
const text = `function Phantom() { bogus(); }`;
interface Response { value: string }
type Alias = Response;
export function real() { return helper(); }
function* helper() { yield 1; }
''', 'typescript');
    final names = (parsed['symbols'] as List).map((s) => s['name']).toList();
    expect(names, ['pattern', 'text', 'Response', 'Alias', 'real', 'helper']);
    expect((parsed['references'] as List).map((s) => s['name']), ['helper']);
  });
  test(
      'mixed map ranks matching candidates and preserves ambiguity across files',
      () async {
    await write('a.ts', 'export function shared() {}');
    await write(
        'b.js', 'function shared() {}\nfunction caller() { shared(); }');
    await write('c.py', 'def shared():\n    return 1\n');
    await write('d.dart', 'void dartFn() {}\nvoid main() { dartFn(); }');
    final map = RepoMapTool(
        sandbox: WorkspaceSandbox(root.path, requireReadBeforeWrite: true));
    final result = await map.execute({'query': 'shared'});
    expect(result.ok, isTrue);
    expect(result.data!['languages'],
        ['dart', 'javascript', 'python', 'typescript']);
    final refs = result.data!['references'] as List;
    expect(refs.single['ambiguous'], isTrue);
    expect((refs.single['targets'] as List).map((s) => s['path']),
        ['a.ts', 'b.js']);
    expect(refs.single['resolution'], 'name_candidate');
    final dart = await map.execute({'query': 'dartFn'});
    expect((dart.data!['symbols'] as List).single['precision'], 'ast');
    expect((dart.data!['references'] as List).single['name'], 'dartFn');
    await write('a.ts', 'export function changed() {}');
    final refreshed = await map.execute({'query': 'changed'});
    expect((refreshed.data!['symbols'] as List).single['name'], 'changed');
  });
  test('Git selection honors ignored, re-included, and tracked ignored files',
      () async {
    final init =
        await Process.run('git', ['init', '-q'], workingDirectory: root.path);
    expect(init.exitCode, 0);
    await write('tracked.py', 'def tracked(): pass');
    expect(
        (await Process.run('git', ['add', 'tracked.py'],
                workingDirectory: root.path))
            .exitCode,
        0);
    await write('.gitignore', '*.py\n!keep.py\n');
    await write('hidden.py', 'def hidden(): pass');
    await write('keep.py', 'def keep(): pass');
    final result =
        await RepoMapTool(sandbox: WorkspaceSandbox(root.path)).execute({});
    expect(result.data!['ignoreMode'], 'git_standard');
    expect((result.data!['symbols'] as List).map((s) => s['name']),
        ['keep', 'tracked']);
  });
}
