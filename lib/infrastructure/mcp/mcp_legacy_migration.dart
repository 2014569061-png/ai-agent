import '../database/app_database.dart';

/// Database authority must survive an empty restore/clear, otherwise legacy
/// preferences could silently resurrect servers on the next service instance.
abstract final class McpLegacyMigration {
  static Future<bool> isComplete(AppDatabase db) async => (await db
          .customSelect("SELECT 1 FROM sync_meta WHERE "
              "object_id = '_mcp_legacy_complete_v1'")
          .get())
      .isNotEmpty;

  static Future<void> markComplete(AppDatabase db) => db.customStatement(
      "INSERT OR REPLACE INTO sync_meta "
      '(object_id, "table", version, row_json, dirty, updated_at) '
      "VALUES ('_mcp_legacy_complete_v1', '_mcp_legacy_v1', 1, '1', 0, ?)",
      [DateTime.now().millisecondsSinceEpoch ~/ 1000]);
}
