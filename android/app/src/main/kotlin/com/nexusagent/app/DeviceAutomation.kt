package com.nexusagent.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.provider.DocumentsContract
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.UUID

/**
 * 设备自动化触发器（MethodChannel `nexus/device_automation`）。
 *
 * 只负责“什么时候该提醒用户”，从不在后台执行设备动作：
 * - 规则由 Dart 侧 DeviceAutomationService 同步到这里（JSON）。
 * - AlarmManager 定时唤醒 [DeviceAutomationReceiver] 评估时间、Wi-Fi、电量触发条件。
 * - 条件满足时只记录一条待确认触发（fire）并发通知；用户点通知回到应用，
 *   由前台逐项预览、确认后再通过既有 android_device 白名单执行。
 * - Wi-Fi/电量为边沿触发：从“不满足”变为“满足”时才触发一次，避免反复提醒。
 */
object DeviceAutomationStore {
    private const val PREFS = "device_automation"
    private const val KEY_RULES = "rules"
    private const val KEY_STATE = "trigger_state"
    private const val KEY_PENDING = "pending_fires"
    private const val KEY_LAUNCH_FIRE = "launch_fire"
    private const val KEY_LAST_EVALUATION = "last_evaluation"
    private const val MAX_PENDING = 20
    private const val PENDING_TTL_MS = 12 * 60 * 60 * 1000L
    const val POLL_INTERVAL_MS = 15 * 60 * 1000L
    private const val TIME_GRACE_MS = 6 * 60 * 60 * 1000L
    const val CHANNEL_ID = "nexus_automation"
    const val EXTRA_FIRE_ID = "nexus_automation_fire_id"
    const val ACTION_EVALUATE = "com.nexusagent.app.AUTOMATION_EVALUATE"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun rules(context: Context): JSONArray =
        runCatching { JSONArray(prefs(context).getString(KEY_RULES, "[]")) }
            .getOrDefault(JSONArray())

    fun saveRules(context: Context, json: String) {
        val parsed = JSONArray(json)
        val ids = (0 until parsed.length()).map { parsed.getJSONObject(it).optString("id") }.toSet()
        val state = state(context)
        state.keys().asSequence().toList().filter { it !in ids }.forEach { state.remove(it) }
        prefs(context).edit()
            .putString(KEY_RULES, parsed.toString())
            .putString(KEY_STATE, state.toString())
            .apply()
    }

    private fun state(context: Context): JSONObject =
        runCatching { JSONObject(prefs(context).getString(KEY_STATE, "{}")) }
            .getOrDefault(JSONObject())

    private fun saveState(context: Context, state: JSONObject) {
        prefs(context).edit().putString(KEY_STATE, state.toString()).apply()
    }

    fun pendingFires(context: Context): JSONArray {
        val now = System.currentTimeMillis()
        val all = runCatching { JSONArray(prefs(context).getString(KEY_PENDING, "[]")) }
            .getOrDefault(JSONArray())
        val kept = JSONArray()
        for (i in 0 until all.length()) {
            val fire = all.getJSONObject(i)
            if (now - fire.optLong("firedAtMs") <= PENDING_TTL_MS) kept.put(fire)
        }
        if (kept.length() != all.length()) {
            prefs(context).edit().putString(KEY_PENDING, kept.toString()).apply()
        }
        return kept
    }

    private fun addPendingFire(context: Context, fire: JSONObject) {
        val pending = pendingFires(context)
        val merged = JSONArray()
        // 同一规则只保留最新一条待确认触发，避免用户离线期间堆积。
        for (i in 0 until pending.length()) {
            val item = pending.getJSONObject(i)
            if (item.optString("ruleId") != fire.optString("ruleId")) merged.put(item)
        }
        merged.put(fire)
        val trimmed = JSONArray()
        val start = (merged.length() - MAX_PENDING).coerceAtLeast(0)
        for (i in start until merged.length()) trimmed.put(merged.get(i))
        prefs(context).edit().putString(KEY_PENDING, trimmed.toString()).apply()
    }

    fun resolveFire(context: Context, fireId: String): Boolean {
        val pending = pendingFires(context)
        val kept = JSONArray()
        var found = false
        for (i in 0 until pending.length()) {
            val fire = pending.getJSONObject(i)
            if (fire.optString("fireId") == fireId) found = true else kept.put(fire)
        }
        prefs(context).edit().putString(KEY_PENDING, kept.toString()).apply()
        notificationManager(context).cancel(fireId.hashCode())
        return found
    }

    fun setLaunchFire(context: Context, fireId: String?) {
        prefs(context).edit().putString(KEY_LAUNCH_FIRE, fireId).apply()
    }

    fun consumeLaunchFire(context: Context): String? {
        val value = prefs(context).getString(KEY_LAUNCH_FIRE, null)
        prefs(context).edit().remove(KEY_LAUNCH_FIRE).apply()
        return value
    }

    fun lastEvaluation(context: Context): JSONObject? =
        prefs(context).getString(KEY_LAST_EVALUATION, null)?.let {
            runCatching { JSONObject(it) }.getOrNull()
        }

    /** 当前触发条件状态；SSID 需要定位权限，拿不到时明确返回原因而不是空字符串。 */
    fun snapshot(context: Context): Map<String, Any?> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        val percent = if (level >= 0 && scale > 0) level * 100 / scale else -1
        val wifi = currentSsid(context)
        return mapOf(
            "batteryPercent" to percent,
            "charging" to charging,
            "ssid" to wifi.first,
            "ssidStatus" to wifi.second,
            "fineLocationGranted" to granted(context, Manifest.permission.ACCESS_FINE_LOCATION),
            "backgroundLocationGranted" to (Build.VERSION.SDK_INT < 29 ||
                granted(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)),
            "notificationsGranted" to (Build.VERSION.SDK_INT < 33 ||
                granted(context, Manifest.permission.POST_NOTIFICATIONS)),
        )
    }

    private fun granted(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /** @return (ssid 或 null, 状态说明) */
    @Suppress("DEPRECATION")
    private fun currentSsid(context: Context): Pair<String?, String> {
        if (!granted(context, Manifest.permission.ACCESS_FINE_LOCATION)) {
            return null to "location_permission_required"
        }
        val manager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return null to "wifi_unavailable"
        if (!manager.isWifiEnabled) return null to "wifi_disabled"
        val raw = manager.connectionInfo?.ssid ?: return null to "not_connected"
        val ssid = raw.trim('"')
        return when {
            ssid.isBlank() || ssid == "<unknown ssid>" -> null to "ssid_hidden_or_location_off"
            else -> ssid to "ok"
        }
    }

    /**
     * 评估全部启用规则。返回新产生的触发数量。
     * 结果写入 last_evaluation，UI 可显示“最近一次检查时间与原因”。
     */
    fun evaluate(context: Context, reason: String): Int {
        val rules = rules(context)
        val state = state(context)
        val snapshot = snapshot(context)
        val now = System.currentTimeMillis()
        var fired = 0
        val skipped = JSONArray()
        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i)
            if (!rule.optBoolean("enabled", true)) continue
            val id = rule.optString("id")
            val trigger = rule.optJSONObject("trigger") ?: continue
            val ruleState = state.optJSONObject(id) ?: JSONObject()
            val description: String? = when (trigger.optString("type")) {
                "time" -> evaluateTime(trigger, ruleState, now, rule.optLong("createdAtMs", 0))
                "wifi_connected" -> {
                    val target = trigger.optString("ssid")
                    val ssid = snapshot["ssid"] as String?
                    if (ssid == null) {
                        skipped.put(JSONObject().put("ruleId", id).put("reason", snapshot["ssidStatus"]))
                        null
                    } else {
                        val connected = ssid == target
                        val was = ruleState.optBoolean("connected", false)
                        ruleState.put("connected", connected)
                        if (connected && !was) "已连接 Wi-Fi「$target」" else null
                    }
                }
                "battery_below" -> {
                    val threshold = trigger.optInt("threshold", 20)
                    val percent = snapshot["batteryPercent"] as Int
                    val charging = snapshot["charging"] as Boolean
                    val armed = ruleState.optBoolean("armed", true)
                    when {
                        percent < 0 -> {
                            skipped.put(JSONObject().put("ruleId", id).put("reason", "battery_unavailable"))
                            null
                        }
                        percent >= threshold + 2 || charging -> {
                            ruleState.put("armed", true)
                            null
                        }
                        percent < threshold && armed -> {
                            ruleState.put("armed", false)
                            "电量降至 $percent%（低于 $threshold%）"
                        }
                        else -> null
                    }
                }
                else -> null
            }
            if (description != null) {
                ruleState.put("lastFiredAtMs", now)
                val fire = JSONObject()
                    .put("fireId", "fire_" + UUID.randomUUID().toString().replace("-", "").take(16))
                    .put("ruleId", id)
                    .put("ruleName", rule.optString("name"))
                    .put("trigger", description)
                    .put("firedAtMs", now)
                addPendingFire(context, fire)
                notifyFire(context, fire)
                fired++
            }
            state.put(id, ruleState)
        }
        saveState(context, state)
        prefs(context).edit().putString(
            KEY_LAST_EVALUATION,
            JSONObject()
                .put("atMs", now)
                .put("reason", reason)
                .put("fired", fired)
                .put("skipped", skipped)
                .toString()
        ).apply()
        schedule(context)
        return fired
    }

    private fun evaluateTime(trigger: JSONObject, ruleState: JSONObject, now: Long, createdAtMs: Long): String? {
        val latest = latestOccurrence(trigger, now) ?: return null
        val lastFired = ruleState.optLong("lastFiredAtMs", createdAtMs)
        if (latest <= lastFired || now - latest > TIME_GRACE_MS) return null
        val hour = trigger.optInt("hour")
        val minute = trigger.optInt("minute")
        return "到达设定时间 %02d:%02d".format(hour, minute)
    }

    private fun latestOccurrence(trigger: JSONObject, now: Long): Long? {
        val days = trigger.optJSONArray("days")
        val allowed = (0 until (days?.length() ?: 0)).map { days!!.getInt(it) }.toSet()
        for (daysAgo in 0..7) {
            val cal = Calendar.getInstance().apply {
                timeInMillis = now
                add(Calendar.DAY_OF_YEAR, -daysAgo)
                set(Calendar.HOUR_OF_DAY, trigger.optInt("hour"))
                set(Calendar.MINUTE, trigger.optInt("minute"))
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (allowed.isNotEmpty() && isoWeekday(cal) !in allowed) continue
            if (cal.timeInMillis <= now) return cal.timeInMillis
        }
        return null
    }

    private fun nextOccurrence(trigger: JSONObject, now: Long): Long? {
        val days = trigger.optJSONArray("days")
        val allowed = (0 until (days?.length() ?: 0)).map { days!!.getInt(it) }.toSet()
        for (daysAhead in 0..7) {
            val cal = Calendar.getInstance().apply {
                timeInMillis = now
                add(Calendar.DAY_OF_YEAR, daysAhead)
                set(Calendar.HOUR_OF_DAY, trigger.optInt("hour"))
                set(Calendar.MINUTE, trigger.optInt("minute"))
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (allowed.isNotEmpty() && isoWeekday(cal) !in allowed) continue
            if (cal.timeInMillis > now) return cal.timeInMillis
        }
        return null
    }

    private fun isoWeekday(cal: Calendar): Int {
        val day = cal.get(Calendar.DAY_OF_WEEK) // 1 = Sunday
        return if (day == Calendar.SUNDAY) 7 else day - 1
    }

    /** 下一次唤醒：最近的时间规则，或有 Wi-Fi/电量规则时 15 分钟后。无启用规则则取消。 */
    fun schedule(context: Context) {
        val rules = rules(context)
        val now = System.currentTimeMillis()
        var next: Long? = null
        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i)
            if (!rule.optBoolean("enabled", true)) continue
            val trigger = rule.optJSONObject("trigger") ?: continue
            val candidate = when (trigger.optString("type")) {
                "time" -> nextOccurrence(trigger, now)
                "wifi_connected", "battery_below" -> now + POLL_INTERVAL_MS
                else -> null
            } ?: continue
            next = if (next == null) candidate else minOf(next, candidate)
        }
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = evaluationIntent(context)
        if (next == null) {
            alarm.cancel(pending)
            return
        }
        // 非精确闹钟：不申请 SCHEDULE_EXACT_ALARM，系统可能延后数分钟。
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
    }

    private fun evaluationIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        4201,
        Intent(context, DeviceAutomationReceiver::class.java).setAction(ACTION_EVALUATE),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun notificationManager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun notifyFire(context: Context, fire: JSONObject) {
        val manager = notificationManager(context)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "设备自动化确认", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "自动化规则触发后需要你确认才会执行"
                }
            )
        }
        val fireId = fire.optString("fireId")
        val open = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_FIRE_ID, fireId)
        val content = PendingIntent.getActivity(
            context,
            fireId.hashCode(),
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("自动化待确认 · ${fire.optString("ruleName")}")
            .setContentText("${fire.optString("trigger")}。点按查看将执行的操作并确认；未确认不会执行。")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "${fire.optString("trigger")}。点按查看将执行的操作并确认；未确认不会执行。12 小时后自动过期。"
                )
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(content)
            .build()
        runCatching { manager.notify(fireId.hashCode(), notification) }
    }

    /**
     * 列出已授权 SAF 目录的第一层文件（不递归），用于“清理目录”类自动化动作。
     * 只返回用户持久授权过的树 URI 下的文档；最多 [limit] 项，同时报告总数和总大小。
     */
    fun listFolderFiles(
        context: Context,
        treeUri: String,
        modifiedBeforeMs: Long?,
        extension: String?,
        limit: Int,
    ): Map<String, Any?> {
        val tree = Uri.parse(treeUri)
        val authorized = context.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isWritePermission
        }
        if (!authorized) throw SecurityException("该目录没有持久写入授权，请先在应用内重新授权")
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree)
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val normalizedExtension = extension?.trim()?.trimStart('.')?.lowercase()?.ifBlank { null }
        val files = mutableListOf<Map<String, Any?>>()
        var matched = 0
        var totalBytes = 0L
        context.contentResolver.query(children, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val mime = cursor.getString(2) ?: ""
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) continue
                val name = cursor.getString(1) ?: continue
                val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                val modified = if (cursor.isNull(4)) 0L else cursor.getLong(4)
                if (modifiedBeforeMs != null && modified >= modifiedBeforeMs) continue
                if (normalizedExtension != null &&
                    !name.lowercase().endsWith(".$normalizedExtension")
                ) continue
                matched++
                totalBytes += size
                if (files.size < limit) {
                    files.add(
                        mapOf(
                            "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0)).toString(),
                            "name" to name,
                            "size" to size,
                            "modifiedMs" to modified,
                        )
                    )
                }
            }
        } ?: throw SecurityException("系统拒绝列出该目录")
        return mapOf(
            "files" to files,
            "matchedCount" to matched,
            "totalBytes" to totalBytes,
            "remaining" to (matched - files.size).coerceAtLeast(0),
        )
    }

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "syncRules" -> {
                    val json = call.argument<String>("rules") ?: "[]"
                    saveRules(context, json)
                    schedule(context)
                    result.success(mapOf("synced" to true))
                }
                "evaluateNow" -> result.success(mapOf("fired" to evaluate(context, "foreground")))
                "pendingFires" -> result.success(pendingFires(context).toString())
                "resolveFire" -> {
                    val fireId = call.argument<String>("fireId")
                    if (fireId.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "fireId 无效", null)
                    } else {
                        result.success(mapOf("resolved" to resolveFire(context, fireId)))
                    }
                }
                "consumeLaunchFire" -> result.success(consumeLaunchFire(context))
                "triggerStatus" -> result.success(
                    snapshot(context) + mapOf("lastEvaluation" to lastEvaluation(context)?.toString())
                )
                "listFolderFiles" -> {
                    val treeUri = call.argument<String>("treeUri")
                    if (treeUri.isNullOrBlank() || !treeUri.startsWith("content://")) {
                        result.error("INVALID_ARGS", "treeUri 无效", null)
                        return
                    }
                    val before = call.argument<Number>("modifiedBeforeMs")?.toLong()
                    val limit = (call.argument<Number>("limit")?.toInt() ?: 100).coerceIn(1, 100)
                    result.success(
                        listFolderFiles(context, treeUri, before, call.argument<String>("extension"), limit)
                    )
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "权限被拒绝", null)
        } catch (e: Exception) {
            result.error("AUTOMATION_FAILED", e.message ?: "自动化操作失败", null)
        }
    }
}

/** 闹钟、开机和应用更新后重新评估并排程；只产生待确认触发，不执行设备动作。 */
class DeviceAutomationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reason = when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> "boot"
            Intent.ACTION_MY_PACKAGE_REPLACED -> "package_replaced"
            DeviceAutomationStore.ACTION_EVALUATE -> "alarm"
            else -> return
        }
        val pending = goAsync()
        Thread {
            try {
                DeviceAutomationStore.evaluate(context.applicationContext, reason)
            } catch (_: Exception) {
                runCatching { DeviceAutomationStore.schedule(context.applicationContext) }
            } finally {
                pending.finish()
            }
        }.start()
    }
}
