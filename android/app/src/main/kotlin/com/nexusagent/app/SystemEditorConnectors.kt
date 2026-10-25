package com.nexusagent.app

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.CalendarContract
import android.provider.ContactsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Public editor handoff only. No provider read/write and no new permissions. */
class SystemEditorConnectors(private val activity: Activity) {
    private val pm get() = activity.packageManager

    private fun base(kind: String): Intent = when (kind) {
        "calendar" -> Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI)
        "contacts" -> Intent(Intent.ACTION_INSERT).setType(ContactsContract.RawContacts.CONTENT_TYPE)
        else -> throw IllegalArgumentException("不支持的系统编辑器")
    }

    @Suppress("DEPRECATION")
    private fun version(packageName: String): String {
        val info = pm.getPackageInfo(packageName, 0)
        return if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode.toString()
        else info.versionCode.toString()
    }

    @Suppress("DEPRECATION")
    private fun handlers(kind: String): List<Map<String, String>> =
        pm.queryIntentActivities(base(kind), PackageManager.MATCH_DEFAULT_ONLY)
            .filter { it.activityInfo.exported && it.activityInfo.enabled && it.activityInfo.applicationInfo.enabled }
            .distinctBy { "${it.activityInfo.packageName}/${it.activityInfo.name}" }
            .take(40)
            .map {
                val info = it.activityInfo
                mapOf("packageName" to info.packageName, "activityName" to info.name,
                    "version" to version(info.packageName), "label" to it.loadLabel(pm).toString().take(200))
            }

    private fun text(fields: Map<*, *>, key: String, limit: Int, required: Boolean = true): String? {
        val value = fields[key]
        if (value == null && !required && !fields.containsKey(key)) return null
        require(value is String && value.isNotBlank() && value.length <= limit &&
            value.none { it.code < 32 || it.code == 127 }) { "编辑器字段无效" }
        return value.trim()
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        var attempted = false
        try {
            val kind = call.argument<String>("kind") ?: throw IllegalArgumentException()
            if (call.method == "listSystemEditorHandlers") {
                result.success(handlers(kind))
                return
            }
            require(call.method == "openSystemEditor")
            val packageName = call.argument<String>("packageName") ?: throw IllegalArgumentException()
            val activityName = call.argument<String>("activityName") ?: throw IllegalArgumentException()
            val expectedVersion = call.argument<String>("receiverVersion") ?: throw IllegalArgumentException()
            val deadline = call.argument<Number>("deadlineMs")?.toLong() ?: throw IllegalArgumentException()
            val now = System.currentTimeMillis()
            if (deadline < now || deadline - now > 10_000) {
                result.error("STALE_HANDOFF", "交接已过期，请重新预览", null)
                return
            }
            val receiver = handlers(kind).firstOrNull {
                it["packageName"] == packageName && it["activityName"] == activityName
            }
            if (receiver == null || receiver["version"] != expectedVersion) {
                result.error("RECEIVER_CHANGED", "接收方已变化或不可用，请重新选择并预览", null)
                return
            }
            val fields = call.argument<Map<*, *>>("fields") ?: throw IllegalArgumentException()
            val intent = base(kind).setComponent(ComponentName(packageName, activityName))
            when (kind) {
                "calendar" -> {
                    require(fields.keys.all { it in setOf("title", "startMillis", "endMillis", "location", "description") })
                    val start = fields["startMillis"]
                    val end = fields["endMillis"]
                    require((start is Long || start is Int) && (end is Long || end is Int))
                    val startMs = (start as Number).toLong()
                    val endMs = (end as Number).toLong()
                    require(startMs in -62135596800000L..253402300799999L &&
                        endMs in -62135596800000L..253402300799999L && endMs > startMs)
                    intent.putExtra(CalendarContract.Events.TITLE, text(fields, "title", 200))
                    intent.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
                    intent.putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMs)
                    text(fields, "location", 500, false)?.let { intent.putExtra(CalendarContract.Events.EVENT_LOCATION, it) }
                    text(fields, "description", 4000, false)?.let { intent.putExtra(CalendarContract.Events.DESCRIPTION, it) }
                }
                "contacts" -> {
                    require(fields.keys.all { it in setOf("name", "phone", "email") })
                    intent.putExtra(ContactsContract.Intents.Insert.NAME, text(fields, "name", 200))
                    text(fields, "phone", 80, false)?.let { intent.putExtra(ContactsContract.Intents.Insert.PHONE, it) }
                    text(fields, "email", 254, false)?.let { intent.putExtra(ContactsContract.Intents.Insert.EMAIL, it) }
                }
            }
            // Do not use activity-result success as proof that the user saved.
            attempted = true
            activity.startActivity(intent)
            result.success(mapOf("handoffRequested" to true, "businessCompleted" to false,
                "needsUserCompletion" to true, "automaticRetryAllowed" to false))
        } catch (_: android.content.ActivityNotFoundException) {
            result.error("RECEIVER_CHANGED", "接收方不可用，请重新预览", null)
        } catch (_: SecurityException) {
            result.error("PERMISSION_DENIED", "系统不允许向此编辑器交接", null)
        } catch (_: Exception) {
            result.error(if (attempted) "HANDOFF_UNKNOWN" else "INVALID_ARGS",
                if (attempted) "交接状态未知，请先检查系统界面，勿自动重试" else "编辑器参数无效", null)
        }
    }
}
