import 'package:flutter/foundation.dart';
import 'dart:async';
import 'assistant_entry.dart';
import '../../domain/assistant_page_context.dart';
import '../notifications/notification_intent.dart';

/// External links stage navigation/prefill only; they never send or cancel a run.
class DeepLinkService extends ChangeNotifier {
  DeepLinkService._();

  /// Isolated window/embedding stream; does not subscribe to platform links.
  DeepLinkService.detached();
  static final DeepLinkService instance = DeepLinkService._();
  String? pendingPrompt;
  bool pendingNewAgent = false, pendingMemory = false, pendingAssistant = false;
  int _revision = 0;
  int get revision => _revision;
  int _legacyRevision = 0;
  int get legacyRevision => _legacyRevision;
  int? _failedRevision;
  final _external = <AssistantEntry>[];
  final _failedExternal = <String>{};
  int _externalSequence = 0;
  Timer? _expiry;
  Object? _claimOwner;
  String? _claimedEntry;
  static const maxExternalEntries = 8;
  static const maxStagedCodeUnits = 16 * 1024 * 1024;
  bool get hasLegacyPending =>
      pendingPrompt != null ||
      pendingNewAgent ||
      pendingMemory ||
      pendingAssistant;
  AssistantEntry? get pendingExternal =>
      _external.isEmpty ? null : _external.first;
  int get externalCount => _external.length;
  bool claimExternal(String id, Object owner) {
    if (hasLegacyPending ||
        pendingExternal?.id != id ||
        _claimOwner != null ||
        _failedExternal.contains(id)) {
      return false;
    }
    _claimedEntry = id;
    _claimOwner = owner;
    return true;
  }

  bool ownsExternal(String id, Object owner) =>
      _claimedEntry == id &&
      identical(_claimOwner, owner) &&
      pendingExternal?.id == id;
  void releaseExternal(Object owner) {
    if (identical(_claimOwner, owner)) {
      _claimOwner = null;
      _claimedEntry = null;
    }
  }

  void _invalidateMissingClaim() {
    if (_external.every((entry) => entry.id != _claimedEntry)) {
      _claimOwner = null;
      _claimedEntry = null;
    }
  }

  bool get consumptionReady => hasLegacyPending
      ? _failedRevision != _legacyRevision
      : pendingExternal != null &&
          !_failedExternal.contains(pendingExternal!.id);

  void _externalChanged({required bool accepted}) {
    _revision++;
    lastEventAccepted = accepted;
    notifyListeners();
  }

  bool _enqueue(AssistantEntry entry) {
    if (_external.any((item) => item.id == entry.id)) {
      if (entry.kind == AssistantEntryKind.notification) {
        _failedExternal.remove(entry.id);
      }
      _externalChanged(accepted: true);
      return true;
    }
    if (_external.length >= maxExternalEntries ||
        _external.fold<int>(0, (sum, item) => sum + item.size) + entry.size >
            maxStagedCodeUnits) {
      _reject('待处理入口已满或内容过大，请先处理现有内容后重新分享');
      return false;
    }
    _external.add(entry);
    _scheduleExpiry();
    _externalChanged(accepted: true);
    return true;
  }

  bool enqueueShare(List<String> values) {
    final items = values
        .where((value) =>
            value.trim().isNotEmpty &&
            Uri.tryParse(value.trim())?.scheme.toLowerCase() != 'nexus')
        .toList();
    if (items.isEmpty) return false;
    final textItems = items.where((value) => !value.startsWith('data:image/'));
    final textLength =
        textItems.fold<int>(0, (sum, value) => sum + value.length) +
            (textItems.isEmpty ? 0 : (textItems.length - 1) * 2);
    if (items.length > 12 || textLength > 16000) {
      _reject('分享内容超过支持的大小或数量，请减少内容后重新分享');
      return false;
    }
    return _enqueue(
        AssistantEntry.share('share:${++_externalSequence}', items));
  }

  bool enqueueNotification(NotificationIntent intent) {
    if (NotificationIntent.parse('${intent.kind.name}:${intent.id}') !=
        intent) {
      _reject('通知入口格式无效，现有内容未改动');
      return false;
    }
    return _enqueue(AssistantEntry.notification(
        'notification:${intent.kind.name}:${intent.id}', intent));
  }

  bool enqueuePageContext(AssistantPageContext context) {
    if (context.isExpired()) return false;
    return _enqueue(AssistantEntry.pageContext(context));
  }

  void discardPageContexts({String? id}) {
    final removed = _external
        .where((item) =>
            item.pageContext != null &&
            (id == null || item.pageContext!.id == id))
        .toList();
    if (removed.isEmpty) return;
    _external.removeWhere(removed.contains);
    _invalidateMissingClaim();
    for (final item in removed) {
      _failedExternal.remove(item.id);
    }
    _scheduleExpiry();
    _externalChanged(accepted: false);
  }

  bool acknowledgeExternal(String id) {
    if (pendingExternal?.id != id) return false;
    _external.removeAt(0);
    _claimOwner = null;
    _claimedEntry = null;
    _failedExternal.remove(id);
    _scheduleExpiry();
    _externalChanged(accepted: false);
    return true;
  }

  void markExternalFailed(String id) {
    if (pendingExternal?.id == id) _failedExternal.add(id);
  }

  bool retryExternal(String id) {
    if (pendingExternal?.id != id || !_failedExternal.remove(id)) return false;
    _externalChanged(accepted: true);
    return true;
  }

  void discardExpiredContexts([DateTime? now]) {
    final removed = _external
        .where((item) => item.pageContext?.isExpired(now) ?? false)
        .toList();
    if (removed.isEmpty) return;
    _external.removeWhere((item) => removed.contains(item));
    _invalidateMissingClaim();
    for (final item in removed) {
      _failedExternal.remove(item.id);
    }
    _scheduleExpiry();
    _externalChanged(accepted: false);
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    final dates = _external
        .map((item) => item.pageContext?.remainingLifetime)
        .whereType<Duration>()
        .toList()
      ..sort();
    if (dates.isNotEmpty) {
      final delay = dates.first;
      _expiry = Timer(
          delay.isNegative ? Duration.zero : delay, discardExpiredContexts);
    }
  }

  void markConsumptionFailed(int expectedRevision) {
    if (expectedRevision == _legacyRevision && hasLegacyPending) {
      _failedRevision = _legacyRevision;
    }
  }

  bool retryPending(int expectedRevision) {
    if (expectedRevision != _legacyRevision || !hasLegacyPending) return false;
    _failedRevision = null;
    _revision++;
    _legacyRevision = _revision;
    lastEventAccepted = true;
    notifyListeners();
    return true;
  }

  bool lastEventAccepted = false;
  String? _rejection;
  bool get hasRejection => _rejection != null;
  String? takeRejection() {
    final value = _rejection;
    _rejection = null;
    return value;
  }

  void _reject(String message) {
    lastEventAccepted = false;
    _rejection = message;
    notifyListeners();
  }

  void reportInputFailure(String message) => _reject(message);

  void handleUri(Uri uri) {
    try {
      if (uri.toString().length > 20000 ||
          uri.scheme != 'nexus' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.fragment.isNotEmpty ||
          (uri.path.isNotEmpty && uri.path != '/')) {
        _reject('外部入口格式不受支持，现有内容未改动');
        return;
      }
      final host = uri.host;
      if (!const {'new-chat', 'new-agent', 'memory', 'assistant'}
          .contains(host)) {
        _reject('外部入口不受支持，现有内容未改动');
        return;
      }
      final query = uri.queryParametersAll;
      if (query.keys.any((key) => key != 'prompt' || host != 'new-chat') ||
          query.values.any((values) => values.length != 1)) {
        _reject('入口参数不受支持，现有内容未改动');
        return;
      }
      final prompt =
          host == 'new-chat' ? (query['prompt']?.single ?? '') : null;
      if (prompt != null && prompt.length > 16000) {
        _reject('预填内容超过16000字符，未接收');
        return;
      }
      if (host == 'assistant' && hasPending) {
        // Navigation can bring a staged share/context into view without
        // replacing it, clearing a failed entry or introducing another slot.
        _externalChanged(accepted: true);
        return;
      }
      final duplicate = switch (host) {
        'new-chat' => pendingPrompt == prompt &&
            !pendingNewAgent &&
            !pendingMemory &&
            !pendingAssistant,
        'new-agent' => pendingNewAgent &&
            pendingPrompt == null &&
            !pendingMemory &&
            !pendingAssistant,
        'memory' => pendingMemory &&
            pendingPrompt == null &&
            !pendingNewAgent &&
            !pendingAssistant,
        _ => pendingAssistant &&
            pendingPrompt == null &&
            !pendingNewAgent &&
            !pendingMemory,
      };
      if (hasPending && !duplicate) {
        _reject('已有待处理入口，新的入口未覆盖它');
        return;
      }
      switch (host) {
        case 'new-chat':
          pendingPrompt = prompt;
        case 'new-agent':
          pendingNewAgent = true;
        case 'memory':
          pendingMemory = true;
        case 'assistant':
          pendingAssistant = true;
      }
      _failedRevision = null;
      lastEventAccepted = true;
      _rejection = null;
      _revision++;
      _legacyRevision = _revision;
      notifyListeners();
    } catch (_) {
      _reject('入口参数无法解析，现有内容未改动');
    }
  }

  bool get hasPending => hasLegacyPending || _external.isNotEmpty;
  String? drainPrompt() {
    final value = pendingPrompt;
    pendingPrompt = null;
    return value;
  }

  bool drainNewAgent() {
    final value = pendingNewAgent;
    pendingNewAgent = false;
    return value;
  }

  bool drainMemory() {
    final value = pendingMemory;
    pendingMemory = false;
    return value;
  }

  bool drainAssistant() {
    final value = pendingAssistant;
    pendingAssistant = false;
    return value;
  }

  @visibleForTesting
  void reset() {
    pendingPrompt = null;
    pendingNewAgent = false;
    pendingMemory = false;
    pendingAssistant = false;
    _rejection = null;
    lastEventAccepted = false;
    _revision = 0;
    _legacyRevision = 0;
    _failedRevision = null;
    _external.clear();
    _claimOwner = null;
    _claimedEntry = null;
    _failedExternal.clear();
    _expiry?.cancel();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }
}
