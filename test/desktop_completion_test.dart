import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_agent/application/bounded_log_buffer.dart';
import 'package:mobile_agent/application/desktop_diff.dart';
import 'package:mobile_agent/application/desktop_git_service.dart';
import 'package:mobile_agent/application/desktop_workflow_service.dart';
import 'package:mobile_agent/application/desktop_worktree_service.dart';
import 'package:mobile_agent/application/session_checkpoint_service.dart';
import 'package:mobile_agent/application/session_operation_guard.dart';
import 'package:mobile_agent/domain/session_operation_guard.dart' as domain;
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('100k log lines have bounded display memory', () {
    final log = BoundedLogBuffer();
    for (var i = 0; i < 100000; i += 1000) {
      log.append(List.generate(1000, (j) => '${i + j} output\n').join());
    }
    expect(log.text.length, lessThanOrEqualTo(log.maxCharacters));
    expect(log.lines.length, lessThanOrEqualTo(log.maxLines));
    expect(log.text, contains('99999 output'));
    expect(log.droppedCharacters, greaterThan(0));
  });
  test('hunks carry source line numbers and separate complete patches', () {
    final diff = DesktopDiff.parse(
        '--- a/a.txt\n+++ b/a.txt\n@@ -7,2 +7,3 @@\n context\n-old\n+new\n+extra\n@@ -40 +41 @@\n-end\n+tail\n');
    expect(diff.hunks, hasLength(2));
    expect(diff.hunks.first.lines.map((l) => l.oldLine), [7, 8, null, null]);
    expect(diff.hunks.first.lines.map((l) => l.newLine), [7, null, 8, 9]);
    expect(diff.hunks.last.lines.first.oldLine, 40);
    expect(diff.hunks.first.patch, isNot(contains('tail')));
  });
  test('restore lock rejects execution and releases after failure', () async {
    const service = SessionCheckpointService();
    final cp = SessionCheckpoint(
        id: 'cp',
        conversationId: 'c',
        workspacePath: '',
        messageCount: 0,
        createdAt: DateTime(2026),
        turn: 1);
    await expectLater(
        service.withRestoreLock(cp,
            isRunning: () async => true, action: () async => 0),
        throwsStateError);
    expect(SessionOperationGuard.restoring, false);
    await service.withRestoreLock(cp,
        isRunning: () async => false,
        action: () async {
          expect(SessionOperationGuard.assertCanRun, throwsStateError);
          expect(domain.SessionOperationGuard.assertCanRun, throwsStateError);
          expect(domain.SessionOperationGuard.restoring, isTrue);
        });
    expect(SessionOperationGuard.assertCanRun, returnsNormally);
    expect(domain.SessionOperationGuard.assertCanRun, returnsNormally);
  });
  test(
      'concurrent checkpoint writes retain all records and corrupt files stay intact',
      () async {
    final root = await Directory.systemTemp.createTemp('nexus-cp-serial');
    addTearDown(() => root.delete(recursive: true));
    final store = SessionCheckpointStore(overrideDirectory: root);
    await Future.wait(List.generate(
        20,
        (i) => store.append(SessionCheckpoint(
            id: '$i',
            conversationId: 'conversation',
            workspacePath: '',
            messageCount: i,
            createdAt: DateTime(2026),
            turn: i + 1))));
    expect(await store.listFor('conversation'), hasLength(20));
    final file = File('${root.path}/checkpoints/conversation.json');
    await file.writeAsString('{broken');
    await expectLater(store.listFor('conversation'), throwsFormatException);
    expect(await file.readAsString(), '{broken');
  });
  test('workflows validate imports and preserve custom instructions', () async {
    final service = DesktopWorkflowService();
    const item = DesktopWorkflow(id: 'one', name: '审查', prompt: '只读检查项目');
    final parsed = service.parse(service.export([item]));
    await service.save(parsed);
    expect((await service.custom()).single.prompt, item.prompt);
    expect(() => service.parse('{"version":2,"workflows":[]}'),
        throwsFormatException);
  });
  test('real Git stages and reverts only the selected hunk', () async {
    final directory = await Directory.systemTemp.createTemp('nexus-hunks');
    addTearDown(() => directory.delete(recursive: true));
    Future<void> git(List<String> args) async {
      final result =
          await Process.run('git', args, workingDirectory: directory.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    await git(['init', '-q']);
    await git(['config', 'user.email', 'test@example.invalid']);
    await git(['config', 'user.name', 'Test']);
    final file = File('${directory.path}/sample.txt');
    final original = List.generate(50, (i) => 'line$i').join('\n');
    await file.writeAsString('$original\n');
    await git(['add', '.']);
    await git(['commit', '-qm', 'base']);
    await file.writeAsString(
        '${original.replaceFirst('line1\n', 'changed1\n').replaceFirst('line45\n', 'changed45\n')}\n');
    const service = DesktopGitService();
    final snapshot = await service.inspect(directory.path);
    final diff =
        DesktopDiff.parse(await service.diff(snapshot, snapshot.files.single));
    expect(diff.hunks, hasLength(2));
    await service.applyPatch(directory.path, diff.hunks.first.patch,
        staged: true);
    final staged = await service.inspect(directory.path);
    final stagedText =
        await service.diff(staged, staged.files.single, staged: true);
    expect(stagedText, contains('changed1'));
    expect(stagedText, isNot(contains('changed45')));
    await service.applyPatch(directory.path, diff.hunks.last.patch,
        reverse: true);
    expect(await file.readAsString(), contains('changed1'));
    expect(await file.readAsString(), isNot(contains('changed45')));
  });
  test(
      'worktree binding does not change project root and survives service recreation',
      () async {
    const service = DesktopWorktreeService();
    await service.bind('c', 'D:/project', 'D:/project/.nexus/worktrees/c');
    final binding = await const DesktopWorktreeService().binding('c');
    expect(binding!.root.replaceAll('\\', '/'), 'D:/project');
    expect(binding.workspace.replaceAll('\\', '/'),
        endsWith('/.nexus/worktrees/c'));
    await service.unbind('c');
    expect(await service.binding('c'), isNull);
  });
  testWidgets(
      'accessible navigation reduces desktop motion even when disableAnimations is false',
      (tester) async {
    late Duration duration;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(accessibleNavigation: true),
            child: Builder(builder: (context) {
              duration = DesktopTheme.motionDuration(
                  context, const Duration(milliseconds: 180));
              return const SizedBox();
            }))));
    expect(duration, Duration.zero);
  });
}
