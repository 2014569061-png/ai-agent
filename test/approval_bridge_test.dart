import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/application/approval_bridge.dart';
import 'package:mobile_agent/application/approval_notification_text.dart';
import 'package:mobile_agent/domain/approval_action_codec.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/infrastructure/database/app_database.dart';

/// 锁屏审批通道的守护。
///
/// 这条链路跨三个边界：通知动作 id 的编解码、数据库的一次性握手行、以及
/// 「谁先决定谁生效」的并发语义。任何一处写错，症状都是「点了批准毫无反应」，
/// 而那时候用户正锁着屏，没有任何日志可看——所以必须在这里钉死。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('动作 id 编解码', () {
    test('批准与拒绝都能往返', () {
      final approve = parseApprovalActionId(
          encodeApprovalActionId('appr-1', approve: true));
      expect(approve?.requestId, 'appr-1');
      expect(approve?.approve, isTrue);

      final deny = parseApprovalActionId(
          encodeApprovalActionId('appr-2', approve: false));
      expect(deny?.requestId, 'appr-2');
      expect(deny?.approve, isFalse);
    });

    test('requestId 自身含冒号也不会解析错位', () {
      final parsed =
          parseApprovalActionId(encodeApprovalActionId('a:b:c', approve: true));
      expect(parsed?.requestId, 'a:b:c');
      expect(parsed?.approve, isTrue);
    });

    test('无法识别的动作 id 一律返回 null，不猜', () {
      for (final raw in <String?>[
        null,
        '',
        'approve',
        'approve:',
        ':appr-1',
        'unknown:appr-1',
        'appr-1',
      ]) {
        expect(parseApprovalActionId(raw), isNull, reason: 'input=$raw');
      }
    });
  });

  group('一次性握手行', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
    });

    test('初始未决，写入决定后可读出', () async {
      await db.insertPendingApproval(
        requestId: 'appr-1',
        toolName: 'terminal',
        summary: 'terminal（需确认）',
        risk: 'requiresConfirmation',
        ttl: const Duration(minutes: 5),
      );

      expect(await db.findPendingApprovalDecision('appr-1'), isNull);

      expect(await db.decidePendingApproval('appr-1', approvalApproveAction),
          isTrue);
      expect(await db.findPendingApprovalDecision('appr-1'),
          approvalApproveAction);
    });

    test('只有第一条决定生效，后到的不会覆盖', () async {
      await db.insertPendingApproval(
        requestId: 'appr-2',
        toolName: 'terminal',
        summary: 'x',
        risk: 'requiresConfirmation',
        ttl: const Duration(minutes: 5),
      );

      expect(
          await db.decidePendingApproval('appr-2', approvalDenyAction), isTrue);
      // 锁屏动作与前台弹窗几乎同时提交时，第二条必须被丢弃。
      expect(await db.decidePendingApproval('appr-2', approvalApproveAction),
          isFalse);
      expect(
          await db.findPendingApprovalDecision('appr-2'), approvalDenyAction);
    });

    test('清理只删过期行，未过期的不受影响', () async {
      await db.insertPendingApproval(
        requestId: 'expired',
        toolName: 'terminal',
        summary: 'x',
        risk: 'x',
        ttl: const Duration(seconds: -30),
      );
      await db.insertPendingApproval(
        requestId: 'alive',
        toolName: 'terminal',
        summary: 'x',
        risk: 'x',
        ttl: const Duration(minutes: 5),
      );

      expect(await db.prunePendingApprovals(), 1);
      expect(await db.findPendingApprovalDecision('expired'), isNull);
      final alive = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM pending_approvals',
          )
          .getSingle();
      expect(alive.read<int>('c'), 1);
    });
  });

  group('端到端：外部写入决定被轮到', () {
    test('批准 → true，并且握手行在返回后被清理', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final future =
          const ApprovalBridge(pollInterval: Duration(milliseconds: 20))
              .requestDecision(
        toolName: 'terminal',
        summary: 'terminal（需确认）',
        risk: 'requiresConfirmation',
        timeout: const Duration(seconds: 5),
        database: db,
      );

      // 模拟「另一个 isolate 里的通知动作」：等请求落库后写入决定。
      final requestId = await _waitForRequestId(db);
      expect(await db.decidePendingApproval(requestId, approvalApproveAction),
          isTrue);

      expect(await future, isTrue);
      await _expectNoPendingRows(db);
    });

    test('拒绝 → false', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final future =
          const ApprovalBridge(pollInterval: Duration(milliseconds: 20))
              .requestDecision(
        toolName: 'terminal',
        summary: 'x',
        risk: 'dangerous',
        timeout: const Duration(seconds: 5),
        database: db,
      );

      final requestId = await _waitForRequestId(db);
      await db.decidePendingApproval(requestId, approvalDenyAction);

      expect(await future, isFalse);
    });

    test('无人处理时超时返回 null，并保留 expired 决策', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final decision =
          await const ApprovalBridge(pollInterval: Duration(milliseconds: 20))
              .requestDecision(
        toolName: 'terminal',
        summary: 'x',
        risk: 'dangerous',
        timeout: const Duration(milliseconds: 120),
        database: db,
      );

      expect(decision, isNull);
      final rows = await db
          .customSelect(
            'SELECT decision FROM pending_approvals',
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('decision'), approvalExpiredAction);
    });
  });

  group('锁屏正文的隐私约束', () {
    test('参数敏感的工具只显示工具名与风险，不带参数原文', () {
      final text = approvalNotificationSummary(
        const ToolCall(
          id: 'c1',
          name: 'terminal',
          arguments: {'command': 'cat ~/.ssh/id_rsa'},
        ),
        ToolRisk.requiresConfirmation,
      );

      expect(text, contains('terminal'));
      expect(text, contains('需确认'));
      // 关键：锁屏上旁人能看到这段文字，私钥路径绝不能出现。
      expect(text, isNot(contains('id_rsa')));
      expect(text, isNot(contains('command')));
    });

    test('非敏感工具只截断展示参数，避免撑满通知', () {
      final text = approvalNotificationSummary(
        ToolCall(
          id: 'c2',
          name: 'calculator',
          arguments: {'expression': 'x' * 400},
        ),
        ToolRisk.safe,
      );

      expect(text, contains('calculator'));
      expect(text.length, lessThan(160));
      expect(text, contains('…'));
    });
  });
}

/// 等请求落库并取出它的 requestId（模拟另一个 isolate 看到的那一行）。
Future<String> _waitForRequestId(AppDatabase db) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final rows = await db
        .customSelect('SELECT request_id FROM pending_approvals LIMIT 1')
        .get();
    if (rows.isNotEmpty) return rows.first.read<String>('request_id');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('审批请求未落库');
}

Future<void> _expectNoPendingRows(AppDatabase db) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM pending_approvals')
      .getSingle();
  expect(row.read<int>('c'), 0);
}
