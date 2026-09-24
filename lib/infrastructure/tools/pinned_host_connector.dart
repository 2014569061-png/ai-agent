import 'dart:io';

/// Remembers a DNS answer that already passed the private-network check and
/// connects later sockets to that address. A second lookup of the original
/// hostname can be rebound to an internal address.
class PinnedHostConnector {
  PinnedHostConnector({
    this.resolveAddress,
    this.requirePin = false,
  });

  final Map<String, InternetAddress> _pins = {};
  final Future<InternetAddress?> Function(Uri uri)? resolveAddress;
  final bool requirePin;

  void pin(String host, InternetAddress address) {
    _pins[host.toLowerCase()] = address;
  }

  InternetAddress? pinFor(String host) => _pins[host.toLowerCase()];

  HttpClient createClient() {
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null) {
        throw const SocketException('Pinned connections do not allow proxies');
      }
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final pinned = pinFor(uri.host) ?? await resolveAddress?.call(uri);
      if (pinned == null && requirePin) {
        throw SocketException('No approved address for ${uri.host}');
      }
      return Socket.startConnect(pinned ?? uri.host, port);
    };
    return client;
  }
}
