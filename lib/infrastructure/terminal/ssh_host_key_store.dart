import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SshHostKeyDecision {
  trusted,
  trustedNew,
  rejected,
  mismatch,
}

/// 已信任的 SSH 主机密钥。实现可替换，便于测试，也避免会话直接依赖存储细节。
abstract class SshKnownHostStore {
  Future<String?> readFingerprint(String host, int port);
  Future<void> saveFingerprint(String host, int port, String fingerprint);
}

class SecureSshKnownHostStore implements SshKnownHostStore {
  SecureSshKnownHostStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'nexus_ssh_known_hosts';
  final FlutterSecureStorage _storage;

  static String identity(String host, int port) =>
      '$port|${host.trim().toLowerCase()}';

  Future<Map<String, String>> _load() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final entry in decoded.entries)
        if (entry.value is String) entry.key.toString(): entry.value as String,
    };
  }

  @override
  Future<String?> readFingerprint(String host, int port) async {
    final all = await _load();
    return all[identity(host, port)];
  }

  @override
  Future<void> saveFingerprint(
      String host, int port, String fingerprint) async {
    final all = await _load();
    all[identity(host, port)] = fingerprint;
    await _storage.write(key: storageKey, value: jsonEncode(all));
  }
}

class SshHostKeyVerifier {
  SshHostKeyVerifier(this._store);

  final SshKnownHostStore _store;

  /// 首次见到的密钥默认信任并保存（TOFU）。[confirmUnknown] 可改为先询问。
  /// 已保存的密钥一旦变化一律拒绝。存储读写失败也拒绝，不在无法核对时放行。
  Future<SshHostKeyDecision> decide({
    required String host,
    required int port,
    required String fingerprint,
    Future<bool> Function(String fingerprint)? confirmUnknown,
  }) async {
    if (fingerprint.isEmpty) return SshHostKeyDecision.rejected;
    final String? known;
    try {
      known = await _store.readFingerprint(host, port);
    } catch (_) {
      return SshHostKeyDecision.rejected;
    }
    if (known == null || known.isEmpty) {
      final accepted =
          confirmUnknown == null ? true : await confirmUnknown(fingerprint);
      if (!accepted) return SshHostKeyDecision.rejected;
      try {
        await _store.saveFingerprint(host, port, fingerprint);
      } catch (_) {
        return SshHostKeyDecision.rejected;
      }
      return SshHostKeyDecision.trustedNew;
    }
    if (known == fingerprint) return SshHostKeyDecision.trusted;
    return SshHostKeyDecision.mismatch;
  }
}
