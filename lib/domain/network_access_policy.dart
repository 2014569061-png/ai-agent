import 'dart:io';

/// Shared HTTP destination policy for plugin tools and other outbound calls.
class NetworkAccessDecision {
  const NetworkAccessDecision.allow()
      : allowed = true,
        reason = '';
  const NetworkAccessDecision.deny(this.reason) : allowed = false;

  final bool allowed;
  final String reason;
}

class NetworkAccessPolicy {
  const NetworkAccessPolicy();

  static final _blockedHosts = {
    'localhost',
    '127.0.0.1',
    '0.0.0.0',
    '::1',
    'metadata.google.internal',
    'metadata',
  };

  NetworkAccessDecision inspect(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      return const NetworkAccessDecision.deny('URL 为空');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const NetworkAccessDecision.deny('URL 无效');
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return NetworkAccessDecision.deny('不支持的协议：${uri.scheme}');
    }
    final host = uri.host.toLowerCase();
    if (_blockedHosts.contains(host) || host.endsWith('.localhost')) {
      return NetworkAccessDecision.deny('禁止访问本机或元数据地址：$host');
    }
    if (_isPrivateHost(host)) {
      return NetworkAccessDecision.deny('禁止访问私网地址：$host');
    }
    return const NetworkAccessDecision.allow();
  }

  bool _isPrivateHost(String host) {
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    if (address.isLoopback || address.isLinkLocal) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length >= 4) {
      return _isPrivateIpv4(bytes);
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length >= 16) {
      if (_isIpv4Mapped(bytes)) {
        return _isPrivateIpv4(bytes.sublist(12, 16));
      }
      // Unique local addresses (fc00::/7) and site-local fec0::/10.
      return (bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0xc0);
    }
    return false;
  }

  bool _isIpv4Mapped(List<int> bytes) {
    for (var i = 0; i < 10; i++) {
      if (bytes[i] != 0) return false;
    }
    return bytes[10] == 0xff && bytes[11] == 0xff;
  }

  bool _isPrivateIpv4(List<int> bytes) {
    if (bytes.length < 4) return false;
    final a = bytes[0];
    final b = bytes[1];
    return a == 10 ||
        a == 127 ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }
}
