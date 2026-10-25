import '../infrastructure/share/deep_link_service.dart';

/// A voice sheet may outlive an external entry or conversation restoration.
/// Even draining an entry does not restore permission to send that old draft.
class SpeechSubmissionGuard {
  SpeechSubmissionGuard.capture(DeepLinkService links)
      : _revision = links.revision,
        _hadPendingEntry = links.hasPending;

  final int _revision;
  final bool _hadPendingEntry;

  bool allowsAutoSend({
    required DeepLinkService links,
    required bool requested,
    required bool initiallyEmpty,
    required bool draftUnchanged,
    required bool attachmentsEmpty,
    required bool contextAvailable,
  }) =>
      requested &&
      !_hadPendingEntry &&
      !links.hasPending &&
      links.revision == _revision &&
      initiallyEmpty &&
      draftUnchanged &&
      attachmentsEmpty &&
      contextAvailable;
}
