import 'package:flutter/services.dart';
import '../navigation/assistant_entry_surface.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../application/speech_capture.dart';
import '../../domain/unique_id.dart';
import '../../infrastructure/tts/tts_service.dart';

class SpeechCaptureDraft {
  const SpeechCaptureDraft(this.text, {this.autoSend = false});
  final String text;
  final bool autoSend;
}

class SpeechCaptureSheet extends StatefulWidget {
  const SpeechCaptureSheet({super.key, this.controller});
  final SpeechCaptureController? controller;
  @override
  State<SpeechCaptureSheet> createState() => _SpeechCaptureSheetState();
}

class _SpeechCaptureSheetState extends State<SpeechCaptureSheet>
    with WidgetsBindingObserver {
  late final SpeechCaptureController _capture;
  final _text = TextEditingController();
  ModalRoute<dynamic>? _ownedRoute;
  NavigatorState? _ownedNavigator;
  bool _hiddenCancelScheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ownedRoute ??= ModalRoute.of(context);
    _ownedNavigator ??= Navigator.of(context);
  }

  void _closeOwned(Object? result) {
    final route = _ownedRoute;
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      _ownedNavigator!.pop(result);
    } else {
      _ownedNavigator!.removeRoute(route, result);
    }
  }

  String _lastTranscript = '';
  String _language = 'zh-CN';
  bool _systemService = false, _autoSend = false, _closing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _capture = widget.controller ??
        SpeechCaptureController(
            source:
                AndroidSpeechCaptureSource(UniqueId.generate('speech_owner')),
            stopSpeaking: () async {
              if (!await TtsService.instance.stopBeforeRecording()) {
                throw PlatformException(code: 'TTS_STOP_UNCONFIRMED');
              }
            });
    _capture.addListener(_changed);
    unawaited(_capture.initialize());
  }

  void _changed() {
    if (!mounted || _closing) return;
    if (_capture.transcript != _lastTranscript) {
      _lastTranscript = _capture.transcript;
      _text.value = TextEditingValue(
          text: _lastTranscript,
          selection: TextSelection.collapsed(offset: _lastTranscript.length));
    }
    setState(() {});
    if (_autoSend && _capture.phase == SpeechCapturePhase.ready) {
      scheduleMicrotask(() {
        if (mounted &&
            !_closing &&
            _autoSend &&
            _capture.phase == SpeechCapturePhase.ready &&
            _ownedRoute?.isCurrent == true &&
            AssistantEntrySurface.canConsume(context)) {
          _useDraft();
        }
      });
    }
  }

  void _useDraft() {
    if (_ownedRoute?.isCurrent != true ||
        !AssistantEntrySurface.canConsume(context)) {
      return;
    }
    final text = _text.text.trim();
    if (text.isEmpty || _capture.capturing || _closing) return;
    _closing = true;
    unawaited(_capture.cancel());
    _closeOwned(SpeechCaptureDraft(text, autoSend: _autoSend));
  }

  Future<void> _cancel() async {
    if (_closing) return;
    _closing = true;
    await _capture.cancel();
    if (mounted) _closeOwned(null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      if (mounted && !_closing && _autoSend) {
        setState(() => _autoSend = false);
      }
      unawaited(_capture.cancel());
      unawaited(TtsService.instance.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _capture.removeListener(_changed);
    unawaited(_capture.cancel());
    if (widget.controller == null) _capture.dispose();
    _text.dispose();
    super.dispose();
  }

  String get _status => switch (_capture.phase) {
        SpeechCapturePhase.idle => '点击录音，或按住说话、松开结束',
        SpeechCapturePhase.checking => '正在准备语音输入',
        SpeechCapturePhase.permission => '等待麦克风授权；授权后可再次点击录音',
        SpeechCapturePhase.recording => '正在录音 · 最长60秒',
        SpeechCapturePhase.transcribing => '正在结束录音并等待最终转写',
        SpeechCapturePhase.ready => '转写待确认，可编辑后使用或取消',
        SpeechCapturePhase.error => _speechError(_capture.errorCode),
      };
  String _speechError(String? code) => switch (code) {
        'permission_denied' ||
        'permission_revoked' =>
          '麦克风未授权或已撤销，可在系统设置允许，或使用文字',
        'no_recognizer' ||
        'unavailable' ||
        'speech_unavailable' =>
          '所选识别服务不可用，请切换已安装服务或使用文字',
        'tts_stop_unconfirmed' => '播报未确认停止，未开启录音；可先停止朗读再重试',
        'no_speech' => '未识别到有效语音，可重试或编辑文字',
        'network_error' => '系统识别服务网络失败，转写未发送',
        'background' => '已离开前台，录音已停止',
        'audio_interrupted' ||
        'audio_route_changed' ||
        'audio_busy' =>
          '音频被中断或设备已切换，录音已停止',
        'utterance_limit' || 'final_result_timeout' => '已到单句时限，未确认的内容不会自动发送',
        'cancelled' => '录音已取消',
        'unsupported_sdk' => '此语音入口需要Android 8或以上版本，可使用文字',
        _ => '识别未完成，转写未发送；可重试或使用文字',
      };
  @override
  Widget build(BuildContext context) {
    final visible = AssistantEntrySurface.canConsume(context);
    if (!visible &&
        !_closing &&
        !_hiddenCancelScheduled &&
        (_autoSend ||
            _capture.capturing ||
            _capture.phase == SpeechCapturePhase.checking ||
            _capture.phase == SpeechCapturePhase.permission)) {
      _hiddenCancelScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _hiddenCancelScheduled = false;
        if (!mounted || _closing || AssistantEntrySurface.canConsume(context)) {
          return;
        }
        if (_autoSend) setState(() => _autoSend = false);
        if (_capture.capturing ||
            _capture.phase == SpeechCapturePhase.checking ||
            _capture.phase == SpeechCapturePhase.permission) {
          unawaited(_capture.cancel());
        }
      });
    }

    final busy = _capture.phase == SpeechCapturePhase.checking ||
        _capture.phase == SpeechCapturePhase.permission;
    final canStart = _capture.capabilities.supported &&
        !busy &&
        !_capture.capturing &&
        (_systemService
            ? _capture.capabilities.system
            : _capture.capabilities.onDevice);
    return PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            _closing = true;
            unawaited(_capture.cancel());
          }
        },
        child: SafeArea(
            child: Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Row(children: [
                        Expanded(
                            child: Text('语音输入',
                                style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                            tooltip: '取消语音输入',
                            onPressed: _cancel,
                            icon: const Icon(Icons.close))
                      ]),
                      const SizedBox(height: 8),
                      const Text('前台单句输入，不是连续会话或后台唤醒。默认设备端识别；本应用不保存原始音频。'),
                      const SizedBox(height: 8),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('改用系统识别服务（可能联网）'),
                          subtitle: const Text(
                              '启用后音频交给系统配置的识别提供方，可能发送到其服务器；不是发送给当前聊天模型。'),
                          value: _systemService,
                          onChanged: !busy &&
                                  !_capture.capturing &&
                                  _capture.capabilities.system
                              ? (value) =>
                                  setState(() => _systemService = value)
                              : null),
                      if (!_capture.capabilities.supported && !busy)
                        const Text('当前Android版本仅提供文字输入，不启动语音录音。')
                      else if (!_capture.capabilities.onDevice &&
                          !_systemService &&
                          !busy)
                        const Text('当前设备端识别不可用。可主动切换可用的系统服务，或直接编辑文字。'),
                      DropdownButtonFormField<String>(
                          initialValue: _language,
                          decoration: const InputDecoration(
                              labelText: '识别语言（由所选服务决定是否支持）'),
                          items: const [
                            DropdownMenuItem(
                                value: 'zh-CN', child: Text('中文普通话')),
                            DropdownMenuItem(
                                value: 'en-SG',
                                child: Text('English (Singapore)')),
                            DropdownMenuItem(
                                value: 'en-US', child: Text('English (US)'))
                          ],
                          onChanged: busy || _capture.capturing
                              ? null
                              : (value) => setState(() => _language = value!)),
                      const SizedBox(height: 12),
                      Semantics(
                          liveRegion: true,
                          child: Text(_status,
                              key: const ValueKey('speech-status'))),
                      const SizedBox(height: 12),
                      TextField(
                          key: const ValueKey('speech-transcript'),
                          controller: _text,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 16000,
                          enabled: !busy && !_capture.capturing,
                          decoration: const InputDecoration(
                              labelText: '转写/待发送文字',
                              hintText: '识别结果可编辑；也可以直接输入',
                              border: OutlineInputBorder()),
                          onChanged: (_) => setState(() {})),
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('本次最终转写后自动发送'),
                          subtitle: const Text(
                              '默认关闭。开启会使用原聊天发送流程及其模型预算；会话或已有草稿变化时仅放入输入框。'),
                          value: _autoSend,
                          onChanged: busy || _capture.capturing
                              ? null
                              : (value) =>
                                  setState(() => _autoSend = value == true)),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        GestureDetector(
                            onLongPressStart: canStart
                                ? (_) => unawaited(_capture.start(
                                    systemService: _systemService,
                                    language: _language))
                                : null,
                            onLongPressEnd: (_) => unawaited(_capture.stop()),
                            child: FilledButton.icon(
                                key: const ValueKey('speech-record'),
                                onPressed: _capture.phase ==
                                        SpeechCapturePhase.recording
                                    ? () => unawaited(_capture.stop())
                                    : canStart
                                        ? () => unawaited(_capture.start(
                                            systemService: _systemService,
                                            language: _language))
                                        : null,
                                icon: Icon(_capture.phase ==
                                        SpeechCapturePhase.recording
                                    ? Icons.stop
                                    : Icons.mic),
                                label: Text(_capture.phase ==
                                        SpeechCapturePhase.recording
                                    ? '结束录音'
                                    : '点击/按住说话'))),
                        OutlinedButton(
                            onPressed: _cancel, child: const Text('取消，不发送')),
                        TextButton(
                            onPressed: TtsService.instance.stop,
                            child: const Text('停止朗读')),
                        FilledButton(
                            key: const ValueKey('speech-use'),
                            onPressed: !busy &&
                                    !_capture.capturing &&
                                    _text.text.trim().isNotEmpty
                                ? _useDraft
                                : null,
                            child: Text(_autoSend ? '确认并发送' : '使用文字')),
                      ]),
                    ])))));
  }
}
