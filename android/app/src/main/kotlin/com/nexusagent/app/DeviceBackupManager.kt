package com.nexusagent.app

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.CallLog
import android.provider.ContactsContract
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedWriter
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * 备份与恢复（MethodChannel `nexus/device_backup`）。
 *
 * 设计约束：
 * - 所有备份写入应用自己的外部文件目录 `Android/data/<pkg>/files/backups/<id>/`，
 *   每个备份带 manifest.json（文件列表、大小、SHA-256、来源版本和可恢复范围）。
 * - 免 Root：应用可选 `scope=apk` 只备份安装包（含 split APK），经系统安装器恢复；
 *   目录备份在已获“所有文件访问”时以应用自身身份打包，否则走 Root / Shizuku。
 * - Root（或 Root 模式的 Shizuku）只用于读取/写回应用私有数据。命令由本类固定模板生成，参数只接受
 *   校验过的包名、备份 ID 和白名单路径；Root 进程通过 stdout/stdin 流式传输
 *   tar 数据，避免 Root 创建的文件出现在共享存储上导致属主混乱。
 * - 恢复前必须能列出归档内容；恢复时先自动生成一份“恢复前快照”作为撤销入口。
 * - 短信和通话记录只导出，不写回（写回短信需要成为默认短信应用，写通话记录需要额外权限）。
 * - 不提供整机一键恢复。
 */
class DeviceBackupManager(private val activity: Activity) {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermission: PendingPersonalExport? = null

    private data class PendingPersonalExport(
        val category: String,
        val result: MethodChannel.Result,
    )

    private class BackupFailure(val code: String, message: String) : Exception(message)

    val backupsRoot: File
        get() {
            val base = activity.getExternalFilesDir(null) ?: activity.filesDir
            return File(base, "backups")
        }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listBackups" -> runAsync(result) { listBackups() }
            "inspectBackup" -> {
                val id = call.argument<String>("backupId")
                if (!isValidBackupId(id)) {
                    result.error("INVALID_ARGS", "backupId 无效", null)
                } else {
                    runAsync(result) { inspectBackup(id!!) }
                }
            }
            "personalDataPermission" -> {
                val category = call.argument<String>("category")
                val permission = permissionFor(category)
                if (permission == null) {
                    result.error("INVALID_ARGS", "category 仅支持 contacts、sms、call_log", null)
                } else {
                    result.success(
                        mapOf(
                            "category" to category,
                            "permission" to permission,
                            "granted" to isGranted(permission),
                        )
                    )
                }
            }
            "exportPersonalData" -> {
                val category = call.argument<String>("category")
                val permission = permissionFor(category)
                when {
                    permission == null ->
                        result.error("INVALID_ARGS", "category 仅支持 contacts、sms、call_log", null)
                    isGranted(permission) ->
                        runAsync(result) { exportPersonalData(category!!) }
                    pendingPermission != null ->
                        result.error("BUSY", "已有一个权限请求正在等待用户处理", null)
                    else -> {
                        pendingPermission = PendingPersonalExport(category!!, result)
                        activity.requestPermissions(arrayOf(permission), PERMISSION_REQUEST_CODE)
                    }
                }
            }
            "backupAppData" -> {
                val appPackage = call.argument<String>("packageName")?.trim()
                val scope = call.argument<String>("scope") ?: "config"
                if (!isValidPackageName(appPackage) || scope !in APP_DATA_SCOPES) {
                    result.error("INVALID_ARGS", "packageName 或 scope 无效（scope: config/full/apk）", null)
                } else if (scope == "apk") {
                    runAsync(result) { backupApk(appPackage!!) }
                } else {
                    runAsync(result) { backupAppData(appPackage!!, scope, tag = null) }
                }
            }
            "backupDirectory" -> {
                val path = call.argument<String>("path")?.trim()
                if (!isAllowedDirectoryBackupPath(path)) {
                    result.error("INVALID_ARGS", "目录不在允许范围内，且不能是存储根目录", null)
                } else {
                    runAsync(result) { backupDirectory(path!!) }
                }
            }
            "restoreAppData" -> {
                val id = call.argument<String>("backupId")
                if (!isValidBackupId(id)) {
                    result.error("INVALID_ARGS", "backupId 无效", null)
                } else {
                    runAsync(result) { restoreAppData(id!!) }
                }
            }
            "importContacts" -> {
                val id = call.argument<String>("backupId")
                if (!isValidBackupId(id)) {
                    result.error("INVALID_ARGS", "backupId 无效", null)
                } else {
                    importContacts(id!!, result)
                }
            }
            "deleteBackup" -> {
                val id = call.argument<String>("backupId")
                if (!isValidBackupId(id)) {
                    result.error("INVALID_ARGS", "backupId 无效", null)
                } else {
                    runAsync(result) { deleteBackup(id!!) }
                }
            }
            else -> result.notImplemented()
        }
    }

    /** 返回 true 表示请求码属于备份模块并已处理。 */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val pending = pendingPermission ?: return true
        pendingPermission = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            pending.result.error(
                "PERMISSION_DENIED",
                "用户拒绝了 ${permissionLabel(pending.category)} 读取权限；未导出任何数据",
                null
            )
            return true
        }
        runAsync(pending.result) { exportPersonalData(pending.category) }
        return true
    }

    fun shutdown() {
        pendingPermission?.result?.error("CANCELLED", "页面已关闭", null)
        pendingPermission = null
        executor.shutdownNow()
    }

    // ---------------------------------------------------------------------
    // 列表与检查
    // ---------------------------------------------------------------------

    private fun listBackups(): Map<String, Any?> {
        val root = backupsRoot
        val items = root.listFiles()
            ?.filter { it.isDirectory && isValidBackupId(it.name) }
            ?.mapNotNull { dir -> readManifest(dir)?.let { summarize(it) } }
            ?.sortedByDescending { (it["createdAtMs"] as? Long) ?: 0L }
            .orEmpty()
        return mapOf(
            "backupsRoot" to root.absolutePath,
            "backups" to items.take(MAX_LISTED_BACKUPS),
            "total" to items.size,
            "truncated" to (items.size > MAX_LISTED_BACKUPS),
            "freeBytes" to freeBytes(root),
        )
    }

    private fun inspectBackup(id: String): Map<String, Any?> {
        val dir = backupDir(id)
        val manifest = readManifest(dir)
            ?: throw BackupFailure("NOT_FOUND", "备份 $id 不存在或清单损坏")
        val summary = summarize(manifest).toMutableMap()
        val files = manifest.optJSONArray("files") ?: JSONArray()
        val integrity = mutableListOf<Map<String, Any?>>()
        for (i in 0 until files.length()) {
            val item = files.getJSONObject(i)
            val file = File(dir, item.getString("name"))
            integrity.add(
                mapOf(
                    "name" to item.getString("name"),
                    "bytes" to item.optLong("bytes"),
                    "exists" to file.isFile,
                    "sizeMatches" to (file.isFile && file.length() == item.optLong("bytes")),
                )
            )
        }
        summary["files"] = integrity
        if (manifest.optString("kind") == "app_data" || manifest.optString("kind") == "directory") {
            val archive = File(dir, ARCHIVE_NAME)
            if (archive.isFile) {
                val listing = listArchive(archive)
                summary["entries"] = listing.entries.take(PREVIEW_ENTRY_COUNT)
                summary["entryCount"] = listing.entries.size
                summary["remainingEntries"] = (listing.entries.size - PREVIEW_ENTRY_COUNT).coerceAtLeast(0)
                summary["uncompressedBytes"] = listing.totalBytes
                summary["topLevel"] = listing.topLevel.toList().sorted()
                summary["unsafeEntries"] = listing.unsafe.take(10)
            }
        }
        if (manifest.optString("kind") == "apk") {
            val appPackage = manifest.optString("packageName")
            val installed = installedVersion(appPackage)
            summary["installedVersionCode"] = installed?.first
            summary["installedVersionName"] = installed?.second
            summary["signatureMatches"] = signingDigest(appPackage)?.let { current ->
                manifest.optString("signingSha256").takeIf { it.isNotBlank() }?.let { it == current }
            }
            summary["restoreCompatibility"] = apkCompatibility(manifest)
            summary["installPermissionGranted"] = PrivilegeManager.installPackagesAllowed()
            ApkInstallResultReceiver.lastResult(activity, id)?.let { summary["lastInstallResult"] = it }
        }
        if (manifest.optString("kind") == "app_data") {
            val appPackage = manifest.optString("packageName")
            val installed = installedVersion(appPackage)
            summary["installedVersionCode"] = installed?.first
            summary["installedVersionName"] = installed?.second
            summary["restoreCompatibility"] = restoreCompatibility(manifest, installed)
        }
        return summary
    }

    private fun summarize(manifest: JSONObject): Map<String, Any?> {
        val coverage = manifest.optJSONArray("restoreCoverage")
        return mapOf(
            "backupId" to manifest.optString("id"),
            "kind" to manifest.optString("kind"),
            "category" to manifest.optString("category").ifBlank { null },
            "packageName" to manifest.optString("packageName").ifBlank { null },
            "scope" to manifest.optString("scope").ifBlank { null },
            "sourcePath" to manifest.optString("sourcePath").ifBlank { null },
            "tag" to manifest.optString("tag").ifBlank { null },
            "createdAtMs" to manifest.optLong("createdAtMs"),
            "totalBytes" to manifest.optLong("totalBytes"),
            "itemCount" to if (manifest.has("itemCount")) manifest.optInt("itemCount") else null,
            "versionCode" to if (manifest.has("versionCode")) manifest.optLong("versionCode") else null,
            "versionName" to manifest.optString("versionName").ifBlank { null },
            "restorable" to manifest.optBoolean("restorable"),
            "restoreMethod" to manifest.optString("restoreMethod").ifBlank { null },
            "restoreCoverage" to (0 until (coverage?.length() ?: 0)).map { coverage!!.getString(it) },
            "notes" to manifest.optString("notes").ifBlank { null },
            "appLabel" to manifest.optString("appLabel").ifBlank { null },
            "executedVia" to manifest.optString("executedVia").ifBlank { null },
            "path" to backupDir(manifest.optString("id")).absolutePath,
        )
    }

    // ---------------------------------------------------------------------
    // 个人数据导出（运行时权限）
    // ---------------------------------------------------------------------

    private fun exportPersonalData(category: String): Map<String, Any?> {
        val id = newBackupId("personal")
        val dir = backupDir(id)
        if (!dir.mkdirs()) throw BackupFailure("IO_ERROR", "无法创建备份目录")
        try {
            val written = when (category) {
                "contacts" -> exportContacts(dir)
                "sms" -> exportSms(dir)
                "call_log" -> exportCallLog(dir)
                else -> throw BackupFailure("INVALID_ARGS", "未知类别")
            }
            val manifest = JSONObject()
                .put("id", id)
                .put("kind", "personal")
                .put("category", category)
                .put("createdAtMs", System.currentTimeMillis())
                .put("itemCount", written.second)
                .put("files", fileEntries(dir, written.first))
                .put("totalBytes", written.first.sumOf { File(dir, it).length() })
                .put("restorable", category == "contacts")
                .put("restoreMethod", if (category == "contacts") "system_contacts_import" else "none")
                .put(
                    "restoreCoverage",
                    JSONArray(if (category == "contacts") listOf("导入到系统通讯录（由通讯录应用确认，可能产生重复联系人）") else emptyList())
                )
                .put(
                    "notes",
                    when (category) {
                        "sms" -> "短信仅导出为 JSON；写回短信需要本应用成为默认短信应用，因此不提供恢复。"
                        "call_log" -> "通话记录仅导出为 JSON；不申请 WRITE_CALL_LOG，因此不提供恢复。"
                        else -> "联系人导出为 vCard 3.0 与 JSON；恢复通过系统通讯录导入完成。"
                    }
                )
            writeManifest(dir, manifest)
            return summarize(manifest) + mapOf("exported" to true)
        } catch (e: Exception) {
            dir.deleteRecursively()
            throw e
        }
    }

    private fun exportContacts(dir: File): Pair<List<String>, Int> {
        data class Contact(
            var name: String = "",
            val phones: MutableList<String> = mutableListOf(),
            val emails: MutableList<String> = mutableListOf(),
            var organization: String = "",
            var note: String = "",
        )
        val contacts = linkedMapOf<Long, Contact>()
        val projection = arrayOf(
            ContactsContract.Data.CONTACT_ID,
            ContactsContract.Data.MIMETYPE,
            ContactsContract.Data.DISPLAY_NAME,
            ContactsContract.Data.DATA1,
        )
        activity.contentResolver.query(
            ContactsContract.Data.CONTENT_URI,
            projection,
            null,
            null,
            ContactsContract.Data.CONTACT_ID + " ASC"
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (contacts.size >= MAX_PERSONAL_ITEMS && !contacts.containsKey(cursor.getLong(0))) break
                val contact = contacts.getOrPut(cursor.getLong(0)) { Contact() }
                if (contact.name.isBlank()) contact.name = cursor.stringOrEmpty(2)
                val value = cursor.stringOrEmpty(3)
                if (value.isBlank()) continue
                when (cursor.stringOrEmpty(1)) {
                    ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE -> contact.phones.add(value)
                    ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE -> contact.emails.add(value)
                    ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE -> contact.organization = value
                    ContactsContract.CommonDataKinds.Note.CONTENT_ITEM_TYPE -> contact.note = value
                }
            }
        } ?: throw BackupFailure("PERMISSION_DENIED", "系统拒绝读取联系人")

        File(dir, "contacts.vcf").bufferedWriter().use { out ->
            contacts.values.forEach { contact ->
                out.write("BEGIN:VCARD\r\nVERSION:3.0\r\n")
                out.write("FN:${vcardEscape(contact.name)}\r\n")
                out.write("N:${vcardEscape(contact.name)};;;;\r\n")
                contact.phones.distinct().forEach { out.write("TEL;TYPE=CELL:${vcardEscape(it)}\r\n") }
                contact.emails.distinct().forEach { out.write("EMAIL:${vcardEscape(it)}\r\n") }
                if (contact.organization.isNotBlank()) out.write("ORG:${vcardEscape(contact.organization)}\r\n")
                if (contact.note.isNotBlank()) out.write("NOTE:${vcardEscape(contact.note)}\r\n")
                out.write("END:VCARD\r\n")
            }
        }
        File(dir, "contacts.json").bufferedWriter().use { out ->
            writeJsonArray(out, contacts.values.map { contact ->
                JSONObject()
                    .put("name", contact.name)
                    .put("phones", JSONArray(contact.phones.distinct()))
                    .put("emails", JSONArray(contact.emails.distinct()))
                    .put("organization", contact.organization)
                    .put("note", contact.note)
            })
        }
        return listOf("contacts.vcf", "contacts.json") to contacts.size
    }

    private fun exportSms(dir: File): Pair<List<String>, Int> {
        val uri = Uri.parse("content://sms")
        val projection = arrayOf("address", "body", "date", "type", "read", "thread_id")
        var count = 0
        File(dir, "sms.json").bufferedWriter().use { out ->
            out.write("[")
            activity.contentResolver.query(uri, projection, null, null, "date DESC")?.use { cursor ->
                while (cursor.moveToNext() && count < MAX_PERSONAL_ITEMS) {
                    if (count > 0) out.write(",")
                    out.write(
                        JSONObject()
                            .put("address", cursor.stringOrEmpty(0))
                            .put("body", cursor.stringOrEmpty(1))
                            .put("date", cursor.getLong(2))
                            .put("type", smsType(cursor.getInt(3)))
                            .put("read", cursor.getInt(4) == 1)
                            .put("threadId", cursor.getLong(5))
                            .toString()
                    )
                    count++
                }
            } ?: throw BackupFailure("PERMISSION_DENIED", "系统拒绝读取短信")
            out.write("]")
        }
        return listOf("sms.json") to count
    }

    private fun exportCallLog(dir: File): Pair<List<String>, Int> {
        val projection = arrayOf(
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
            CallLog.Calls.TYPE,
        )
        var count = 0
        File(dir, "call_log.json").bufferedWriter().use { out ->
            out.write("[")
            activity.contentResolver.query(
                CallLog.Calls.CONTENT_URI, projection, null, null, CallLog.Calls.DATE + " DESC"
            )?.use { cursor ->
                while (cursor.moveToNext() && count < MAX_PERSONAL_ITEMS) {
                    if (count > 0) out.write(",")
                    out.write(
                        JSONObject()
                            .put("number", cursor.stringOrEmpty(0))
                            .put("name", cursor.stringOrEmpty(1))
                            .put("date", cursor.getLong(2))
                            .put("durationSeconds", cursor.getLong(3))
                            .put("type", callType(cursor.getInt(4)))
                            .toString()
                    )
                    count++
                }
            } ?: throw BackupFailure("PERMISSION_DENIED", "系统拒绝读取通话记录")
            out.write("]")
        }
        return listOf("call_log.json") to count
    }

    private fun importContacts(id: String, result: MethodChannel.Result) {
        try {
            val manifest = readManifest(backupDir(id))
            if (manifest == null || manifest.optString("category") != "contacts") {
                result.error("NOT_FOUND", "只有联系人备份可以导入系统通讯录", null)
                return
            }
            val source = File(backupDir(id), "contacts.vcf")
            if (!source.isFile) {
                result.error("NOT_FOUND", "备份中缺少 contacts.vcf", null)
                return
            }
            val stagingDir = File(activity.filesDir, "contact_exports")
            if (!stagingDir.isDirectory && !stagingDir.mkdirs()) {
                result.error("IO_ERROR", "无法准备导入文件", null)
                return
            }
            val staged = File(stagingDir, "import.vcf")
            source.copyTo(staged, overwrite = true)
            val uri = FileProvider.getUriForFile(
                activity, "${activity.packageName}.fileprovider", staged
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "text/x-vcard")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivity(Intent.createChooser(intent, "导入联系人"))
            result.success(
                mapOf(
                    "opened" to true,
                    "itemCount" to manifest.optInt("itemCount"),
                    "note" to "已交给系统通讯录处理；是否导入、导入到哪个账户由用户在系统界面确认",
                )
            )
        } catch (e: Exception) {
            result.error("UNSUPPORTED_OPERATION", e.message ?: "没有可处理 vCard 的通讯录应用", null)
        }
    }

    // ---------------------------------------------------------------------
    // 应用数据 / 目录备份（Root）
    // ---------------------------------------------------------------------

    private fun backupAppData(appPackage: String, scope: String, tag: String?): Map<String, Any?> {
        val id = newBackupId(if (tag == null) "app" else "prerestore")
        val dir = backupDir(id)
        if (!dir.mkdirs()) throw BackupFailure("IO_ERROR", "无法创建备份目录")
        try {
            ensureFreeSpace(dir)
            val script = appDataRootPrelude(appPackage) + "\n" + when (scope) {
                "config" -> """
                    set --
                    for d in shared_prefs databases; do
                      if [ -e "${'$'}d" ] && [ ! -L "${'$'}d" ]; then set -- "${'$'}@" "${'$'}d"; fi
                    done
                """.trimIndent()
                else -> """
                    set --
                    for d in * .[!.]*; do
                      case "${'$'}d" in cache|code_cache|lib|'*'|'.[!.]*') continue ;; esac
                      if [ -e "${'$'}d" ] && [ ! -L "${'$'}d" ]; then set -- "${'$'}@" "${'$'}d"; fi
                    done
                """.trimIndent()
            } + "\n" + """
                [ "${'$'}#" -gt 0 ] || exit 25
                tar -czf - -- "${'$'}@"
            """.trimIndent()
            val archive = File(dir, ARCHIVE_NAME)
            FileOutputStream(archive).use { out -> runRootStreaming(script, stdin = null, stdout = out) }
            val listing = listArchive(archive)
            if (listing.unsafe.isNotEmpty()) {
                throw BackupFailure("UNSAFE_ARCHIVE", "归档包含不安全路径，已放弃：${listing.unsafe.first()}")
            }
            val version = installedVersion(appPackage)
            val coverage = listing.topLevel.toList().sorted()
            val manifest = JSONObject()
                .put("id", id)
                .put("kind", "app_data")
                .put("packageName", appPackage)
                .put("scope", scope)
                .put("createdAtMs", System.currentTimeMillis())
                .put("files", fileEntries(dir, listOf(ARCHIVE_NAME)))
                .put("totalBytes", archive.length())
                .put("itemCount", listing.entries.size)
                .put("uncompressedBytes", listing.totalBytes)
                .put("restorable", true)
                .put("restoreMethod", "root_replace_directories")
                .put("restoreCoverage", JSONArray(coverage.map { "/data/user/0/$appPackage/$it" }))
                .put(
                    "notes",
                    if (scope == "config") "配置包：只包含 shared_prefs 与 databases。" +
                        "应用运行中备份的数据库可能不是一致快照，建议先停止应用再备份。"
                    else "完整应用数据（不含 cache、code_cache、lib）。应用运行中备份可能不一致。"
                )
            if (version != null) {
                manifest.put("versionCode", version.first).put("versionName", version.second)
            }
            if (tag != null) manifest.put("tag", tag)
            writeManifest(dir, manifest)
            return summarize(manifest) + mapOf("created" to true)
        } catch (e: Exception) {
            dir.deleteRecursively()
            throw e
        }
    }

    private fun backupDirectory(path: String): Map<String, Any?> {
        val normalized = path.replace(Regex("/+"), "/").trimEnd('/')
        val parent = normalized.substringBeforeLast('/')
        val name = normalized.substringAfterLast('/')
        val id = newBackupId("dir")
        val dir = backupDir(id)
        if (!dir.mkdirs()) throw BackupFailure("IO_ERROR", "无法创建备份目录")
        try {
            ensureFreeSpace(dir)
            val script = """
                [ -d ${shellQuote(normalized)} ] || exit 26
                [ ! -L ${shellQuote(normalized)} ] || exit 27
                cd -- ${shellQuote(parent)} || exit 24
                tar -czf - -- ${shellQuote(name)}
            """.trimIndent()
            val archive = File(dir, ARCHIVE_NAME)
            val backend = FileOutputStream(archive).use { out ->
                runRootStreaming(
                    script,
                    stdin = null,
                    stdout = out,
                    requirement = PrivilegeRequirement.STORAGE,
                    paths = listOf(normalized),
                )
            }
            val listing = listArchive(archive)
            val manifest = JSONObject()
                .put("id", id)
                .put("kind", "directory")
                .put("executedVia", backend.id)
                .put("sourcePath", normalized)
                .put("createdAtMs", System.currentTimeMillis())
                .put("files", fileEntries(dir, listOf(ARCHIVE_NAME)))
                .put("totalBytes", archive.length())
                .put("itemCount", listing.entries.size)
                .put("uncompressedBytes", listing.totalBytes)
                .put("restorable", false)
                .put("restoreMethod", "manual_extract")
                .put("restoreCoverage", JSONArray())
                .put("notes", "目录导出不会自动覆盖原位置；需要时用 extract_root_archive 解压到指定白名单目录。")
            writeManifest(dir, manifest)
            return summarize(manifest) + mapOf("created" to true)
        } catch (e: Exception) {
            dir.deleteRecursively()
            throw e
        }
    }

    private fun restoreAppData(id: String): Map<String, Any?> {
        val dir = backupDir(id)
        val manifest = readManifest(dir)
            ?: throw BackupFailure("NOT_FOUND", "备份 $id 不存在或清单损坏")
        if (manifest.optString("kind") == "apk") return restoreApk(id, dir, manifest)
        if (manifest.optString("kind") != "app_data") {
            throw BackupFailure("UNSUPPORTED_OPERATION", "只有应用数据备份和安装包备份支持恢复")
        }
        val appPackage = manifest.optString("packageName")
        if (!isValidPackageName(appPackage)) throw BackupFailure("INVALID_ARGS", "清单中的包名无效")
        val archive = File(dir, ARCHIVE_NAME)
        verifyIntegrity(dir, manifest)
        val installed = installedVersion(appPackage)
        val compatibility = restoreCompatibility(manifest, installed)
        if (compatibility["allowed"] != true) {
            throw BackupFailure("RESTORE_BLOCKED", compatibility["reason"].toString())
        }
        val listing = listArchive(archive)
        if (listing.unsafe.isNotEmpty()) {
            throw BackupFailure("UNSAFE_ARCHIVE", "归档包含不安全路径：${listing.unsafe.first()}")
        }
        val topLevel = listing.topLevel.filter { it !in PROTECTED_APP_DIRS }
        if (topLevel.isEmpty()) throw BackupFailure("EMPTY_ARCHIVE", "归档没有可恢复的目录")

        // 撤销入口：先对即将被覆盖的范围做一次快照。
        val snapshot = backupAppData(
            appPackage,
            manifest.optString("scope").ifBlank { "config" },
            tag = "pre_restore:$id"
        )
        val removeDirs = topLevel.joinToString(" ") { shellQuote(it) }
        val script = appDataRootPrelude(appPackage) + "\n" + """
            owner=${'$'}(stat -c %u:%g "${'$'}app_root") || exit 28
            am force-stop ${appPackage}
            for d in $removeDirs; do
              [ -L "${'$'}app_root/${'$'}d" ] && exit 29
              rm -rf -- "${'$'}app_root/${'$'}d" || exit 30
            done
            tar -xzf - -C "${'$'}app_root" || exit 31
            for d in $removeDirs; do
              [ -e "${'$'}app_root/${'$'}d" ] && chown -R "${'$'}owner" -- "${'$'}app_root/${'$'}d"
            done
            restorecon -R -- "${'$'}app_root" 2>/dev/null || true
            echo restored
        """.trimIndent()
        try {
            FileInputStream(archive).use { input -> runRootStreaming(script, stdin = input, stdout = null) }
        } catch (e: BackupFailure) {
            // 失败时数据可能已部分替换：把撤销用的快照 ID 带回，不让调用方误以为“什么都没发生”。
            throw BackupFailure(
                e.code,
                "${e.message}；恢复前快照 ${snapshot["backupId"]} 已保留，可对它执行 restore_app_data 撤销"
            )
        }
        return mapOf(
            "restored" to true,
            "backupId" to id,
            "packageName" to appPackage,
            "replacedDirectories" to topLevel.map { "/data/user/0/$appPackage/$it" },
            "entryCount" to listing.entries.size,
            "undoBackupId" to snapshot["backupId"],
            "undoHint" to "如需撤销，对 undoBackupId 再执行一次 restore_app_data",
        )
    }

    // ---------------------------------------------------------------------
    // 安装包备份与恢复（免 Root）
    // ---------------------------------------------------------------------

    private fun backupApk(appPackage: String): Map<String, Any?> {
        val pm = activity.packageManager
        val info = try {
            pm.getApplicationInfo(appPackage, 0)
        } catch (e: PackageManager.NameNotFoundException) {
            throw BackupFailure("NOT_FOUND", "应用 $appPackage 未安装或对本应用不可见")
        }
        val sources = (listOf(info.sourceDir) + info.splitSourceDirs.orEmpty().toList())
            .filterNotNull()
            .map { File(it) }
        if (sources.isEmpty() || sources.any { !it.isFile || !it.canRead() }) {
            throw BackupFailure("PERMISSION_DENIED", "无法读取该应用的安装包文件")
        }
        val total = sources.sumOf { it.length() }
        val id = newBackupId("apk")
        val dir = backupDir(id)
        if (!dir.mkdirs()) throw BackupFailure("IO_ERROR", "无法创建备份目录")
        try {
            if (freeBytes(dir) < total + MIN_FREE_BYTES) {
                throw BackupFailure("INSUFFICIENT_STORAGE", "剩余空间不足以保存 ${total / (1024 * 1024)} MiB 的安装包")
            }
            val names = sources.mapIndexed { index, file ->
                val name = if (index == 0) "base.apk" else {
                    val clean = file.name.replace(Regex("[^A-Za-z0-9._-]"), "_")
                    "split_${index}_" + if (clean.endsWith(".apk")) clean else "$clean.apk"
                }
                file.copyTo(File(dir, name), overwrite = false)
                name
            }
            val version = installedVersion(appPackage)
            val manifest = JSONObject()
                .put("id", id)
                .put("kind", "apk")
                .put("packageName", appPackage)
                .put("appLabel", info.loadLabel(pm).toString())
                .put("createdAtMs", System.currentTimeMillis())
                .put("files", fileEntries(dir, names))
                .put("totalBytes", names.sumOf { File(dir, it).length() })
                .put("itemCount", names.size)
                .put("splitCount", names.size - 1)
                .put("restorable", true)
                .put("restoreMethod", "package_installer")
                .put("executedVia", "app")
                .put("restoreCoverage", JSONArray(listOf("安装包：$appPackage（${names.size} 个 APK，不含应用数据）")))
                .put(
                    "notes",
                    "仅备份安装包，不含应用数据。恢复经系统安装器并需用户确认；" +
                        "已安装版本签名不同或版本更高时系统会拒绝安装。"
                )
            signingDigest(appPackage)?.let { manifest.put("signingSha256", it) }
            if (version != null) {
                manifest.put("versionCode", version.first).put("versionName", version.second)
            }
            writeManifest(dir, manifest)
            return summarize(manifest) + mapOf("created" to true)
        } catch (e: Exception) {
            dir.deleteRecursively()
            throw e
        }
    }

    private fun apkCompatibility(manifest: JSONObject): Map<String, Any?> {
        val appPackage = manifest.optString("packageName")
        val installed = installedVersion(appPackage)
        val backupVersion = if (manifest.has("versionCode")) manifest.optLong("versionCode") else null
        val backupSigning = manifest.optString("signingSha256")
        val installedSigning = if (installed != null) signingDigest(appPackage) else null
        return when {
            installed == null -> mapOf("allowed" to true, "reason" to "目标应用未安装，将全新安装（不含数据）")
            backupSigning.isNotBlank() && installedSigning != null && installedSigning != backupSigning -> mapOf(
                "allowed" to false,
                "reason" to "已安装应用的签名与备份不同，系统会拒绝覆盖安装；只有先卸载才能安装（卸载会清除数据，不可逆），已拒绝",
            )
            backupVersion != null && installed.first > backupVersion -> mapOf(
                "allowed" to true,
                "reason" to "备份版本 ($backupVersion) 低于已安装版本 ${installed.second}(${installed.first})，系统通常会拒绝降级安装",
            )
            else -> mapOf("allowed" to true, "reason" to "签名一致，可覆盖安装；应用数据保留")
        }
    }

    private fun restoreApk(id: String, dir: File, manifest: JSONObject): Map<String, Any?> {
        val appPackage = manifest.optString("packageName")
        if (!isValidPackageName(appPackage)) throw BackupFailure("INVALID_ARGS", "清单中的包名无效")
        verifyIntegrity(dir, manifest)
        val compatibility = apkCompatibility(manifest)
        if (compatibility["allowed"] != true) {
            throw BackupFailure("RESTORE_BLOCKED", compatibility["reason"].toString())
        }
        if (!PrivilegeManager.installPackagesAllowed()) {
            throw BackupFailure(
                "PERMISSION_REQUIRED",
                "需要先允许 NEXUS“安装未知应用”（设备能力页可打开授权页），然后重试恢复",
            )
        }
        val files = manifest.optJSONArray("files") ?: JSONArray()
        val names = (0 until files.length()).map { files.getJSONObject(it).getString("name") }
            .filter { it.endsWith(".apk") && !it.contains('/') }
        if (names.isEmpty()) throw BackupFailure("CORRUPT_ARCHIVE", "备份中没有 APK 文件")
        val installer = activity.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(appPackage)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
        }
        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        try {
            names.forEach { name ->
                val file = File(dir, name)
                FileInputStream(file).use { input ->
                    session.openWrite(name, 0, file.length()).use { output ->
                        input.copyTo(output, 64 * 1024)
                        session.fsync(output)
                    }
                }
            }
            val callback = Intent(activity, ApkInstallResultReceiver::class.java)
                .setAction(ApkInstallResultReceiver.ACTION_INSTALL_STATUS)
                .setPackage(activity.packageName)
                .putExtra(ApkInstallResultReceiver.EXTRA_BACKUP_ID, id)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val pending = PendingIntent.getBroadcast(activity, sessionId, callback, flags)
            session.commit(pending.intentSender)
        } catch (e: Exception) {
            runCatching { session.abandon() }
            throw BackupFailure("INSTALL_FAILED", "写入安装会话失败：${e.message}")
        } finally {
            session.close()
        }
        return mapOf(
            "restored" to false,
            "installRequested" to true,
            "userActionRequired" to true,
            "executedVia" to "package_installer",
            "backupId" to id,
            "packageName" to appPackage,
            "sessionId" to sessionId,
            "apkCount" to names.size,
            "compatibility" to compatibility,
            "message" to "已提交系统安装器，请在弹出的确认框中点击“安装”；结果以系统提示为准，可稍后用 backup_inspect 查看 lastInstallResult",
            "undoHint" to "安装包恢复不能自动撤销；如需回退，请重新安装原版本安装包",
        )
    }

    private fun signingDigest(appPackage: String): String? = runCatching {
        val pm = activity.packageManager
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signing = pm.getPackageInfo(appPackage, PackageManager.GET_SIGNING_CERTIFICATES)
                .signingInfo ?: return null
            if (signing.hasMultipleSigners()) signing.apkContentsSigners
            else signing.signingCertificateHistory
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(appPackage, PackageManager.GET_SIGNATURES).signatures
        }
        val first = signatures?.firstOrNull() ?: return null
        MessageDigest.getInstance("SHA-256").digest(first.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }.getOrNull()

    private fun deleteBackup(id: String): Map<String, Any?> {
        val dir = backupDir(id)
        if (!dir.isDirectory) throw BackupFailure("NOT_FOUND", "备份 $id 不存在")
        val bytes = dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        if (!dir.deleteRecursively()) throw BackupFailure("IO_ERROR", "删除备份失败")
        return mapOf("deleted" to true, "backupId" to id, "freedBytes" to bytes)
    }

    // ---------------------------------------------------------------------
    // Root 执行与归档工具
    // ---------------------------------------------------------------------

    private fun appDataRootPrelude(appPackage: String): String = """
        data_root=${'$'}(readlink -f -- '/data/user/0') || exit 20
        app_root=${'$'}(readlink -f -- '/data/user/0/$appPackage') || exit 21
        [ "${'$'}app_root" = "${'$'}data_root/$appPackage" ] || exit 22
        [ -d "${'$'}app_root" ] || exit 23
        cd -- "${'$'}app_root" || exit 24
    """.trimIndent()

    /**
     * 通过 `su -c` 执行固定模板脚本，stdout/stdin 以流方式传输归档。
     * 超时、Root 不可用、权限/SELinux 拒绝都会映射成明确错误码，不假装成功。
     */
    private fun runRootStreaming(
        script: String,
        stdin: InputStream?,
        stdout: OutputStream?,
        requirement: PrivilegeRequirement = PrivilegeRequirement.ROOT_UID,
        paths: List<String> = emptyList(),
    ): PrivilegeBackend {
        val process = try {
            PrivilegeManager.start(requirement, script, paths, acceptsStdin = stdin != null)
        } catch (e: PrivilegeUnavailableException) {
            throw BackupFailure(
                e.code,
                if (requirement == PrivilegeRequirement.ROOT_UID) {
                    "读写应用私有数据需要 Root（或 Root 模式的 Shizuku）；免 Root 可改用 scope=apk 备份安装包"
                } else {
                    e.message ?: "没有可用的执行通道"
                },
            )
        } catch (e: IOException) {
            throw BackupFailure("PRIVILEGE_UNAVAILABLE", "执行通道启动失败：${e.message}")
        }
        val label = process.backend.label
        val stderr = StringBuilder()
        val stderrThread = Thread {
            runCatching {
                process.errorStream.bufferedReader().forEachLine {
                    if (stderr.length < 4000) stderr.appendLine(it)
                }
            }
        }.apply { start() }
        val copied = AtomicLong(0)
        val streamError = java.util.concurrent.atomic.AtomicReference<Throwable?>(null)
        val writerThread = stdin?.let { input ->
            Thread {
                runCatching {
                    process.outputStream.use { out -> copyBounded(input, out, copied, MAX_ARCHIVE_BYTES) }
                }.onFailure { error ->
                    // 解压端提前退出会导致 broken pipe，以退出码为准；超限才算流错误。
                    if (error.message?.contains("上限") == true) streamError.compareAndSet(null, error)
                }
            }.apply { start() }
        } ?: run {
            runCatching { process.outputStream.close() }
            null
        }
        val readerThread = Thread {
            runCatching {
                process.inputStream.use { input ->
                    if (stdout != null) {
                        copyBounded(input, stdout, AtomicLong(0), MAX_ARCHIVE_BYTES)
                    } else {
                        val sink = ByteArray(8 * 1024)
                        while (input.read(sink) >= 0) { /* drain */ }
                    }
                }
            }.onFailure { error -> streamError.compareAndSet(null, error) }
        }.apply { start() }
        val finished = process.waitFor(ROOT_TIMEOUT_SECONDS * 1000L)
        if (!finished) {
            process.destroy()
            throw BackupFailure("TIMEOUT", "$label 操作超过 $ROOT_TIMEOUT_SECONDS 秒，已终止；部分文件可能未写完")
        }
        readerThread.join(5000)
        writerThread?.join(5000)
        stderrThread.join(2000)
        val exit = process.exitValue()
        streamError.get()?.let { error ->
            throw BackupFailure("STREAM_FAILED", "归档传输失败：${error.message}")
        }
        if (exit == 0) return process.backend
        val error = stderr.toString().trim()
        throw when {
            process.backend == PrivilegeBackend.ROOT && exit == 1 && (error.contains("not allowed", true) || error.contains("denied", true) && error.contains("su", true)) ->
                BackupFailure("ROOT_DENIED", "Root 授权被拒绝：${error.take(300)}")
            error.contains("avc:", true) || error.contains("SELinux", true) ->
                BackupFailure("SELINUX_DENIED", "SELinux 拦截了操作：${error.take(300)}")
            exit in ROOT_SCRIPT_ERRORS -> BackupFailure("ROOT_COMMAND_FAILED", ROOT_SCRIPT_ERRORS.getValue(exit))
            error.contains("Permission denied", true) ->
                BackupFailure("PERMISSION_DENIED", "权限被拒绝：${error.take(300)}")
            else -> BackupFailure("ROOT_COMMAND_FAILED", "$label 命令失败（退出码 $exit）：${error.take(300)}")
        }
    }

    private fun copyBounded(input: InputStream, output: OutputStream, counter: AtomicLong, limit: Long) {
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            if (counter.addAndGet(read.toLong()) > limit) {
                throw IOException("归档超过 ${limit / (1024 * 1024)} MiB 上限")
            }
            output.write(buffer, 0, read)
        }
        output.flush()
    }

    private data class ArchiveListing(
        val entries: List<Map<String, Any?>>,
        val totalBytes: Long,
        val topLevel: Set<String>,
        val unsafe: List<String>,
    )

    /** 以应用自身身份用 toybox tar 列出归档内容（不需要 Root）。 */
    private fun listArchive(archive: File): ArchiveListing {
        val process = ProcessBuilder("tar", "-tzvf", archive.absolutePath)
            .redirectErrorStream(true)
            .start()
        val entries = mutableListOf<Map<String, Any?>>()
        val topLevel = linkedSetOf<String>()
        val unsafe = mutableListOf<String>()
        var total = 0L
        process.inputStream.bufferedReader().useLines { lines ->
            lines.forEach { line ->
                val parts = line.trim().split(Regex("\\s+"), limit = 6)
                if (parts.size < 6) return@forEach
                val size = parts[2].toLongOrNull() ?: return@forEach
                val name = parts[5].substringBefore(" -> ")
                total += size
                if (entries.size < MAX_LISTED_ENTRIES) {
                    entries.add(mapOf("path" to name, "bytes" to size, "mode" to parts[0]))
                }
                val clean = name.removePrefix("./")
                if (clean.startsWith("/") || clean.split('/').any { it == ".." }) {
                    unsafe.add(name)
                } else {
                    val top = clean.substringBefore('/')
                    if (top.isNotEmpty() && top.matches(Regex("^[A-Za-z0-9._-]+$"))) topLevel.add(top)
                    else if (top.isNotEmpty()) unsafe.add(name)
                }
            }
        }
        if (!process.waitFor(60, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            throw BackupFailure("TIMEOUT", "列出归档内容超时")
        }
        if (process.exitValue() != 0) throw BackupFailure("CORRUPT_ARCHIVE", "归档无法读取，可能已损坏")
        return ArchiveListing(entries, total, topLevel, unsafe)
    }

    private fun verifyIntegrity(dir: File, manifest: JSONObject) {
        val files = manifest.optJSONArray("files") ?: throw BackupFailure("CORRUPT_ARCHIVE", "清单缺少文件列表")
        for (i in 0 until files.length()) {
            val item = files.getJSONObject(i)
            val file = File(dir, item.getString("name"))
            if (!file.isFile) throw BackupFailure("CORRUPT_ARCHIVE", "缺少文件 ${item.getString("name")}")
            val expected = item.optString("sha256")
            if (expected.isNotBlank() && sha256(file) != expected) {
                throw BackupFailure("CORRUPT_ARCHIVE", "${item.getString("name")} 校验和不匹配，拒绝恢复")
            }
        }
    }

    private fun restoreCompatibility(manifest: JSONObject, installed: Pair<Long, String>?): Map<String, Any?> {
        val backupVersion = if (manifest.has("versionCode")) manifest.optLong("versionCode") else null
        return when {
            installed == null -> mapOf("allowed" to false, "reason" to "目标应用未安装或对本应用不可见，无法恢复")
            backupVersion != null && installed.first < backupVersion -> mapOf(
                "allowed" to false,
                "reason" to "已安装版本 ${installed.second}(${installed.first}) 低于备份版本 ($backupVersion)，数据降级可能导致应用崩溃，已拒绝",
            )
            backupVersion != null && installed.first > backupVersion -> mapOf(
                "allowed" to true,
                "reason" to "已安装版本高于备份版本；应用通常能迁移旧数据，但不保证",
            )
            else -> mapOf("allowed" to true, "reason" to "版本一致")
        }
    }

    // ---------------------------------------------------------------------
    // 辅助
    // ---------------------------------------------------------------------

    private fun runAsync(result: MethodChannel.Result, block: () -> Map<String, Any?>) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: BackupFailure) {
                mainHandler.post { result.error(e.code, e.message, null) }
            } catch (e: SecurityException) {
                mainHandler.post { result.error("PERMISSION_DENIED", e.message ?: "权限被拒绝", null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("BACKUP_FAILED", e.message ?: "备份操作失败", null) }
            }
        }
    }

    private fun backupDir(id: String): File = File(backupsRoot, id)

    private fun readManifest(dir: File): JSONObject? = runCatching {
        JSONObject(File(dir, MANIFEST_NAME).readText())
    }.getOrNull()

    private fun writeManifest(dir: File, manifest: JSONObject) {
        File(dir, MANIFEST_NAME).writeText(manifest.toString(2))
    }

    private fun fileEntries(dir: File, names: List<String>): JSONArray = JSONArray(
        names.map { name ->
            val file = File(dir, name)
            JSONObject().put("name", name).put("bytes", file.length()).put("sha256", sha256(file))
        }
    )

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun ensureFreeSpace(dir: File) {
        if (freeBytes(dir) < MIN_FREE_BYTES) {
            throw BackupFailure("INSUFFICIENT_STORAGE", "剩余空间不足 ${MIN_FREE_BYTES / (1024 * 1024)} MiB，已取消备份")
        }
    }

    private fun freeBytes(dir: File): Long = runCatching {
        var target = dir
        while (!target.exists()) target = target.parentFile ?: break
        StatFs(target.absolutePath).availableBytes
    }.getOrDefault(0L)

    private fun installedVersion(appPackage: String): Pair<Long, String>? = runCatching {
        val info = activity.packageManager.getPackageInfo(appPackage, 0)
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        code to (info.versionName ?: "")
    }.getOrNull()

    private fun newBackupId(kind: String): String {
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val suffix = (1..4).map { "abcdefghijklmnopqrstuvwxyz0123456789".random() }.joinToString("")
        return "$kind-$stamp-$suffix"
    }

    private fun isValidBackupId(value: String?): Boolean =
        value != null && BACKUP_ID_PATTERN.matches(value)

    private fun isValidPackageName(value: String?): Boolean =
        value != null && value.length <= 255 &&
            Regex("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+$").matches(value)

    private fun isAllowedDirectoryBackupPath(path: String?): Boolean {
        if (path.isNullOrBlank() || !path.startsWith("/") || path.contains('\u0000') ||
            path.split('/').any { it == ".." || it == "." }
        ) return false
        val normalized = path.replace(Regex("/+"), "/").trimEnd('/')
        return ALLOWED_DIRECTORY_ROOTS.any { root -> normalized.startsWith("$root/") }
    }

    private fun permissionFor(category: String?): String? = when (category) {
        "contacts" -> Manifest.permission.READ_CONTACTS
        "sms" -> Manifest.permission.READ_SMS
        "call_log" -> Manifest.permission.READ_CALL_LOG
        else -> null
    }

    private fun permissionLabel(category: String): String = when (category) {
        "contacts" -> "联系人"
        "sms" -> "短信"
        else -> "通话记录"
    }

    private fun isGranted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED

    private fun shellQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"

    private fun vcardEscape(value: String): String = value
        .replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace(",", "\\,")
        .replace(";", "\\;")

    private fun writeJsonArray(out: BufferedWriter, items: List<JSONObject>) {
        out.write("[")
        items.forEachIndexed { index, item ->
            if (index > 0) out.write(",")
            out.write(item.toString())
        }
        out.write("]")
    }

    private fun Cursor.stringOrEmpty(index: Int): String =
        if (isNull(index)) "" else getString(index) ?: ""

    private fun smsType(type: Int): String = when (type) {
        1 -> "inbox"
        2 -> "sent"
        3 -> "draft"
        4 -> "outbox"
        5 -> "failed"
        6 -> "queued"
        else -> "other"
    }

    private fun callType(type: Int): String = when (type) {
        CallLog.Calls.INCOMING_TYPE -> "incoming"
        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
        CallLog.Calls.MISSED_TYPE -> "missed"
        5 -> "rejected"
        6 -> "blocked"
        else -> "other"
    }

    companion object {
        const val PERMISSION_REQUEST_CODE = 9201
        private const val ARCHIVE_NAME = "data.tar.gz"
        private const val MANIFEST_NAME = "manifest.json"
        private const val MAX_LISTED_BACKUPS = 100
        private const val MAX_LISTED_ENTRIES = 5000
        private const val PREVIEW_ENTRY_COUNT = 20
        private const val MAX_PERSONAL_ITEMS = 50000
        private const val ROOT_TIMEOUT_SECONDS = 180L
        private const val MAX_ARCHIVE_BYTES = 2L * 1024 * 1024 * 1024
        private const val MIN_FREE_BYTES = 200L * 1024 * 1024
        private val APP_DATA_SCOPES = setOf("config", "full", "apk")
        private val PROTECTED_APP_DIRS = setOf("cache", "code_cache", "lib")
        private val BACKUP_ID_PATTERN = Regex("^(personal|app|prerestore|dir|apk)-\\d{8}-\\d{6}-[a-z0-9]{4}$")
        private val ALLOWED_DIRECTORY_ROOTS = listOf("/sdcard", "/storage/emulated/0", "/data/local/tmp")
        private val ROOT_SCRIPT_ERRORS = mapOf(
            20 to "无法解析 /data/user/0",
            21 to "目标应用数据目录不存在",
            22 to "应用数据目录经符号链接跳转到预期之外的位置，已拒绝",
            23 to "应用数据目录不存在",
            24 to "无法进入目标目录",
            25 to "没有可备份的目录（应用可能尚未生成数据）",
            26 to "源目录不存在",
            27 to "源目录是符号链接，已拒绝",
            28 to "无法读取应用数据目录属主",
            29 to "目标目录是符号链接，已拒绝覆盖",
            30 to "删除旧数据失败，恢复中止（恢复前快照已保留）",
            31 to "解压归档失败（恢复前快照已保留，可用它撤销）",
        )
    }
}
