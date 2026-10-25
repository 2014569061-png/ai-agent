import '../infrastructure/share/deep_link_service.dart';
import '../application/speech_submission_guard.dart';
import '../presentation/navigation/mobile_shell.dart';
import '../presentation/navigation/assistant_entry_surface.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../application/speech_capture.dart';
import '../presentation/voice/speech_capture_sheet.dart';

class _UiSpeechSource implements SpeechCaptureSource {
  _UiSpeechSource(this.available);
  final bool available;
  final stream = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  int starts = 0, cancels = 0, permissions = 0;
  String? id;
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<SpeechCapabilities> inspect() async =>
      SpeechCapabilities(onDevice: available, permission: true);
  @override
  Future<bool> requestPermission(String sessionId) async {
    permissions++;
    return false;
  }

  @override
  Future<bool> start(String sessionId,
      {required bool systemService, required String language}) async {
    id = sessionId;
    starts++;
    return true;
  }

  @override
  Future<void> stop(String sessionId) async {}
  @override
  Future<void> cancel(String sessionId) async {
    cancels++;
  }

  void emit(String sessionId, String text) =>
      stream.add({'sessionId': sessionId, 'type': 'result', 'text': text});
}

bool _registered = false;
DeepLinkService? _fixtureLinks;
int _epoch = 0;
NavigatorState? _navigator;
Route<void>? _route, _cover;
ModalRoute<dynamic>? _sheetRoute;
final _host = GlobalKey<_SpeechUiHostState>();
var _sheet = GlobalKey();
_UiSpeechSource? _source;
SpeechCaptureController? _capture;
String? _previousSession;
void registerSpeechCaptureUiChecks() {
  if (!kDebugMode || _registered) return;
  _registered = true;
  registerExtension(
      'ext.nexus.speechCaptureFixture',
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
    _navigator = navigator;
    _fixtureLinks = DeepLinkService.detached();
    final route = _route = MaterialPageRoute<void>(
        builder: (_) => MobileShell(deepLinks: _fixtureLinks, pageBuilders: [
              (_) => _SpeechUiHost(key: _host),
              (_) => const Scaffold(body: Center(child: Text('隔离任务页'))),
              (_) => const Scaffold(body: Center(child: Text('隔离工作区页'))),
              (_) => const Scaffold(body: Center(child: Text('隔离我的页'))),
            ]));
    unawaited(navigator!.push(route));
  } else if (mode == 'result') {
    final id = _source?.id;
    if (id == null) throw StateError('No synthetic capture');
    _source!.emit(id, 'fixture voice draft');
  } else if (mode == 'late') {
    if (_previousSession == null) {
      throw StateError('No previous synthetic session');
    }
    _source!.emit(_previousSession!, 'OBSOLETE VOICE TEXT');
  } else if (mode == 'available') {
    _host.currentState!.available();
  } else if (mode == 'lateCurrent') {
    final id = _source?.id;
    if (id != null) _source!.emit(id, 'OBSOLETE VOICE TEXT');
  } else if (mode == 'assistantLink') {
    _fixtureLinks!.handleUri(Uri.parse('nexus://assistant'));
  } else if (mode == 'promptLink') {
    _fixtureLinks!
        .handleUri(Uri.parse('nexus://new-chat?prompt=fixture_entry_1'));
  } else if (mode == 'secondPromptLink') {
    _fixtureLinks!
        .handleUri(Uri.parse('nexus://new-chat?prompt=fixture_entry_2'));
  } else if (mode == 'busyOn') {
    _host.currentState!.setBusy(true);
  } else if (mode == 'preexistingEntry') {
    _fixtureLinks!
        .handleUri(Uri.parse('nexus://new-chat?prompt=retained_before_voice'));
    _fixtureLinks!.markConsumptionFailed(_fixtureLinks!.revision);
  } else if (mode == 'drainExistingEntry') {
    _fixtureLinks!.drainPrompt();
  } else if (mode == 'busyOff') {
    _host.currentState!.setBusy(false);
  } else if (mode == 'unavailable') {
    _host.currentState!.unavailable();
  } else if (mode == 'focusEnd') {
    final context = _sheet.currentContext;
    if (context == null) throw StateError('No owned sheet');
    EditableText? editable;
    void visit(Element element) {
      if (element.widget is EditableText) {
        editable = element.widget as EditableText;
      } else {
        element.visitChildElements(visit);
      }
    }

    (context as Element).visitChildElements(visit);
    final field = editable;
    if (field == null) throw StateError('No fixture editor');
    field.focusNode.requestFocus();
    field.controller.selection =
        TextSelection.collapsed(offset: field.controller.text.length);
  } else if (mode == 'cover') {
    if (_cover != null) throw StateError('Cover already open');
    final route = _cover = DialogRoute<void>(
        context: _host.currentContext!,
        builder: (_) => const AlertDialog(
            title: Text('隔离语音遮盖层'), content: Text('旧语音回调不得关闭此层或自动发送')));
    unawaited(_navigator!.push(route));
  } else if (mode == 'uncover') {
    final cover = _cover;
    _cover = null;
    if (cover != null && cover.isActive) _navigator!.removeRoute(cover);
  } else if (mode == 'close') {
    _epoch++;
    final cover = _cover;
    _cover = null;
    if (cover != null && cover.isActive) _navigator!.removeRoute(cover);
    final sheet = _sheetRoute;
    _sheetRoute = null;
    if (sheet != null && sheet.isActive) sheet.navigator!.removeRoute(sheet);
    await _capture?.cancel();
    _capture?.dispose();
    _capture = null;
    await _source?.stream.close();
    _source = null;
    final route = _route;
    _route = null;
    if (route != null && route.isActive) _navigator!.removeRoute(route);
    await WidgetsBinding.instance.endOfFrame;
    _fixtureLinks?.dispose();
    _fixtureLinks = null;
    _navigator = null;
    _previousSession = null;
  }
  return {
    'fixtureOnly': true,
    'modelCalls': 0,
    'externalActions': 0,
    'realMicrophoneStarts': 0,
    'pendingEntry': _fixtureLinks?.hasPending ?? false,
    'pendingPrompt': _fixtureLinks?.pendingPrompt,
    'prefill': _host.currentState?._prefill,
    'entryCount': _host.currentState?._entryCount ?? 0,
    'phase': _capture?.phase.name,
    'transcript': _capture?.transcript,
    'starts': _source?.starts ?? 0,
    'cancels': _source?.cancels ?? 0,
    'permissionRequests': _source?.permissions ?? 0,
    'resultText': _host.currentState?.result?.text,
    'autoSend': _host.currentState?.result?.autoSend ?? false,
    'submissionAllowed': _host.currentState?.submissionAllowed ?? false,
    'coverVisible': _cover?.isCurrent ?? false,
    'sheetOpen': _sheetRoute?.isActive ?? false
  };
}

class _SpeechUiHost extends StatefulWidget {
  const _SpeechUiHost({super.key});
  @override
  State<_SpeechUiHost> createState() => _SpeechUiHostState();
}

class _SpeechUiHostState extends State<_SpeechUiHost> {
  SpeechCaptureDraft? result;
  bool submissionAllowed = false;
  bool _available = true, _opening = false;
  late final DeepLinkService _links;
  bool _busy = false, _entryScheduled = false;
  String? _prefill;
  int _entryCount = 0;
  @override
  void initState() {
    super.initState();
    _links = _fixtureLinks!;
    _links.addListener(_scheduleEntry);
  }

  @override
  void dispose() {
    _links.removeListener(_scheduleEntry);
    super.dispose();
  }

  void available() {
    setState(() => _available = true);
  }

  void setBusy(bool value) {
    setState(() => _busy = value);
  }

  void _scheduleEntry() {
    if (!mounted || _entryScheduled) return;
    _entryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entryScheduled = false;
      if (!mounted ||
          !_links.consumptionReady ||
          !AssistantEntrySurface.canConsume(context, busy: _busy)) {
        return;
      }
      final prompt = _links.drainPrompt();
      final assistant = _links.drainAssistant();
      if (prompt != null || assistant) {
        setState(() {
          if (prompt != null) _prefill = prompt;
          _entryCount++;
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _nested() {
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (page) => PopScope(
            canPop: false,
            child: Scaffold(
                appBar: AppBar(title: const Text('隔离未保存编辑页')),
                body: Column(children: [
                  const Text('自动入口不得弹出未保存页面'),
                  TextButton(
                      onPressed: () => Navigator.of(page).pop(),
                      child: const Text('确认离开隔离页')),
                ]))))));
  }

  void unavailable() {
    setState(() => _available = false);
  }

  Future<void> open() async {
    if (_opening) return;
    _opening = true;
    final epoch = _epoch;
    _previousSession = _source?.id ?? _previousSession;
    _capture?.dispose();
    await _source?.stream.close();
    if (!mounted || epoch != _epoch) {
      _opening = false;
      return;
    }
    final source = _source = _UiSpeechSource(_available);
    final capture = _capture =
        SpeechCaptureController(source: source, stopSpeaking: () async {});
    if (!mounted) return;
    final submission = SpeechSubmissionGuard.capture(_links);
    setState(() {
      result = null;
      submissionAllowed = false;
    });
    final sheetKey = _sheet = GlobalKey();
    final future = showModalBottomSheet<SpeechCaptureDraft>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SpeechCaptureSheet(key: sheetKey, controller: capture));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && epoch == _epoch && identical(_sheet, sheetKey)) {
        _sheetRoute = sheetKey.currentContext == null
            ? null
            : ModalRoute.of(sheetKey.currentContext!);
      }
    });
    final value = await future;
    _sheetRoute = null;
    if (mounted && epoch == _epoch) {
      setState(() {
        result = value;
        submissionAllowed = value != null &&
            submission.allowsAutoSend(
                links: _links,
                requested: value.autoSend,
                initiallyEmpty: true,
                draftUnchanged: true,
                attachmentsEmpty: true,
                contextAvailable:
                    AssistantEntrySurface.canConsume(context, busy: _busy));
      });
    }
    _opening = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_links.consumptionReady &&
        AssistantEntrySurface.canConsume(context, busy: _busy)) {
      _scheduleEntry();
    }
    return Scaffold(
        appBar: AppBar(title: const Text('隔离验收 · 语音输入')),
        body: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('生产语音Sheet + 内存识别Source；无真实录音/授权/模型/用户草稿写入。'),
              Text(_busy ? '入口等待忙碌结束' : '入口可呈现'),
              if (_prefill != null) Text('入口预填：$_prefill'),
              TextButton(onPressed: _nested, child: const Text('打开隔离未保存页')),
              FilledButton(onPressed: open, child: const Text('打开隔离语音')),
              Text(result == null ? '没有提交语音文字' : '已暂存：${result!.text}'),
              Text(result?.autoSend == true ? '仅记录自动发送意图；没有调用模型' : '自动发送关闭'),
            ])));
  }
}
