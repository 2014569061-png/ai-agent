import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_page_layout.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/browser_session_service.dart';
import '../../application/android_accessibility_session_service.dart';
import '../../application/chat_controller.dart';
import '../../application/log_service.dart';
import '../../domain/browser_session.dart';
import '../../domain/models.dart';
import '../widgets/tool_approval_helper.dart';
import '../theme/mobile_theme.dart';

class BrowserPage extends ConsumerStatefulWidget {
  const BrowserPage(
      {super.key, required this.conversationId, this.viewBuilder});
  final String conversationId;
  final Widget Function(String sessionId)? viewBuilder;
  @override
  ConsumerState<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends ConsumerState<BrowserPage>
    with WidgetsBindingObserver {
  final _url = TextEditingController();
  final _urlFocus = FocusNode();
  final _request = TextEditingController();
  late BrowserSessionService _browser;
  late AndroidAccessibilitySessionService _accessibility;
  late ChatController _chat;
  late LogService _logs;
  String? _ownedSession;
  bool _ready = false, _busy = false, _sending = false;
  bool _wasAgent = false;
  bool _currentOwner = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _browser = ref.read(browserSessionProvider);
    _accessibility = ref.read(androidAccessibilitySessionProvider);
    _chat = ref.read(chatControllerProvider.notifier);
    _logs = ref.read(logServiceProvider);
    ref.listenManual(chatControllerProvider, (previous, next) {
      _currentOwner = next.conversationId == widget.conversationId;
      if (!_currentOwner) {
        unawaited(_takeover());
        unawaited(_accessibility.endSession(widget.conversationId));
      }
    }, fireImmediately: true);
    _browser.addListener(_updated);
    _accessibility.addListener(_accessibilityUpdated);
    unawaited(_refreshAccessibilityStatus());
    _urlFocus.addListener(() {
      if (_urlFocus.hasFocus && _browser.agentControlled) {
        unawaited(_takeover());
      }
    });
    unawaited(_perform(() async {
      await _browser.open(widget.conversationId);
      if (!mounted) {
        await _browser.close();
        return;
      }
      _ownedSession = _browser.sessionId;
      _ready = true;
    }));
  }

  void _updated() {
    final currentUrl = _browser.state['url'];
    if (!_urlFocus.hasFocus &&
        currentUrl is String &&
        currentUrl.isNotEmpty &&
        currentUrl != 'about:blank') {
      _url.text = currentUrl;
    }
    if (_wasAgent && !_browser.agentControlled && _sending && _currentOwner) {
      _chat.stop();
    }
    _wasAgent = _browser.agentControlled;
    if (mounted) setState(() {});
  }

  void _accessibilityUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshAccessibilityStatus() async {
    try {
      await _accessibility.refreshStatus();
    } catch (_) {
      // The controls remain disabled with a safe fallback on non-Android hosts.
    }
  }

  Future<void> _toggleAccessibilitySession() async {
    try {
      if (_accessibility.availableFor(widget.conversationId)) {
        await _accessibility.endSession(widget.conversationId);
      } else if (!_accessibility.enabled) {
        await _accessibility.openSettings();
      } else {
        await _accessibility.beginSession(widget.conversationId);
      }
      if (mounted) {
        setState(() => _error = null);
      }
    } on AccessibilitySessionFailure catch (error) {
      if (mounted) {
        setState(() => _error = switch (error.code) {
              'ACCESSIBILITY_DISABLED' => '请先在系统设置中启用 NEXUS 无障碍服务',
              'OWNER_MISMATCH' => '无障碍观察已由其他会话占用',
              'SESSION_BUSY' => '无障碍观察正在切换，请稍后重试',
              _ => '无障碍观察未能开启（${error.code}）',
            });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无障碍设置暂不可用，请稍后重试');
    }
  }

  Future<void> _perform(Future<void> Function() operation) async {
    if (_busy) return;
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      await operation();
    } on BrowserFailure catch (error) {
      if (mounted) {
        setState(() => _error = error.code == 'CAPABILITY_UNAVAILABLE'
            ? '当前 WebView 不支持独立会话，请更新 Android 系统 WebView 后重试。'
            : '浏览器操作未完成，请检查连接或重新打开会话。');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '浏览器暂不可用，请重新打开。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _visit() => _perform(() async {
        final uri = browserUrl(_url.text.trim());
        await _browser.command(widget.conversationId, 'visit', {'url': '$uri'});
        if (mounted) FocusScope.of(context).unfocus();
      });

  Future<void> _takeover() async {
    if (_ownedSession == null || _browser.sessionId != _ownedSession) return;
    _wasAgent = false;
    if (_currentOwner) _chat.stop();
    try {
      await _browser.control('user');
    } catch (error) {
      if (mounted) setState(() => _error = '停止确认未返回，请关闭本会话后重试。');
    }
  }

  Future<void> _send() async {
    final text = _request.text.trim();
    if (text.isEmpty || _sending || !_browser.agentControlled) return;
    final controller = ref.read(chatControllerProvider.notifier);
    if (ref.read(chatControllerProvider).conversationId !=
        widget.conversationId) {
      await _takeover();
      return;
    }
    setState(() => _sending = true);
    _request.clear();
    FocusScope.of(context).unfocus();
    try {
      controller.setMode(ChatMode.agent);
      await controller.send(
          text: text,
          attachments: const [],
          approveTool: (call, risk, sensitive) async {
            if (!mounted || !_browser.agentControlled) {
              return ToolApproval.reject;
            }
            return promptToolApproval(context, ref, call, risk, sensitive);
          });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _browser.sessionId != null) {
      // Native onPause also revokes synchronously. Never auto-resume control.
      unawaited(_takeover());
    }
    if (state == AppLifecycleState.resumed) {
      // A prior short-lived observation is never restored after returning.
      unawaited(_refreshAccessibilityStatus());
    } else {
      unawaited(_accessibility.endSession(widget.conversationId));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _browser.removeListener(_updated);
    _accessibility.removeListener(_accessibilityUpdated);
    unawaited(_accessibility.endSession(widget.conversationId));
    if (_sending && _currentOwner) _chat.stop();
    if (_ownedSession != null && _browser.sessionId == _ownedSession) {
      unawaited(_browser.close().catchError((Object error) {
        unawaited(_logs.warning('Browser cleanup unconfirmed',
            category: 'browser',
            detail: {
              'phase': 'close',
              'errorType': error.runtimeType.toString()
            }));
      }));
    }
    _url.dispose();
    _urlFocus.dispose();
    _request.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final currentOwner = chat.conversationId == widget.conversationId;
    final controls =
        _ready && !_busy && currentOwner && _browser.state['attached'] == true;
    final accessibilityActive =
        _accessibility.availableFor(widget.conversationId);
    return Scaffold(
      appBar: NexusPageHeader(title: '内置浏览器', actions: [
        IconButton(
            tooltip: '立即接管',
            icon: const Icon(Icons.pan_tool_outlined),
            onPressed: _ready ? _takeover : null),
        IconButton(
            tooltip: '关闭会话',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop()),
      ]),
      body: NexusPageLayout(
          mobileMaxWidth: double.infinity,
          desktopMaxWidth: double.infinity,
          child: SafeArea(
              child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                      child: SizedBox(
                          height: math.max(
                              constraints.maxHeight,
                              MediaQuery.textScalerOf(context).scale(340) +
                                  240),
                          child: Column(children: [
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(children: [
                                  Expanded(
                                      child: TextField(
                                          controller: _url,
                                          focusNode: _urlFocus,
                                          keyboardType: TextInputType.url,
                                          onSubmitted:
                                              controls ? (_) => _visit() : null,
                                          decoration: const InputDecoration(
                                              labelText: '网页地址',
                                              hintText: 'https://…',
                                              isDense: true))),
                                  IconButton(
                                      tooltip: '打开网页',
                                      onPressed: controls ? _visit : null,
                                      icon: const Icon(Icons.arrow_forward)),
                                ])),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                    _browser.agentControlled
                                        ? '助手控制中 · 每次操作需确认，触碰网页即可接管\n临时会话，关闭后需重新登录。'
                                        : '由你控制 · 可手动浏览或允许助手操作\n临时会话，关闭后需重新登录。',
                                    style:
                                        Theme.of(context).textTheme.bodySmall)),
                            if (!_browser.agentControlled)
                              Wrap(spacing: 8, children: [
                                TextButton.icon(
                                    icon: const Icon(Icons.smart_toy_outlined),
                                    onPressed: controls &&
                                            !_browser.agentControlled
                                        ? () => _perform(() async {
                                              FocusScope.of(context).unfocus();
                                              await _browser.control('agent');
                                            })
                                        : null,
                                    label: const Text('允许助手操作')),
                              ]),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(MobileTheme.insetRadius),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(
                                    children: [
                                      const Icon(
                                          Icons.accessibility_new_rounded),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          accessibilityActive
                                              ? '本应用只读观察已开启 · 每次读取须批准 · 5 分钟自动结束'
                                              : _accessibility.enabled
                                                  ? '可选：允许助手读取 NEXUS 当前窗口的可访问文字'
                                                  : '可选：系统无障碍服务未启用；仅在你手动开启后可读取本应用界面',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      OutlinedButton(
                                        onPressed: _busy
                                            ? null
                                            : _toggleAccessibilitySession,
                                        child: Text(
                                          accessibilityActive
                                              ? '停止'
                                              : _accessibility.enabled
                                                  ? '开始'
                                                  : '设置',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_busy || _browser.state['loading'] == true)
                              const LinearProgressIndicator(),
                            if (_error != null)
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(_error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                            Expanded(
                                child: _ready &&
                                        _browser.sessionId != null &&
                                        !kIsWeb
                                    ? widget.viewBuilder
                                            ?.call(_browser.sessionId!) ??
                                        AndroidView(
                                            key: ValueKey(_browser.sessionId),
                                            viewType: 'nexus/browser-view',
                                            gestureRecognizers: {
                                              Factory<OneSequenceGestureRecognizer>(
                                                  () =>
                                                      EagerGestureRecognizer()),
                                            },
                                            creationParams: {
                                              'sessionId': _browser.sessionId
                                            },
                                            creationParamsCodec:
                                                const StandardMessageCodec())
                                    : const Center(child: Text('独立浏览器会话'))),
                            if (chat.messages.isNotEmpty)
                              ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxHeight: 80),
                                  child: SingleChildScrollView(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(chat.messages.last.text,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis))),
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(children: [
                                  Expanded(
                                      child: TextField(
                                          controller: _request,
                                          maxLines: 2,
                                          minLines: 1,
                                          enabled: controls &&
                                              _browser.agentControlled &&
                                              !chat.running,
                                          decoration: const InputDecoration(
                                              hintText: '让助手在当前网页完成什么？',
                                              isDense: true))),
                                  IconButton(
                                      tooltip:
                                          chat.running ? '停止任务' : '发送浏览器任务',
                                      onPressed: chat.running
                                          ? _takeover
                                          : controls && _browser.agentControlled
                                              ? _send
                                              : null,
                                      icon: Icon(chat.running
                                          ? Icons.stop
                                          : Icons.send_outlined)),
                                ])),
                          ])))))),
    );
  }
}
