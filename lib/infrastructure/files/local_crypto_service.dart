import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 本地加解密服务：为隐私保险箱、本地数据备份与定时任务快照提供加解密原语。
///
/// 前身是 [SyncService]（多设备加密云同步，D1 卖点）。多设备云同步已于
/// 2026-09-10 移除，本类保留其**本地加解密能力**：
/// - [encryptWithPassword] / [decryptWithPassword]：用户口令派生密钥（G3 隐私保险箱）
/// - [encryptString] / [decryptString]：设备本机密钥（本地备份、定时任务快照）
///
/// 密码学实现：Pbkdf2-HMAC-SHA256（100k 次迭代）派生密钥 + AES-256-GCM，
/// 每份密文携带随机 nonce 与认证标签。
///
/// 注意：Secure Storage 中的密钥名沿用旧的 `sync.salt` / `sync.secret`，
/// 这是**有意保留**——已有设备上用设备密钥加密的备份/快照依赖它们，改名会导致无法解密。
class LocalCryptoService {
  LocalCryptoService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // 沿用旧名以保持既有加密数据的可解密性（见类注释）。
  static const _keySalt = 'sync.salt';
  static const _keySecret = 'sync.secret';

  final FlutterSecureStorage _secureStorage;
  // 注：cryptography 2.x 已移除 scrypt，改用 Pbkdf2-HMAC-SHA256（100k 次迭代）作为等价的
  // memory/time-hard KDF，密钥派生语义与文档一致（passphrase + salt → 32B 密钥）。
  final _kdf = Pbkdf2.hmacSha256(iterations: 100000, bits: 256);
  final _aes = AesGcm.with256bits();

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

  /// 取当前有效密钥（设备本机密钥，缓存于安全存储）。
  Future<SecretKey> _secretKey() async {
    final cached = await _secureStorage.read(key: _keySecret);
    if (cached != null && cached.isNotEmpty) {
      return SecretKey(base64Decode(cached));
    }
    final salt = await _salt();
    return _deriveKey('', salt);
  }

  // --- 加解密原语 ---

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
}
