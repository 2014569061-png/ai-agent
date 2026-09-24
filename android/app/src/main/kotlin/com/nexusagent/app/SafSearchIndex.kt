package com.nexusagent.app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

internal data class SafIndexedDocument(
    val uri: String,
    val name: String,
    val mimeType: String,
    val modifiedAtMs: Long,
    val sizeBytes: Long,
)

internal data class SafIndexState(
    val indexedAtMs: Long,
    val complete: Boolean,
)

internal data class SafIndexSearchResult(
    val files: List<Map<String, String>>,
    val truncated: Boolean,
    val indexedAtMs: Long,
    val incompleteRoots: List<String>,
)

/**
 * A small private index for user-authorized Storage Access Framework trees.
 *
 * SAF providers are queried only while an index is first built, explicitly
 * refreshed, or considered stale. Searches then use SQLite instead of walking
 * the provider tree on every request.
 */
internal class SafSearchIndex(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE roots (
              root_uri TEXT PRIMARY KEY NOT NULL,
              indexed_at_ms INTEGER NOT NULL,
              complete INTEGER NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE TABLE files (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              root_uri TEXT NOT NULL,
              document_uri TEXT NOT NULL,
              name TEXT NOT NULL,
              mime_type TEXT NOT NULL,
              modified_at_ms INTEGER NOT NULL,
              size_bytes INTEGER NOT NULL,
              UNIQUE(root_uri, document_uri)
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX files_by_name ON files(name COLLATE NOCASE)")
        db.execSQL("CREATE INDEX files_by_root ON files(root_uri)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < DATABASE_VERSION) {
            db.execSQL("DROP TABLE IF EXISTS files")
            db.execSQL("DROP TABLE IF EXISTS roots")
            onCreate(db)
        }
    }

    fun state(rootUri: String): SafIndexState? =
        readableDatabase.rawQuery(
            "SELECT indexed_at_ms, complete FROM roots WHERE root_uri = ?",
            arrayOf(rootUri),
        ).use { cursor ->
            if (!cursor.moveToFirst()) null
            else SafIndexState(cursor.getLong(0), cursor.getInt(1) == 1)
        }

    fun replaceRoot(
        rootUri: String,
        documents: List<SafIndexedDocument>,
        indexedAtMs: Long,
        complete: Boolean,
    ) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("files", "root_uri = ?", arrayOf(rootUri))
            val values = ContentValues()
            for (document in documents) {
                values.clear()
                values.put("root_uri", rootUri)
                values.put("document_uri", document.uri)
                values.put("name", document.name)
                values.put("mime_type", document.mimeType)
                values.put("modified_at_ms", document.modifiedAtMs)
                values.put("size_bytes", document.sizeBytes)
                db.insertOrThrow("files", null, values)
            }
            values.clear()
            values.put("root_uri", rootUri)
            values.put("indexed_at_ms", indexedAtMs)
            values.put("complete", if (complete) 1 else 0)
            db.insertWithOnConflict(
                "roots",
                null,
                values,
                SQLiteDatabase.CONFLICT_REPLACE,
            )
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun removeRoot(rootUri: String) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("files", "root_uri = ?", arrayOf(rootUri))
            db.delete("roots", "root_uri = ?", arrayOf(rootUri))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun search(
        rootUris: List<String>,
        query: String,
        extension: String? = null,
        modifiedAfterMs: Long? = null,
        modifiedBeforeMs: Long? = null,
        limit: Int = 101,
    ): SafIndexSearchResult {
        if (rootUris.isEmpty()) {
            return SafIndexSearchResult(emptyList(), false, 0L, emptyList())
        }
        val placeholders = rootUris.joinToString(",") { "?" }
        val clauses = mutableListOf(
            "root_uri IN ($placeholders)",
            "mime_type != ?",
            "instr(lower(name), lower(?)) > 0",
        )
        val args = mutableListOf<String>().apply {
            addAll(rootUris)
            add("vnd.android.document/directory")
            add(query)
        }
        if (!extension.isNullOrBlank()) {
            val normalizedExtension =
                if (extension.startsWith(".")) extension.lowercase()
                else ".${extension.lowercase()}"
            clauses.add("substr(lower(name), -?) = ?")
            args.add(normalizedExtension.length.toString())
            args.add(normalizedExtension)
        }
        if (modifiedAfterMs != null) {
            clauses.add("modified_at_ms >= ?")
            args.add(modifiedAfterMs.toString())
        }
        if (modifiedBeforeMs != null) {
            clauses.add("modified_at_ms <= ?")
            args.add(modifiedBeforeMs.toString())
        }

        val files = mutableListOf<Map<String, String>>()
        readableDatabase.rawQuery(
            """
            SELECT document_uri, name, modified_at_ms, size_bytes
            FROM files
            WHERE ${clauses.joinToString(" AND ")}
            ORDER BY modified_at_ms DESC, name COLLATE NOCASE ASC
            LIMIT ?
            """.trimIndent(),
            (args + limit.toString()).toTypedArray(),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                files.add(
                    mapOf(
                        "uri" to cursor.getString(0),
                        "name" to cursor.getString(1),
                        "modifiedAtMs" to cursor.getLong(2).toString(),
                        "sizeBytes" to cursor.getLong(3).toString(),
                    )
                )
            }
        }

        val states = rootUris.mapNotNull { uri -> state(uri)?.let { uri to it } }
        val incomplete = states.filter { !it.second.complete }.map { it.first }
        val indexedAt = states.minOfOrNull { it.second.indexedAtMs } ?: 0L
        val truncated = files.size >= limit || incomplete.isNotEmpty()
        return SafIndexSearchResult(
            files = files.take(limit - 1),
            truncated = truncated,
            indexedAtMs = indexedAt,
            incompleteRoots = incomplete,
        )
    }

    companion object {
        private const val DATABASE_NAME = "saf_search_index.db"
        private const val DATABASE_VERSION = 1
    }
}
