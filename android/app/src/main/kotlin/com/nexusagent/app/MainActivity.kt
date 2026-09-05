package com.nexusagent.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// 使用 FlutterFragmentActivity 以支持 local_auth 的 BiometricPrompt。
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexus/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_PATH", "path is null", null)
                        } else {
                            try {
                                val file = File(path)
                                val uri = FileProvider.getUriForFile(
                                    this,
                                    "$packageName.fileprovider",
                                    file
                                )
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // 电池优化豁免：定时任务在激进省电 ROM 上需要系统白名单才能按时触发。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexus/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            ).apply { data = Uri.parse("package:$packageName") }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // 部分 ROM 不支持直接授权 action，退回系统电池优化列表页。
                            try {
                                startActivity(
                                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                )
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("UNAVAILABLE", e2.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
