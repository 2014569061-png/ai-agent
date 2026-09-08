import 'dart:collection';

/// Chooses when a completed reply should defer rich-text parsing.
///
/// The decision is cached by content fingerprint so rebuilding a chat list does
/// not repeatedly recalculate the same rendering policy.
class MarkdownRenderPolicy {
  MarkdownRenderPolicy._();

  static const baseThreshold = 4000;
  static const _maxEntries = 128;
  static final LinkedHashMap<String, bool> _decisions =
      LinkedHashMap<String, bool>();

  static bool shouldDefer(String data, double viewportWidth) {
    final threshold = thresholdFor(viewportWidth);
    final key = '${data.hashCode}:${data.length}:$threshold';
    final cached = _decisions.remove(key);
    if (cached != null) {
      _decisions[key] = cached;
      return cached;
    }

    final decision = data.length > threshold;
    _decisions[key] = decision;
    if (_decisions.length > _maxEntries) {
      _decisions.remove(_decisions.keys.first);
    }
    return decision;
  }

  static int thresholdFor(double viewportWidth) {
    if (viewportWidth < 380) return 3000;
    if (viewportWidth >= 600) return 5000;
    return baseThreshold;
  }

  static void clearCache() => _decisions.clear();
}
