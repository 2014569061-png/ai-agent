import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 终端 SSH 会话凭据与连接参数配置。
class SSHTerminalConfig {
  const SSHTerminalConfig({
    this.host = '127.0.0.1',
    this.port = 8022,
    this.username = '',
    this.password,
    this.privateKey,
    this.label = 'Termux 本地 (127.0.0.1:8022)',
  });

  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String label;

  bool get isLocalTermux =>
      host == '127.0.0.1' || host == 'localhost' || port == 8022;

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'privateKey': privateKey,
        'label': label,
      };

  factory SSHTerminalConfig.fromJson(Map<String, dynamic> json) {
    return SSHTerminalConfig(
      host: json['host'] as String? ?? '127.0.0.1',
      port: (json['port'] as num?)?.toInt() ?? 8022,
      username: json['username'] as String? ?? '',
      password: json['password'] as String?,
      privateKey: json['privateKey'] as String?,
      label: json['label'] as String? ?? 'Termux 本地 (127.0.0.1:8022)',
    );
  }

  SSHTerminalConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? privateKey,
    String? label,
  }) {
    return SSHTerminalConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      label: label ?? this.label,
    );
  }
}

/// 安全存储本地 Termux 及 SSH 配置。
class TermuxSSHStorage {
  TermuxSSHStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _configKey = 'nexus_terminal_ssh_config';
  final FlutterSecureStorage _storage;

  Future<SSHTerminalConfig> loadConfig() async {
    try {
      final raw = await _storage.read(key: _configKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final config = SSHTerminalConfig.fromJson(map);
        // Older builds wrote the placeholder "termux" when the user left the
        // field untouched. Treat it as unset for the local Termux endpoint so
        // the next connection asks for the real `whoami` value.
        final isLocalHost =
            config.host == '127.0.0.1' || config.host == 'localhost';
        if (isLocalHost && config.port == 8022 && config.username == 'termux') {
          return config.copyWith(username: '');
        }
        return config;
      }
    } catch (_) {
      // 容错降级为默认
    }
    return const SSHTerminalConfig();
  }

  Future<void> saveConfig(SSHTerminalConfig config) async {
    await _storage.write(
      key: _configKey,
      value: jsonEncode(config.toJson()),
    );
  }
}
