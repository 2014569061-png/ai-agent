import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import '../domain/assistant_page_context.dart';
import '../infrastructure/share/deep_link_service.dart';
import 'assistant_role.dart';

/// Reads only a user-confirmed, process-local native handoff. It cannot request
/// a capture, access a screen or start a model. Delivery is acknowledged by ID.
class AssistantContextIntake with WidgetsBindingObserver {
  AssistantContextIntake._();
  static final instance = AssistantContextIntake._();
  static const _channel = MethodChannel('nexus/assistant_context');
  bool _initialized = false, _checking = false, _hint = true;
  int _signalRevision = 0;

  void init() {
    if (_initialized ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    DeepLinkService.instance.addListener(_onEntriesChanged);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pending') {
        _hint = true;
        _signalRevision++;
        await _check();
      }
    });
    unawaited(_check());
  }

  void _onEntriesChanged() {
    if (!_checking) unawaited(_check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _hint = true;
      _signalRevision++;
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (_checking ||
        !_hint ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _checking = true;
    final signal = _signalRevision;
    final entries = DeepLinkService.instance;
    try {
      final status = await const PlatformAssistantRoleSource()
          .status()
          .timeout(const Duration(seconds: 5));
      if (!status.connected || status.locked) {
        entries.discardPageContexts();
        return;
      }
      final raw = await _channel
          .invokeMapMethod<Object?, Object?>('peek')
          .timeout(const Duration(seconds: 5));
      if (raw == null) {
        if (signal == _signalRevision) _hint = false;
        return;
      }
      final context = AssistantPageContext.fromMap(raw);
      if (entries.enqueuePageContext(context)) {
        final acknowledged = await _channel.invokeMethod<bool>('acknowledge',
            {'id': context.id}).timeout(const Duration(seconds: 5));
        if (acknowledged != true) entries.discardPageContexts(id: context.id);
        if (signal == _signalRevision) _hint = false;
      }
    } catch (_) {
      // Native ownership remains bounded by its own expiry. Retry only on a
      // subsequent real lifecycle/entry event, never on every rendered frame.
    } finally {
      _checking = false;
      // A native/lifecycle signal arriving during an awaited peek or ACK must
      // survive that older check. Recheck once for the newer signal, not every
      // frame or on our own queue's rejection notification.
      if (_hint && signal != _signalRevision) unawaited(_check());
    }
  }
}
