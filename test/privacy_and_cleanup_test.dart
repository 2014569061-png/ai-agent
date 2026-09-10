import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_agent/application/log_service.dart';
import 'package:mobile_agent/application/run_event_tracker.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';
import 'package:mobile_agent/infrastructure/files/vault_exporter_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('sensitive tool event and log persistence never keep raw payloads',
      () async {
    final tracker = RunEventTracker(database: db, runId: 'run-sensitive');
    final handle = await tracker.start(
      type: 'tool_call',
      name: 'terminal',
      inputSummary: jsonEncode({'text': '验证码-SECRET-123'}),
      metadata: {
        'effect': 'applied',
        'toolCode': 'OK',
        'result': '验证码-SECRET-123',
      },
    );
    await tracker.finish(
      handle,
      status: 'success',
      outputSummary: '验证码-SECRET-123',
      metadata: {
        'effect': 'applied',
        'toolCode': 'OK',
        'result': '验证码-SECRET-123',
      },
    );
    await tracker.flush();

    final event = (await db.eventsForRun('run-sensitive')).single;
    expect(event.inputSummary, isNot(contains('SECRET-123')));
    expect(event.outputSummary, isNot(contains('SECRET-123')));
    expect(event.metadataJson, isNot(contains('SECRET-123')));
    expect(event.metadataJson, contains('"effect":"applied"'));
    expect(event.metadataJson, contains('"toolCode":"OK"'));

    final logs = LogService(Future.value(db));
    await logs.info(
      '工具执行完成',
      runId: 'run-sensitive',
      category: 'tool',
      detail: {
        'tool': 'terminal',
        'arguments': {'text': '验证码-SECRET-123'},
        'result': '验证码-SECRET-123',
      },
    );
    await logs.flush();
    final rows = await db.recentLogRecords(runId: 'run-sensitive');
    expect(rows, hasLength(1));
    expect(rows.single.detailJson, isNot(contains('SECRET-123')));
  });

  test(
      'vault export redacts sensitive messages and deleting a conversation cascades',
      () async {
    final now = DateTime.now();
    await db.saveConversation(Conversation(
      id: 'conversation-private',
      title: 'private',
      agentId: null,
      isPinned: false,
      isFavorite: false,
      tagsJson: '[]',
      createdAt: now,
      updatedAt: now,
    ));
    await db.insertMessage(MessagesCompanion.insert(
      id: 'assistant-call',
      conversationId: 'conversation-private',
      role: 'assistant',
      content: '',
      toolCallsJson: Value(jsonEncode([
        {
          'id': 'call-private',
          'name': 'terminal',
          'arguments': {'text': 'SECRET-123'},
        }
      ])),
      createdAt: now,
    ));
    await db.insertMessage(MessagesCompanion.insert(
      id: 'tool-result',
      conversationId: 'conversation-private',
      role: 'tool',
      content: 'SECRET-123',
      toolCallId: const Value('call-private'),
      createdAt: now,
    ));
    await db.insertRunRecord(RunRecordsCompanion.insert(
      runId: 'run-private',
      conversationId: 'conversation-private',
      startedAt: now,
    ));
    await db.insertRunEvent(RunEventsCompanion.insert(
      eventId: 'event-private',
      runId: 'run-private',
      sequenceNo: 1,
      type: 'tool_call',
      status: 'success',
      name: 'terminal',
      startedAt: now,
      inputSummary: const Value('SECRET-123'),
      outputSummary: const Value('SECRET-123'),
    ));
    await db.insertLogRecord(LogRecordsCompanion.insert(
      logId: 'log-private',
      runId: const Value('run-private'),
      level: 'info',
      category: 'tool',
      message: 'private',
      detailJson: const Value('{"result":"SECRET-123"}'),
      createdAt: now,
    ));
    await db.insertAuditLog(AuditLogsCompanion.insert(
      id: 'audit-private',
      conversationId: const Value('conversation-private'),
      type: 'tool',
      detail: 'SECRET-123',
      createdAt: now,
    ));

    final exported = await buildVaultJson(db);
    final encoded = jsonEncode(exported);
    expect(encoded, isNot(contains('SECRET-123')));
    expect(encoded, contains('[敏感工具结果已脱敏]'));

    await db.deleteConversation('conversation-private');
    expect(await db.findConversation('conversation-private'), isNull);
    expect(await db.messagesFor('conversation-private'), isEmpty);
    expect(await db.findRunRecord('run-private'), isNull);
    expect(await db.eventsForRun('run-private'), isEmpty);
    expect(await db.recentLogRecords(runId: 'run-private'), isEmpty);
    expect(
        (await db.recentAuditLogs()).where((row) => row.id == 'audit-private'),
        isEmpty);
  });

  test('deleting a task cascades collaboration records', () async {
    final now = DateTime.now();
    await db.saveTask(Task(
      id: 'task-private',
      conversationId: 'conversation-private',
      type: 'development:code_review',
      status: 'completed',
      requestJson: '{}',
      progressJson: '{}',
      resumeCount: 0,
      createdAt: now,
      updatedAt: now,
    ));
    await db.saveCollaborationRun(CollaborationRun(
      id: 'collab-private',
      taskId: 'task-private',
      mode: 'parallel',
      status: 'completed',
      budgetTokens: 100,
      consumedTokens: 10,
      maxAgents: 1,
      maxRounds: 1,
      currentRound: 1,
      planJson: '{}',
      resultJson: null,
      error: null,
      createdAt: now,
      updatedAt: now,
    ));
    await db.saveCollaborationAgentRun(CollaborationAgentRun(
      id: 'agent-private',
      collaborationRunId: 'collab-private',
      role: 'reviewer',
      agentProfileId: null,
      status: 'completed',
      round: 1,
      contextManifest: '[]',
      allowedTools: '[]',
      inputDigest: 'digest',
      outputSummary: 'secret',
      failureReason: null,
      inputTokens: 1,
      outputTokens: 1,
      cachedTokens: 0,
      startedAt: now,
      finishedAt: now,
    ));
    await db.saveCollaborationArtifact(CollaborationArtifact(
      id: 'artifact-private',
      collaborationRunId: 'collab-private',
      producerAgentRunId: 'agent-private',
      type: 'synthesis',
      payloadJson: '{}',
      evidenceRefs: '[]',
      confidence: 1,
      createdAt: now,
    ));
    await db.saveCollaborationMessage(CollaborationMessage(
      id: 'message-private',
      collaborationRunId: 'collab-private',
      senderAgentRunId: 'agent-private',
      recipientRole: null,
      round: 1,
      contentDigest: 'digest',
      content: 'secret',
      artifactRefs: '[]',
      createdAt: now,
    ));

    await db.deleteTask('task-private');
    expect(await db.findTask('task-private'), isNull);
    expect(await db.findCollaborationRun('collab-private'), isNull);
    expect(await db.agentRunsForCollaboration('collab-private'), isEmpty);
    expect(await db.artifactsForCollaboration('collab-private'), isEmpty);
    expect(await db.messagesForCollaboration('collab-private'), isEmpty);
  });
}
