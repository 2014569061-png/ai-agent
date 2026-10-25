/// Platform port. Page text and targets are untrusted website data.
abstract interface class BrowserTransport {
  Stream<Map<String, dynamic>> get events;
  Future<Map<String, dynamic>> invoke(String method, Map<String, dynamic> args);
}

class BrowserFailure implements Exception {
  const BrowserFailure(this.code, {this.dispatched = false});
  final String code;
  final bool dispatched;
}

/// Only web navigation is supported; never pass URLs to external applications.
Uri browserUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !{'https', 'http'}.contains(uri.scheme) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      value.length > 4096 ||
      value.contains(RegExp(r'[\x00-\x20\\]'))) {
    throw const BrowserFailure('INVALID_ARGUMENTS');
  }
  return uri;
}
