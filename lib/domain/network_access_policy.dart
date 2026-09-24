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

/// A destination that passed policy, plus the address the caller must connect
/// to. Re-resolving the original hostname opens a DNS rebinding window.
class ResolvedEndpoint {
  const ResolvedEndpoint(this.decision, {this.address});

  final NetworkAccessDecision decision;
  final InternetAddress? address;
}

typedef HostAddressLookup = Future<List<InternetAddress>> Function(String host);

class NetworkAccessPolicy {
  const NetworkAccessPolicy({this.lookupHost});

  /// 测试可注入。生产环境为空时使用 [InternetAddress.lookup]。
  final HostAddressLookup? lookupHost;

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
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (_blockedHosts.contains(host) ||
        host.endsWith('.localhost') ||
        host.endsWith('.metadata.google.internal')) {
      return NetworkAccessDecision.deny('禁止访问本机或元数据地址：$host');
    }
    if (_isPrivateHost(host)) {
      return NetworkAccessDecision.deny('禁止访问私网地址：$host');
    }
    return const NetworkAccessDecision.allow();
  }

  /// 在字面量检查之后解析主机名。解析失败或任一地址落在私网时拒绝。
  /// [inspect] 保持同步，供导入校验和不需要 DNS 的调用方使用。
  Future<NetworkAccessDecision> inspectResolved(String rawUrl) async {
    return (await resolveForConnect(rawUrl)).decision;
  }

  /// Resolves and checks [rawUrl]. [ResolvedEndpoint.address] is the address
  /// that was checked; callers must connect to it instead of the hostname.
  Future<ResolvedEndpoint> resolveForConnect(String rawUrl) async {
    final syntactic = inspect(rawUrl);
    if (!syntactic.allowed) return ResolvedEndpoint(syntactic);
    final host = Uri.parse(rawUrl.trim()).host;
    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      return ResolvedEndpoint(syntactic, address: literal);
    }
    final lookup = lookupHost ?? InternetAddress.lookup;
    final List<InternetAddress> addresses;
    try {
      addresses = await lookup(host);
    } catch (_) {
      return ResolvedEndpoint(
        NetworkAccessDecision.deny('无法解析主机名，已拒绝连接：$host'),
      );
    }
    if (addresses.isEmpty) {
      return ResolvedEndpoint(
        NetworkAccessDecision.deny('主机名没有可用地址：$host'),
      );
    }
    for (final address in addresses) {
      if (_isBlockedAddress(address)) {
        return ResolvedEndpoint(
          NetworkAccessDecision.deny('主机名解析到私网地址，已拒绝：$host'),
        );
      }
    }
    return ResolvedEndpoint(syntactic, address: addresses.first);
  }

  bool _isBlockedAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return true;
    final host = address.address.toLowerCase();
    return _blockedHosts.contains(host) || _isPrivateHost(host);
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
      if (bytes.every((byte) => byte == 0) || bytes[0] == 0xff) return true;
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
    return a == 0 ||
        a == 10 ||
        a >= 224 ||
        a == 127 ||
        (a == 192 && b == 0 && bytes[2] == 0) ||
        (a == 198 && (b == 18 || b == 19)) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 192 && b == 168);
  }
}
