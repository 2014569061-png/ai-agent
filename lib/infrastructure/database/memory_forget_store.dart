import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'app_database.dart';

/// Content-addressed privacy guard. No original content or conversation IDs.
/// Hashes are not anonymization; treat this table as private user data.
class MemoryForgetStore {
  MemoryForgetStore(this.db);
  final AppDatabase db;
  static String fingerprint(String content) => sha256
      .convert(utf8.encode(content
          .trim()
          .replaceAll(RegExp(r'\s+', unicode: true), ' ')
          .toLowerCase()))
      .toString();
  static String sourceDigest(String? id) => id == null || id.isEmpty
      ? ''
      : sha256.convert(utf8.encode(id)).toString();

  Future<void> rememberForget(Memory memory, {String reason = 'forgotten'}) =>
      put({
        'fingerprint': fingerprint(memory.content),
        'sourceDigest': sourceDigest(memory.sourceConversationId),
        'forgottenAt': DateTime.now().toUtc().toIso8601String(),
        'reason': reason,
      });

  Future<void> put(Map<String, dynamic> row) async {
    validateRow(row);
    await db.customStatement(
        'INSERT INTO memory_forget_rules '
        '(fingerprint, source_digest, forgotten_at, reason) VALUES (?, ?, ?, ?) '
        'ON CONFLICT (fingerprint, source_digest) DO UPDATE SET '
        'forgotten_at = max(forgotten_at, excluded.forgotten_at), reason = excluded.reason',
        [
          row['fingerprint'],
          row['sourceDigest'],
          row['forgottenAt'],
          row['reason']
        ]);
  }

  static void validateRow(Map<String, dynamic> row) {
    final hex = RegExp(r'^[a-f0-9]{64}$');
    if (row['fingerprint'] is! String ||
        !hex.hasMatch(row['fingerprint'] as String) ||
        row['sourceDigest'] is! String ||
        ((row['sourceDigest'] as String).isNotEmpty &&
            !hex.hasMatch(row['sourceDigest'] as String)) ||
        row['forgottenAt'] is! String ||
        (row['forgottenAt'] as String).length > 40 ||
        DateTime.tryParse(row['forgottenAt'] as String) == null ||
        !const {'forgotten', 'corrected', 'disabled'}.contains(row['reason'])) {
      throw const FormatException('遗忘规则格式错误');
    }
  }

  Future<bool> blocks(String content, {String? sourceConversationId}) async {
    final digest = sourceDigest(sourceConversationId);
    return (await db.customSelect(
            'SELECT 1 FROM memory_forget_rules '
            'WHERE fingerprint = ? OR (source_digest <> \'\' AND source_digest = ?) LIMIT 1',
            variables: [
          Variable<String>(fingerprint(content)),
          Variable<String>(digest)
        ]).get())
        .isNotEmpty;
  }

  Future<Set<String>> fingerprints() async => (await db
          .customSelect('SELECT DISTINCT fingerprint FROM memory_forget_rules')
          .get())
      .map((row) => row.read<String>('fingerprint'))
      .toSet();
}

class MemoryForgottenException implements Exception {
  const MemoryForgottenException();
}
