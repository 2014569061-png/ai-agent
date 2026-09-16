import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mobile_agent/application/artifact_service.dart';
import 'package:mobile_agent/application/change_review.dart';
import 'package:mobile_agent/application/change_set_service.dart';
import 'package:mobile_agent/application/conversation_fork_service.dart';
import 'package:mobile_agent/application/development_execution_service.dart';
import 'package:mobile_agent/application/development_verification.dart';
import 'package:mobile_agent/application/git_service.dart';
import 'package:mobile_agent/application/preview_service.dart';
import 'package:mobile_agent/application/project_kind.dart';
import 'package:mobile_agent/application/remote_execution_probe.dart';
import 'package:mobile_agent/application/verification_repair_service.dart';
import 'package:mobile_agent/application/workspace_file_editor.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/tools/command_tool.dart';
import 'package:drift/native.dart';

void main() {
  test('failed verification becomes a repair prompt with attempt cap', () {
    const plan = DevelopmentVerificationPlan(
      project: ProjectKindDetection(
        kind: ProjectKind.unknown,
        confidence: 0,
        signals: [],
      ),
      steps: [
        VerificationStep(
          id: 'test',
          title: '运行测试',
          command: 'python -m pytest',
          status: VerificationStepStatus.failed,
          output: 'FAILED tests/test_login.py',
          exitCode: 1,
        ),
      ],
    );
    final request = const VerificationRepairService().fromFailedPlan(
      plan: plan,
      workspacePath: '/tmp/app',
      attempt: 2,
    );
    expect(request, isNotNull);
    expect(request!.reason, 'test_failed');
    expect(const VerificationRepairService().canAutoRetry(request), isFalse);
    expect(
      const VerificationRepairService().promptFor(request),
      contains('根据这次错误继续修复'),
    );
  });

  test('git porcelain parser keeps spaced paths', () {
    final entries = GitService().parsePorcelain(
      'M  src/我的 文件.dart\x00?? new file.txt\x00',
    );
    expect(entries, hasLength(2));
    expect(entries.first.path, 'src/我的 文件.dart');
    expect(entries.first.staged, isTrue);
  });

  test('remote probe returns handshake and idempotent job status', () async {
    const probe = RemoteExecutionProbe();
    final handshake = await probe.handshake();
    expect(handshake.protocolVersion, isNotEmpty);
    final status = probe.statusFor(
      runId: 'run-1',
      jobId: 'job-1',
      status: 'running',
    );
    expect(status.runId, 'run-1');
    expect(status.jobId, 'job-1');
  });

  test('conversation fork copies context without replaying later messages', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    await db.saveConversation(Conversation(
      id: 'c1',
      title: '原会话',
      mode: 'chat',
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now,
    ));
    await db.saveMessage(Message(
      id: 'm1',
      conversationId: 'c1',
      role: 'user',
      content: 'hello',
      createdAt: now,
    ));
    await db.saveMessage(Message(
      id: 'm2',
      conversationId: 'c1',
      role: 'assistant',
      content: 'world',
      createdAt: now.add(const Duration(seconds: 1)),
    ));
    await db.saveMessage(Message(
      id: 'm3',
      conversationId: 'c1',
      role: 'tool',
      content: 'should not replay',
      createdAt: now.add(const Duration(seconds: 2)),
    ));
    final branch = await const ConversationForkService().fork(
      db: db,
      sourceConversationId: 'c1',
      forkMessageId: 'm1',
    );
    final copied = await db.messagesFor(branch.id);
    expect(copied, hasLength(1));
    expect(copied.single.content, 'hello');
    expect(branch.tagsJson, contains('parent:c1'));
  });

  test('repair follow-up enqueue is idempotent on requestId', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = DevelopmentExecutionService(db: db);
    const request = DevelopmentTaskRequest(
      prompt: '根据这次错误继续修复',
      conversationId: 'c1',
      taskType: 'bug_fix',
      sourceType: 'verification_repair',
      requestId: 'repair-1',
    );
    final first = await service.enqueue(request);
    final second = await service.enqueue(request);
    expect(first.taskId, second.taskId);
    expect(await db.allTasks(), hasLength(1));
  });

  test('artifact records persist by project and round-trip inspection',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp('nexus-art');
    addTearDown(() => dir.delete(recursive: true));
    PathProviderPlatform.instance = _TempPathProvider(dir.path);
    await File(p.join(dir.path, 'app.apk')).writeAsBytes([0x50, 0x4b, 0x03, 0x04]);
    final artifact = await const ArtifactService().record(
      db: db,
      projectId: 'p1',
      taskId: 't1',
      runId: 'r1',
      workspacePath: dir.path,
      inspection: const ArtifactInspection(
        relativePath: 'app.apk',
        exists: true,
        bytes: 4,
        sha256: 'hash',
      ),
    );
    final listed = await const ArtifactService().list(db, projectId: 'p1');
    expect(listed.single.id, artifact.id);
    expect(listed.single.kind, 'apk');
  });

  test('preview binds loopback and refuses a second project session', () async {
    final preview = PreviewService(
      terminal: _StubTerminal(),
      waitForPort: (_) async => true,
      isPortBusy: (_) async => false,
    );
    final first = await preview.start(
      projectId: 'p1',
      workspacePath: '.',
      command: 'python -m http.server 8765',
    );
    expect(first.host, '127.0.0.1');
    expect(first.url, contains('127.0.0.1'));
    expect(
      () => preview.start(
        projectId: 'p2',
        workspacePath: '.',
        command: 'python -m http.server 8766',
      ),
      throwsStateError,
    );
    await preview.stop();
  });

  test('editor refuses save when the on-disk hash changed', () async {
    final dir = await Directory.systemTemp.createTemp('nexus-edit');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'a.txt'));
    await file.writeAsString('one\n');
    final editor = const WorkspaceFileEditor();
    final buffer = await editor.open(
      workspacePath: dir.path,
      relativePath: 'a.txt',
    );
    await file.writeAsString('two\n');
    expect(
      () => editor.save(
        workspacePath: dir.path,
        original: buffer,
        content: 'three\n',
      ),
      throwsA(isA<ConcurrentEditException>()),
    );
  });

  test('changeset rollback refuses later human edits', () async {
    final dir = await Directory.systemTemp.createTemp('nexus-cs');
    addTearDown(() => dir.delete(recursive: true));
    PathProviderPlatform.instance = _TempPathProvider(dir.path);
    await File(p.join(dir.path, 'a.txt')).writeAsString('after');
    final set = await const ChangeSetService().capture(
      projectId: 'p1',
      taskId: 't1',
      workspacePath: dir.path,
      review: const ChangeReview(
        files: [
          FileChangeSummary(
            path: 'a.txt',
            operation: 'edit',
            linesAdded: 1,
            linesRemoved: 0,
          ),
        ],
        mark: ChangeVerificationMark.passed,
      ),
    );
    final conflicts = await const ChangeSetService().rollback(
      workspacePath: dir.path,
      changeSet: set,
      currentHashes: {set.files.single.relativePath: 'different'},
    );
    expect(conflicts.single.reason, contains('人工后续修改'));
  });
}

class _StubTerminal extends TerminalCommandService {
  _StubTerminal() : super(workspacePath: '.');

  @override
  Future<TerminalJobHandle> startJob({
    required String command,
    String? workingDirectory,
    String? taskId,
    String? runId,
    Duration timeout = TerminalCommandService.defaultTimeout,
  }) async {
    return const TerminalJobHandle(jobId: 'job-preview');
  }

  @override
  Future<bool> cancelJob(String jobId) async => true;
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
