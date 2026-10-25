import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/android_accessibility_observe_tool.dart';
import 'package:mobile_agent/application/android_accessibility_session_service.dart';
import 'package:mobile_agent/application/approval_policy.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/domain/sensitive_tool_policy.dart';
import 'package:mobile_agent/domain/tool_codes.dart';
import 'package:mobile_agent/infrastructure/tools/android_accessibility_bridge.dart';
import 'package:mobile_agent/infrastructure/tools/tool_registry.dart';

void main() {
  late _FakeAccessibilityBridge bridge;
  late AndroidAccessibilitySessionService service;

  setUp(() {
    bridge = _FakeAccessibilityBridge();
    service = AndroidAccessibilitySessionService(bridge);
  });

  tearDown(() async {
    await service.endSession();
    service.dispose();
  });

  test('observation tool is sensitive, dangerous, read-only, and inputless',
      () {
    final tool = AndroidAccessibilityObserveTool(service, 'conversation-1');
    expect(tool.manifest.name, 'android_accessibility_observe');
    expect(tool.manifest.risk, ToolRisk.dangerous);
    expect(tool.manifest.sensitive, isTrue);
    expect(tool.manifest.traits.readOnly, isTrue);
    expect(tool.manifest.parametersSchema['additionalProperties'], isFalse);
    expect(tool.manifest.parametersSchema['properties'], isEmpty);
    expect(tool.riskForArguments(const {}), ToolRisk.dangerous);
    expect(tool.requiresPreviewPlan(const {}), isTrue);
    expect(
      const ApprovalPolicy()
          .decide(
            mode: ApprovalMode.fullAccess,
            risk: tool.riskForArguments(const {}),
            sensitive: tool.manifest.sensitive,
            trusted: true,
            toolName: tool.manifest.name,
          )
          .requiresUser,
      isTrue,
      reason: 'Screen observation always needs fresh approval.',
    );
  });

  test(
      'a fresh one-time approval reads only for the active owning conversation',
      () async {
    await service.beginSession('conversation-1');
    final tool = AndroidAccessibilityObserveTool(service, 'conversation-1');
    final details = tool.approvalDetailsFor(const {});

    expect(details?['target'], 'NEXUS Agent 当前窗口');
    expect(details?['scope'], contains('不读取其他应用'));

    final authorized = tool.authorizeAfterApproval(const {});
    final result = await tool.execute(authorized);

    expect(result.ok, isTrue);
    expect(result.data, containsPair('ok', true));
    expect(result.data, containsPair('sessionId', bridge.activeSessionId));
    expect(
        result.data, containsPair('packageName', 'com.nexusagent.app.debug'));
    expect(
      (result.data!['nodes'] as List).single,
      {'id': 'n1', 'label': '当前会话'},
    );
    expect(bridge.observeCalls, 1);

    final repeated = await tool.execute(authorized);
    expect(repeated.ok, isFalse);
    expect(repeated.code, ToolCodes.approvalRejected);
    expect(bridge.observeCalls, 1);
  });

  test('another conversation cannot observe or prepare an approval', () async {
    await service.beginSession('conversation-1');
    final wrongOwner =
        AndroidAccessibilityObserveTool(service, 'conversation-2');

    expect(wrongOwner.approvalDetailsFor(const {}), isNull);
    expect(
      () => wrongOwner.authorizeAfterApproval(const {}),
      throwsA(isA<ToolApprovalAuthorizationException>()),
    );
    expect(bridge.observeCalls, 0);
  });

  test('a session change after approval invalidates the one-time ticket',
      () async {
    await service.beginSession('conversation-1');
    final tool = AndroidAccessibilityObserveTool(service, 'conversation-1');
    expect(tool.approvalDetailsFor(const {}), isNotNull);
    final authorized = tool.authorizeAfterApproval(const {});

    await service.endSession('conversation-1');
    await service.beginSession('conversation-1');
    final result = await tool.execute(authorized);

    expect(result.ok, isFalse);
    expect(result.code, ToolCodes.approvalRejected);
    expect(bridge.observeCalls, 0);
  });

  test('an expired observation session is removed from the active capability',
      () async {
    await service.beginSession('conversation-1');
    service.expiresAtMs = DateTime.now()
        .subtract(const Duration(seconds: 1))
        .millisecondsSinceEpoch;

    expect(service.active, isFalse);
    expect(service.availableFor('conversation-1'), isFalse);
    expect(
      AndroidAccessibilityObserveTool(service, 'conversation-1')
          .approvalDetailsFor(const {}),
      isNull,
    );
  });

  test('screen observations redact both persisted arguments and results', () {
    expect(
      SensitiveToolPolicy.redactArguments(
        'android_accessibility_observe',
        const {},
      ),
      {'redacted': true},
    );
    expect(
      SensitiveToolPolicy.redactResultText(
        'android_accessibility_observe',
        'private page text',
      ),
      '[敏感工具内容已脱敏]',
    );
  });

  test('a Dart restart never adopts a native session', () async {
    bridge.orphanedSession = true;

    await service.refreshStatus();

    expect(service.active, isFalse);
    expect(bridge.endCalls, 1);
  });
}

class _FakeAccessibilityBridge extends AndroidAccessibilityBridge {
  String? activeSessionId;
  bool orphanedSession = false;
  var sessionsCreated = 0;
  int observeCalls = 0;
  int endCalls = 0;

  @override
  Future<Map<String, dynamic>> status() async => {
        'enabled': true,
        'sessionActive': orphanedSession || activeSessionId != null,
        'sessionId': orphanedSession ? 'orphaned-session' : activeSessionId,
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      };

  @override
  Future<Map<String, dynamic>> beginSession(String ownerId) async {
    activeSessionId = 'session-${++sessionsCreated}';
    return {
      'ok': true,
      'sessionId': activeSessionId,
      'expiresAtMs':
          DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
    };
  }

  @override
  Future<Map<String, dynamic>> observe({
    required String ownerId,
    required String sessionId,
  }) async {
    observeCalls++;
    if (sessionId != activeSessionId) {
      return {'ok': false, 'code': 'SESSION_EXPIRED'};
    }
    return {
      'ok': true,
      'sessionId': sessionId,
      'packageName': 'com.nexusagent.app.debug',
      'nodes': [
        {'id': 'n1', 'label': '当前会话'}
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> endSession(String? ownerId) async {
    endCalls++;
    orphanedSession = false;
    activeSessionId = null;
    return {'ok': true};
  }
}
