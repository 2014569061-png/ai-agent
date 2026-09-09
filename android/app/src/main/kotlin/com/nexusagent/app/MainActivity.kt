package com.nexusagent.app

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// 使用 FlutterFragmentActivity 以支持 local_auth 的 BiometricPrompt。
class MainActivity : FlutterFragmentActivity() {
    // G1 Termux 桥：RUN_COMMAND 是 dangerous 权限，需运行时请求；请求期间挂起 method 调用。
    private var pendingTermux: MethodChannel.Result? = null
    private var pendingTermuxCommand: String? = null
    private var pendingTermuxTimeout: Long = 300000L
    private var builtinLinuxRunner: BuiltinLinuxRunner? = null

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 9001) return
        val result = pendingTermux
        pendingTermux = null
        val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (result == null) return
        if (!granted) {
            result.error("PERMISSION_DENIED", "用户拒绝了 Termux RUN_COMMAND 权限", null)
            return
        }
        TermuxBridge.launch(this, pendingTermuxCommand ?: "")
        result.success(mapOf("started" to true))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        builtinLinuxRunner = BuiltinLinuxRunner(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexus/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_PATH", "更新文件路径为空", null)
                        } else {
                            installApk(path, result)
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
        // G1 Termux 桥：go/bash 等命令转交 Termux 沙箱执行。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexus/termux_bridge")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTermuxInstalled" -> {
                        try {
                            packageManager.getPackageInfo("com.termux", 0)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "runInTermux" -> {                        val command = call.argument<String>("command")
                        // Dart int 经 codec 落为 Integer，按 Number 取再转 Long，避免类型强转崩溃
                        val timeoutMs = (call.argument<Number>("timeoutMs") ?: 300000L).toLong()
                        if (command == null) {
                            result.error("INVALID_ARGS", "command is null", null)
                            return@setMethodCallHandler
                        }
                        val perm = "com.termux.permission.RUN_COMMAND"
                        if (ContextCompat.checkSelfPermission(this, perm)
                        != PackageManager.PERMISSION_GRANTED) {
                            pendingTermux = result
                            pendingTermuxCommand = command
                            pendingTermuxTimeout = timeoutMs
                            requestPermissions(arrayOf(perm), 9001)
                            return@setMethodCallHandler
                        }
                        try {
                            TermuxBridge.launch(this, command)
                            result.success(mapOf("started" to true))
                        } catch (e: Exception) {
                            result.error("BRIDGE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexus/builtin_linux")
            .setMethodCallHandler { call, result ->
                val runner = builtinLinuxRunner
                if (runner == null) {
                    result.error("UNAVAILABLE", "内置 Linux Runner 尚未初始化", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "inspect" -> result.success(runner.inspect())
                    "run" -> {
                        val command = call.argument<String>("command")
                        val workingDirectory = call.argument<String>("workingDirectory")
                        val rootfsPath = call.argument<String>("rootfsPath")
                        val runtimeLibraryPath = call.argument<String>("runtimeLibraryPath")
                        if (command == null || workingDirectory == null || rootfsPath == null || runtimeLibraryPath == null) {
                            result.error("INVALID_ARGS", "command、workingDirectory、rootfsPath、runtimeLibraryPath 不能为空", null)
                            return@setMethodCallHandler
                        }
                        val timeoutMs = (call.argument<Number>("timeoutMs") ?: 300000L).toLong()
                        val maxOutputBytes = (call.argument<Number>("maxOutputBytes") ?: 131072).toInt()
                        runner.run(
                            command = command,
                            workingDirectory = workingDirectory,
                            rootfsPath = rootfsPath,
                            runtimeLibraryPath = runtimeLibraryPath,
                            timeoutMs = timeoutMs,
                            maxOutputBytes = maxOutputBytes,
                        ) { response -> result.success(response) }
                    }
                    "stop" -> {
                        runner.stop()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        builtinLinuxRunner?.stop()
        super.onDestroy()
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists() || !file.isFile || file.length() < 4L) {
            result.error("INVALID_APK", "更新文件不存在或不完整", null)
            return
        }

        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "nexus/accessibility").setMethodCallHandler { call, result ->
            if (call.method == "isEnabled") {
                val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                    ?.split(':')?.any { it.contains(packageName, ignoreCase = true) } == true
                result.success(enabled)
            } else result.notImplemented()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                        data = Uri.parse("package:$packageName")
                    }
                )
                result.success(mapOf("status" to "permission_required"))
            } catch (e: ActivityNotFoundException) {
                result.error(
                    "UNKNOWN_SOURCES_SETTINGS_UNAVAILABLE",
                    "无法打开安装未知应用设置",
                    null
                )
            } catch (e: Exception) {
                result.error(
                    "UNKNOWN_SOURCES_SETTINGS_UNAVAILABLE",
                    e.message ?: "无法打开安装未知应用设置",
                    null
                )
            }
            return
        }

        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (e: IllegalArgumentException) {
            result.error("INVALID_APK", "无法读取更新文件", null)
            return
        }

        val installIntent = createInstallIntent(uri, Intent.ACTION_INSTALL_PACKAGE)
        val fallbackIntent = createInstallIntent(uri, Intent.ACTION_VIEW)
        val intent = when {
            installIntent.resolveActivity(packageManager) != null -> installIntent
            fallbackIntent.resolveActivity(packageManager) != null -> fallbackIntent
            else -> null
        }
        if (intent == null) {
            result.error("NO_INSTALLER", "系统没有可用的 APK 安装器", null)
            return
        }

        try {
            startActivity(intent)
            result.success(mapOf("status" to "started"))
        } catch (e: SecurityException) {
            result.error("INSTALL_PERMISSION_DENIED", "系统拒绝读取更新文件", null)
        } catch (e: ActivityNotFoundException) {
            result.error("NO_INSTALLER", "系统没有可用的 APK 安装器", null)
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message ?: "系统安装器启动失败", null)
        }
    }

    private fun createInstallIntent(uri: Uri, action: String): Intent {
        return Intent(action).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            clipData = ClipData.newRawUri("NEXUS update", uri)
        }
    }
}
