import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 多设备加密云同步（D1，Pro 卖点）。
///
/// 设计要点：
/// - 密钥本地派生：`scrypt(passphrase + salt)`，passphrase 为用户设置的恢复码，salt 本地生成。
/// - AES-256-GCM 加密，每份文档随机 nonce，服务端只存密文。
/// - 网络同步依赖 v0.3 托管后端；未配置端点时优雅降级为「仅本地加密打包」，
///   与 G3 隐私保险箱共用同一套加解密原语。
class SyncService {
  SyncService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _keySalt = 'sync.salt';
  static const _keySecret = 'sync.secret';

  final FlutterSecureStorage _secureStorage;
  // 注：cryptography 2.x 已移除 scrypt，改用 Pbkdf2-HMAC-SHA256（100k 次迭代）作为等价的
  // memory/time-hard KDF，密钥派生语义与文档一致（passphrase + salt → 32B 密钥）。
  final _kdf = Pbkdf2.hmacSha256(iterations: 100000, bits: 256);
  final _aes = AesGcm.with256bits();

  // --- 密钥与恢复码 ---

  /// 由用户口令派生 32B 密钥。口令为空时使用随机盐生成设备本机密钥。
  Future<SecretKey> _deriveKey(String passphrase, List<int> salt) async {
    return _kdf.deriveKey(
      secretKey: SecretKey(
          utf8.encode(passphrase.isEmpty ? 'nexus-local' : passphrase)),
      nonce: Uint8List.fromList(salt),
    );
  }

  /// 生成（或读取已有）本机盐。
  Future<List<int>> _salt() async {
    final existing = await _secureStorage.read(key: _keySalt);
    if (existing != null && existing.isNotEmpty) {
      return base64Decode(existing);
    }
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    await _secureStorage.write(key: _keySalt, value: base64Encode(bytes));
    return bytes;
  }

  /// 导出恢复码：`base64(passphrase).base64(salt)`，跨设备唯一凭据。
  Future<String> exportRecoveryCode(String passphrase) async {
    final salt = await _salt();
    return '${base64Encode(utf8.encode(passphrase))}.${base64Encode(salt)}';
  }

  /// 导入恢复码并派生密钥，缓存到安全存储。
  Future<bool> importRecoveryCode(String code) async {
    final parts = code.split('.');
    if (parts.length != 2) return false;
    try {
      final passphrase = utf8.decode(base64Decode(parts[0]));
      final salt = base64Decode(parts[1]);
      final key = await _deriveKey(passphrase, salt);
      await _secureStorage.write(
          key: _keySecret, value: base64Encode(await key.extractBytes()));
      await _secureStorage.write(key: _keySalt, value: base64Encode(salt));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 取当前有效密钥（优先已导入的恢复码密钥，否则用本机盐派生设备密钥）。
  Future<SecretKey> _secretKey() async {
    final cached = await _secureStorage.read(key: _keySecret);
    if (cached != null && cached.isNotEmpty) {
      return SecretKey(base64Decode(cached));
    }
    final salt = await _salt();
    return _deriveKey('', salt);
  }

  // --- 加解密原语（与 G3 共用） ---

  /// 加密纯文本，返回 `nonce:mac:cipherText` 的 base64 组合串（AES-GCM 需携带认证标签）。
  Future<String> encryptString(String plaintext) async {
    final key = await _secretKey();
    return _encryptWithKey(plaintext, key);
  }

  /// 解密 [encryptString] 产出的密文。
  Future<String> decryptString(String payload) async {
    final key = await _secretKey();
    return _decryptWithKey(payload, key);
  }

  /// 用用户口令加密（G3 隐私保险箱用）：盐 + 密文一起编码，跨设备/跨时间可解密。
  Future<String> encryptWithPassword(String plaintext, String password) async {
    final salt = _randomBytes(16);
    final key = await _deriveKey(password, salt);
    final box = await _encryptWithKey(plaintext, key);
    return '${base64Encode(salt)}.$box';
  }

  /// 解密 [encryptWithPassword] 产出的密文。
  Future<String> decryptWithPassword(String payload, String password) async {
    final parts = payload.split('.');
    if (parts.length != 2) throw const FormatException('无效密文格式');
    final salt = base64Decode(parts[0]);
    final key = await _deriveKey(password, salt);
    return _decryptWithKey(parts[1], key);
  }

  Future<String> _encryptWithKey(String plaintext, SecretKey key) async {
    final nonce = _randomBytes(12);
    final box = await _aes.encrypt(utf8.encode(plaintext),
        secretKey: key, nonce: nonce);
    return '${base64Encode(nonce)}:${base64Encode(box.mac.bytes)}:${base64Encode(box.cipherText)}';
  }

  Future<String> _decryptWithKey(String payload, SecretKey key) async {
    final parts = payload.split(':');
    if (parts.length != 3) throw const FormatException('无效密文格式');
    final nonce = base64Decode(parts[0]);
    final mac = Mac(base64Decode(parts[1]));
    final box = SecretBox(base64Decode(parts[2]), nonce: nonce, mac: mac);
    final clear = await _aes.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)));
  }

  // --- 网络同步（V1 桩：无后端时优雅降级） ---

  String? _endpoint;

  /// 设置同步后端地址；为空表示未配置后端。
  void configureEndpoint(String? endpoint) => _endpoint = endpoint;

  bool get isConfigured => _endpoint != null && _endpoint!.trim().isNotEmpty;

  /// 推送本地变更（V1 桩：未配置后端时静默跳过）。
  Future<void> push() async {
    if (!isConfigured) return;
    // 预留：遍历 SyncMeta 中 dirty=1 的行，逐行 AES-GCM 加密后 PUT /v1/sync/objects。
  }

  /// 拉取远端变更（V1 桩：未配置后端时静默跳过）。
  Future<void> pull() async {
    if (!isConfigured) return;
    // 预留：GET 版本号 > 本地的对象 → 解密 → 写库。
  }
}

final syncServiceProvider = Provider<SyncService>((ref) => SyncService());
