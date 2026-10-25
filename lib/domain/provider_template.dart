import 'dart:convert';

/// Untrusted configuration data, never a credential or permission grant.
/// Parsing is deliberately pure: no storage, DNS, HTTP or capability probes.
class ProviderTemplate {
  const ProviderTemplate._(
      {required this.name,
      required this.baseUrl,
      required this.model,
      required this.protocol,
      required this.contextTokens});

  final String name;
  final Uri baseUrl;
  final String model;
  final String protocol;
  final int contextTokens;

  static const protocols = {'openaiCompatible', 'anthropic', 'gemini', 'proxy'};
  static const _fields = {
    'schemaVersion',
    'name',
    'baseUrl',
    'model',
    'protocol',
    'contextTokens'
  };

  factory ProviderTemplate.parse(String text) {
    if (utf8.encode(text).length > 16384) {
      throw const FormatException('模板过大，最多支持 16 KiB');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('请输入有效的 JSON 模板');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('模板必须是 JSON 对象');
    }
    if (decoded.keys.any((key) => !_fields.contains(key))) {
      throw const FormatException('模板含未知字段；不得包含密钥、请求头、授权或执行命令');
    }
    if (decoded['schemaVersion'] is! int || decoded['schemaVersion'] != 1) {
      throw const FormatException('不支持的模板版本，需要 schemaVersion: 1');
    }
    String field(String key, int maxLength) {
      final value = decoded is Map<String, dynamic> ? decoded[key] : null;
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > maxLength ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw FormatException('模板字段 $key 无效');
      }
      return value.trim();
    }

    final name = field('name', 80);
    final model = field('model', 200);
    final protocol = field('protocol', 40);
    if (!protocols.contains(protocol)) {
      throw const FormatException('不支持的模型协议');
    }
    final uri = Uri.tryParse(field('baseUrl', 2048));
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException('端点须为 HTTP(S) 地址，不得含凭证、查询参数或片段');
    }
    if (uri.scheme == 'http' && !_isLocalHost(uri.host)) {
      throw const FormatException('公网端点必须使用 HTTPS；HTTP 仅用于本机或局域网');
    }
    final tokens = decoded['contextTokens'] ?? 32000;
    if (tokens is! int || tokens < 4000 || tokens > 2000000) {
      throw const FormatException('contextTokens 须为 4000–2000000 的整数');
    }
    return ProviderTemplate._(
        name: name,
        baseUrl: uri,
        model: model,
        protocol: protocol,
        contextTokens: tokens);
  }

  static bool _isLocalHost(String host) {
    host = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
    if (host == 'localhost' || host == '::1') return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((n) => n == null || n < 0 || n > 255)) return false;
    return octets[0] == 127 ||
        octets[0] == 10 ||
        (octets[0] == 192 && octets[1] == 168) ||
        (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31) ||
        (octets[0] == 169 && octets[1] == 254);
  }

  bool get isLoopback {
    final host = baseUrl.host.replaceAll('[', '').replaceAll(']', '');
    return host == 'localhost' || host == '::1' || host.startsWith('127.');
  }

  /// Parses either a raw JSON template or a `nexus-provider://template?payload=...`
  /// QR code URI payload (Base64URL or percent-encoded JSON).
  factory ProviderTemplate.parseQrOrJson(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('nexus-provider://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null ||
          uri.host != 'template' ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment) {
        throw const FormatException('无效的二维码模板链接');
      }
      final payload = uri.queryParameters['payload'];
      if (payload == null || payload.trim().isEmpty) {
        throw const FormatException('二维码模板缺少 payload 参数');
      }
      String decodedJson;
      try {
        final normalized = base64Url.normalize(payload.trim());
        decodedJson = utf8.decode(base64Url.decode(normalized));
      } catch (_) {
        decodedJson = Uri.decodeComponent(payload.trim());
      }
      return ProviderTemplate.parse(decodedJson);
    }
    return ProviderTemplate.parse(trimmed);
  }

  String toQrUri() {
    final raw = utf8.encode(jsonEncode(toJson()));
    final encoded = base64UrlEncode(raw).replaceAll('=', '');
    return 'nexus-provider://template?payload=$encoded';
  }

  Map<String, Object> toJson() => {
        'schemaVersion': 1,
        'name': name,
        'baseUrl': baseUrl.toString(),
        'model': model,
        'protocol': protocol,
        'contextTokens': contextTokens,
      };
}

enum DeviceCapabilityTier {
  localCompact('local_compact', '轻量端侧/局域网模型'),
  balancedCloud('balanced_cloud', '均衡云端推理（推荐）'),
  flagshipCloud('flagship_cloud', '长上下文旗舰模型');

  const DeviceCapabilityTier(this.wireName, this.label);
  final String wireName;
  final String label;
}

class DeviceCapabilityProfile {
  const DeviceCapabilityProfile({
    required this.cpuCores,
    required this.estimatedRamGb,
    required this.recommendedTier,
    required this.recommendedContextTokens,
    required this.hostingDecision,
  });

  final int cpuCores;
  final int estimatedRamGb;
  final DeviceCapabilityTier recommendedTier;
  final int recommendedContextTokens;
  final String hostingDecision;

  factory DeviceCapabilityProfile.evaluate({
    required int cpuCores,
    required int estimatedRamGb,
  }) {
    if (estimatedRamGb >= 12 && cpuCores >= 8) {
      return DeviceCapabilityProfile(
        cpuCores: cpuCores,
        estimatedRamGb: estimatedRamGb,
        recommendedTier: DeviceCapabilityTier.flagshipCloud,
        recommendedContextTokens: 128000,
        hostingDecision: '设备内存充足，支持长上下文云端模型或局域网自托管推理',
      );
    }
    if (estimatedRamGb >= 6 && cpuCores >= 4) {
      return DeviceCapabilityProfile(
        cpuCores: cpuCores,
        estimatedRamGb: estimatedRamGb,
        recommendedTier: DeviceCapabilityTier.balancedCloud,
        recommendedContextTokens: 64000,
        hostingDecision: '建议采用云端 API 托管推理（64K 上下文预算）以兼顾响应速度与功耗',
      );
    }
    return DeviceCapabilityProfile(
      cpuCores: cpuCores,
      estimatedRamGb: estimatedRamGb,
      recommendedTier: DeviceCapabilityTier.localCompact,
      recommendedContextTokens: 16000,
      hostingDecision: '建议采用远端轻量模型并控制单次上下文在 16K 以内，避免本机内存压力',
    );
  }

  ProviderTemplate buildRecommendedTemplate() {
    return ProviderTemplate.parse(
      jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'name': '推荐配置（${recommendedTier.label}）',
        'baseUrl': 'https://api.example.com/v1',
        'model': switch (recommendedTier) {
          DeviceCapabilityTier.flagshipCloud => 'deepseek-reasoner',
          DeviceCapabilityTier.balancedCloud => 'deepseek-chat',
          DeviceCapabilityTier.localCompact => 'qwen-turbo',
        },
        'protocol': 'openaiCompatible',
        'contextTokens': recommendedContextTokens,
      }),
    );
  }
}
