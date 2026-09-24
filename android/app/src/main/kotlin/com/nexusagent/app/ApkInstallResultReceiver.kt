package com.nexusagent.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.widget.Toast
import org.json.JSONObject

/**
 * 安装包恢复（PackageInstaller 会话）状态回调。
 *
 * - STATUS_PENDING_USER_ACTION：拉起系统安装确认界面，由用户决定是否安装。
 * - 成功/失败：记录最后一次结果（backup_inspect 返回 lastInstallResult）并 Toast 提示。
 */
class ApkInstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_INSTALL_STATUS) return
        val backupId = intent.getStringExtra(EXTRA_BACKUP_ID)
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                record(context, backupId, "pending_user_action", message)
                if (confirm != null) {
                    runCatching {
                        context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }.onFailure {
                        record(context, backupId, "failed", "无法打开系统安装确认界面：${it.message}")
                    }
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                record(context, backupId, "success", message)
                Toast.makeText(context, "安装包恢复完成", Toast.LENGTH_SHORT).show()
            }
            else -> {
                val label = when (status) {
                    PackageInstaller.STATUS_FAILURE_ABORTED -> "用户取消了安装"
                    PackageInstaller.STATUS_FAILURE_CONFLICT -> "与已安装应用冲突（签名或版本）"
                    PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "与本设备不兼容"
                    PackageInstaller.STATUS_FAILURE_STORAGE -> "存储空间不足"
                    PackageInstaller.STATUS_FAILURE_BLOCKED -> "安装被系统或策略阻止"
                    PackageInstaller.STATUS_FAILURE_INVALID -> "安装包无效或不完整"
                    else -> "安装失败"
                }
                val detail = listOfNotNull(label, message).joinToString("：")
                record(context, backupId, if (status == PackageInstaller.STATUS_FAILURE_ABORTED) "aborted" else "failed", detail)
                Toast.makeText(context, "安装包恢复失败：$detail", Toast.LENGTH_LONG).show()
            }
        }
    }

    companion object {
        const val ACTION_INSTALL_STATUS = "com.nexusagent.app.APK_INSTALL_STATUS"
        const val EXTRA_BACKUP_ID = "nexus_backup_id"
        private const val PREFS = "nexus_apk_restore"

        private fun record(context: Context, backupId: String?, status: String, message: String?) {
            if (backupId == null) return
            val value = JSONObject()
                .put("status", status)
                .put("message", message ?: "")
                .put("atMs", System.currentTimeMillis())
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(backupId, value.toString()).apply()
        }

        fun lastResult(context: Context, backupId: String): Map<String, Any?>? {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(backupId, null) ?: return null
            return runCatching {
                val json = JSONObject(raw)
                mapOf(
                    "status" to json.optString("status"),
                    "message" to json.optString("message"),
                    "atMs" to json.optLong("atMs"),
                )
            }.getOrNull()
        }
    }
}
