import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../application/assistant_entry_delivery.dart';
import '../application/assistant_role.dart';
import '../domain/assistant_page_context.dart';
import '../infrastructure/share/deep_link_service.dart';
import '../infrastructure/notifications/notification_intent.dart';
import '../presentation/navigation/assistant_entry_surface.dart';
import '../presentation/navigation/assistant_input_review_sheet.dart';
import '../presentation/navigation/mobile_shell.dart';

bool _registered = false;
int _epoch = 0;
Route<void>? _route;
ModalRoute<dynamic>? _reviewRoute;
DeepLinkService? _entries;
final _host = GlobalKey<_EntryHostState>();
var _review = GlobalKey();

void registerAssistantEntryUiChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.assistantEntryFixture',
      (method, params) async => ServiceExtensionResponse.result(
          jsonEncode(await _action(params['mode'] ?? 'inspect'))));
}

Future<Map<String, dynamic>> _action(String mode) async {
  if (mode == 'open') {
    if (_route != null) throw StateError('Close owned fixture first');
    NavigatorState? navigator;
    void visit(Element element) {
      if (navigator != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        navigator = element.state as NavigatorState;
      } else {
        element.visitChildElements(visit);
      }
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    if (navigator == null) throw StateError('No navigator');
    _epoch++;
    _entries = DeepLinkService.detached();
    final route = _route = MaterialPageRoute<void>(
        builder: (_) => MobileShell(deepLinks: _entries, pageBuilders: [
              (_) => _EntryHost(key: _host),
              (_) => const Scaffold(body: Center(child: Text('隔离入口任务页'))),
              (_) => const Scaffold(body: Center(child: Text('隔离入口工作区页'))),
              (_) => const Scaffold(body: Center(child: Text('隔离入口我的页'))),
            ]));
    unawaited(navigator!.push(route));
  } else if (mode == 'share') {
    _entries!.enqueueShare(['fixture_share_text']);
  } else if (mode == 'notification') {
    _entries!.enqueueNotification(
        const NotificationIntent(NotificationIntentKind.task, 'fixture-task'));
  } else if (mode == 'approval') {
    _entries!.enqueueNotification(const NotificationIntent(
        NotificationIntentKind.approval, 'fixture-approval'));
  } else if (mode == 'busyOn' || mode == 'busyOff') {
    _host.currentState!
        .update(() => _host.currentState!._busy = mode == 'busyOn');
  } else if (mode == 'lock' || mode == 'unlock') {
    _host.currentState!
        .update(() => _host.currentState!._unlocked = mode == 'unlock');
  } else if (mode == 'rewriteDraft') {
    _host.currentState!
        .update(() => _host.currentState!._draft = 'new_user_fixture_draft');
  } else if (mode == 'syntheticContext') {
    _entries!.enqueuePageContext(AssistantPageContext(
        id: 'synthetic-ui',
        sourcePackage: 'com.example.fixture',
        sourceLabel: '隔离页面',
        text: 'synthetic_context_review_text',
        capturedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 2))));
  } else if (mode == 'expiringContext') {
    _entries!.enqueuePageContext(AssistantPageContext(
        id: 'expiring-ui',
        sourcePackage: 'com.example.fixture',
        sourceLabel: '隔离过期页面',
        text: 'expiring_fixture_text',
        capturedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 2))));
  } else if (mode == 'takeNativeContext') {
    final global = DeepLinkService.instance;
    final pending = global.pendingExternal?.pageContext;
    if (pending != null &&
        pending.sourcePackage == 'com.nexusagent.app.debug' &&
        pending.text.contains('nexus_context_fixture_public')) {
      _host.currentState!._native = pending;
      if (_entries!.enqueuePageContext(pending)) {
        global.acknowledgeExternal(global.pendingExternal!.id);
      }
    }
  } else if (mode == 'retry') {
    final id = _entries!.pendingExternal?.id;
    if (id != null) _entries!.retryExternal(id);
  } else if (mode == 'lookupWait') {
    _host.currentState!._lookup = Completer<void>();
  } else if (mode == 'lookupRelease') {
    final lookup = _host.currentState!._lookup;
    if (lookup != null && !lookup.isCompleted) lookup.complete();
  } else if (mode == 'focusReviewEnd') {
    final context = _review.currentContext;
    if (context == null) throw StateError('No owned review');
    EditableText? field;
    void visit(Element element) {
      if (element.widget is EditableText) {
        field = element.widget as EditableText;
      } else {
        element.visitChildElements(visit);
      }
    }

    (context as Element).visitChildElements(visit);
    field!.focusNode.requestFocus();
    field!.controller.selection =
        TextSelection.collapsed(offset: field!.controller.text.length);
  } else if (mode == 'close') {
    _epoch++;
    final review = _reviewRoute;
    _reviewRoute = null;
    if (review != null && review.isActive) {
      review.navigator!.removeRoute(review);
    }
    final route = _route;
    _route = null;
    if (route != null && route.isActive) route.navigator!.removeRoute(route);
    await WidgetsBinding.instance.endOfFrame;
    _entries?.dispose();
    _entries = null;
    final global = DeepLinkService.instance;
    final pending = global.pendingExternal?.pageContext;
    if (pending?.sourcePackage == 'com.nexusagent.app.debug' &&
        pending!.text.contains('nexus_context_fixture_public')) {
      global.acknowledgeExternal(global.pendingExternal!.id);
    }
  }
  final host = _host.currentState;
  return {
    'fixtureOnly': true,
    'modelCalls': 0,
    'userDatabaseWrites': 0,
    'microphoneStarts': 0,
    'pending': _entries?.externalCount ?? 0,
    'ready': _entries?.consumptionReady ?? false,
    'draft': host?._draft,
    'reviews': host?._reviews ?? 0,
    'stages': host?._stages ?? 0,
    'navigations': host?._navigations ?? 0,
    'outcome': host?._last?.name,
    'reviewOpen': _reviewRoute?.isActive ?? false,
    'nativeContextReceived': host?._native != null,
    'nativePublicTextPresent':
        host?._native?.text.contains('nexus_context_fixture_public') ?? false,
    'nativePasswordExcluded':
        !(host?._native?.text.contains('NEXUS_PASSWORD_MUST_NOT_BE_CAPTURED') ??
            false),
    'nativeSourcePackage': host?._native?.sourcePackage,
    'nativeTextLength': host?._native?.text.length,
    'nativeTruncated': host?._native?.truncated,
  };
}

class _EntryHost extends StatefulWidget {
  const _EntryHost({super.key});
  @override
  State<_EntryHost> createState() => _EntryHostState();
}

class _EntryHostState extends State<_EntryHost> {
  late final _links = _entries!;
  String _draft = 'existing_fixture_draft';
  bool _busy = false, _unlocked = true, _scheduled = false, _consuming = false;
  int _reviews = 0, _stages = 0, _navigations = 0;
  AssistantEntryOutcome? _last;
  AssistantPageContext? _native;
  Completer<void>? _lookup;
  @override
  void initState() {
    super.initState();
    _links.addListener(_schedule);
  }

  @override
  void dispose() {
    _links.removeListener(_schedule);
    super.dispose();
  }

  void update(VoidCallback action) {
    setState(action);
    _schedule();
  }

  bool _available() =>
      mounted &&
      _unlocked &&
      AssistantEntrySurface.canConsume(context,
          busy: _busy && AssistantEntryDelivery.requiresIdle(_links));
  void _schedule() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && _available() && _links.consumptionReady) {
        unawaited(_consume());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _consume() async {
    final entry = _links.pendingExternal;
    if (_consuming || entry == null) return;
    _consuming = true;
    final before = _draft, epoch = _epoch;
    try {
      final result = await const AssistantEntryDelivery().deliver(_links, entry,
          canPresent: _available,
          contextUnchanged: () =>
              mounted && _draft == before && epoch == _epoch,
          pageContextAllowed: () async =>
              _native == null ||
              (await const PlatformAssistantRoleSource().status()).connected,
          navigate: (intent) async {
            await _lookup?.future;
            if (!mounted || !_available()) {
              throw StateError('Fixture lookup lost visibility');
            }
            _navigations++;
            unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('隔离通知目标')),
                    body: const Center(child: Text('只导航，不执行动作'))))));
          },
          review: () async {
            _reviews++;
            final page = entry.pageContext;
            final key = _review = GlobalKey();
            final future = showModalBottomSheet<AssistantInputDecision>(
                context: context,
                useSafeArea: true,
                isScrollControlled: true,
                builder: (_) => AssistantInputReviewSheet(
                    key: key,
                    title: page == null ? '检查分享内容' : '检查本次页面文字',
                    initialText: page?.text ?? entry.shared.join('\n\n'),
                    source: page == null
                        ? '来源：隔离系统分享'
                        : '来源：${page.sourceLabel} (${page.sourcePackage})',
                    expiresAt: page?.expiresAt,
                    validFor: page?.remainingLifetime));
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && epoch == _epoch && key.currentContext != null) {
                _reviewRoute = ModalRoute.of(key.currentContext!);
              }
            });
            final decision = await future;
            _reviewRoute = null;
            return decision;
          },
          stage: (text) {
            _draft = '$_draft\n\n$text';
            _stages++;
          });
      if (mounted) setState(() => _last = result);
    } catch (_) {
      if (mounted) setState(() => _last = AssistantEntryOutcome.deferred);
    } finally {
      _consuming = false;
    }
  }

  void _nested() =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (page) => PopScope(
              canPop: false,
              child: Scaffold(
                  appBar: AppBar(title: const Text('隔离入口未保存页')),
                  body: Column(children: [
                    const Text('外部输入不能弹掉本页'),
                    TextButton(
                        onPressed: () => Navigator.of(page).pop(),
                        child: const Text('保留草稿并返回'))
                  ]))))));
  @override
  Widget build(BuildContext context) {
    if (_links.consumptionReady && _available()) _schedule();
    return Scaffold(
        appBar: AppBar(title: const Text('隔离外部入口验收')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('生产队列、交付协调器与核对页；隔离落地，不写用户库、不发模型。'),
          Text(_busy ? '任务忙碌，输入保留' : (_unlocked ? '已解锁，可处理输入' : '应用锁未解开，输入保留')),
          Text('待处理：${_links.externalCount}，已加入草稿：$_stages'),
          Text(_draft),
          TextButton(onPressed: _nested, child: const Text('打开隔离入口未保存页')),
          if (_links.hasPending && !_links.consumptionReady)
            TextButton(
                onPressed: () {
                  final id = _links.pendingExternal?.id;
                  if (id != null) _links.retryExternal(id);
                },
                child: const Text('重试待处理入口')),
        ]));
  }
}
