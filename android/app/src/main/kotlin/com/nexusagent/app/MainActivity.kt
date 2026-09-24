package com.nexusagent.app

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.media.AudioManager
import android.app.ActivityManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask

// 使用 FlutterFragmentActivity 以支持 local_auth 的 BiometricPrompt。
class MainActivity : FlutterFragmentActivity() {
    // G1 Termux 桥：RUN_COMMAND 是 dangerous 权限，需运行时请求；请求期间挂起 method 调用。
    private var pendingTermux: MethodChannel.Result? = null
    private var pendingTermuxCommand: String? = null
    private var pendingTermuxTimeout: Long = 300000L
    private var builtinLinuxRunner: BuiltinLinuxRunner? = null
    private val deviceFilesPrefs: SharedPreferences by lazy {
        getSharedPreferences("device_files", MODE_PRIVATE)
    }
    private val safSearchIndex: SafSearchIndex by lazy { SafSearchIndex(this) }
    private var pendingDirectoryPicker: MethodChannel.Result? = null
    private val deviceSearchExecutor = Executors.newSingleThreadExecutor()
    private val appPrivateDataExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingSearches = mutableMapOf<String, MethodChannel.Result>()
    private val cancelledSearches = mutableSetOf<String>()
    private val deviceBackupManager: DeviceBackupManager by lazy { DeviceBackupManager(this) }
    private var automationChannel: MethodChannel? = null
    // 免 Root 降级：Root → Shizuku → 系统 API → 设置页；设备控制中的特权方法都经由它执行。
    private val privilegedControl: PrivilegedDeviceControl by lazy { PrivilegedDeviceControl(this) }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        captureAutomationFire(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureAutomationFire(intent)
    }

    /**
     * 自动化通知点击：记录待确认触发，前台 Dart 侧负责预览与确认。
     *
     * 冷启动时 Dart 还没注册回调，invokeMethod 会丢失，因此总是先写入
     * launch fire；Dart 启动时或收到 automationFired 后调用 consumeLaunchFire 清除。
     */
    private fun captureAutomationFire(intent: Intent?) {
        val fireId = intent?.getStringExtra(DeviceAutomationStore.EXTRA_FIRE_ID) ?: return
        intent.removeExtra(DeviceAutomationStore.EXTRA_FIRE_ID)
        DeviceAutomationStore.setLaunchFire(this, fireId)
        automationChannel?.invokeMethod("automationFired", fireId)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (deviceBackupManager.onRequestPermissionsResult(requestCode, grantResults)) return
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
        PrivilegeManager.init(this)
        builtinLinuxRunner = BuiltinLinuxRunner(this)
        // 备份与恢复：独立通道与后台线程，Root 流式 tar，恢复前自动快照。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexus/device_backup")
            .setMethodCallHandler { call, result -> deviceBackupManager.handle(call, result) }
        // 设备自动化：只同步规则、查询触发状态与待确认触发，不在后台执行动作。
        automationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nexus/device_automation"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                DeviceAutomationStore.handle(applicationContext, call, result)
            }
        }
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexus/device_control")
            .setMethodCallHandler { call, result ->
                if (privilegedControl.handles(call.method)) {
                    privilegedControl.handle(call, result)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "listApps" -> result.success(listLaunchableApps())
                    "deviceInfo" -> result.success(deviceInfo())
                    "storageInfo" -> result.success(storageInfo())
                    "networkInfo" -> result.success(networkInfo())
                    "openVpnSettings" -> openSettingsPage(
                        Intent(Settings.ACTION_VPN_SETTINGS),
                        result,
                    )
                    "appInfo" -> {
                        val appPackage = call.argument<String>("packageName")
                        if (appPackage.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "packageName 不能为空", null)
                        } else {
                            appInfo(appPackage, result)
                        }
                    }
                    "systemStatus" -> result.success(systemStatus())
                    "trafficInfo" -> result.success(trafficInfo())
                    "traceroute" -> {
                        val host = call.argument<String>("host")?.trim()
                        if (!isValidProbeHost(host)) result.error("INVALID_ARGS", "Traceroute 主机无效", null)
                        else traceroute(host!!, result)
                    }
                    "systemSettings" -> result.success(systemSettings())
                    "setBrightness" -> {
                        val value = (call.argument<Number>("value") ?: -1.0).toFloat()
                        if (value !in 0f..1f) result.error("INVALID_ARGS", "亮度参数无效", null)
                        else setBrightness(value, result)
                    }
                    "setVolume" -> {
                        val stream = call.argument<String>("stream")
                        val value = (call.argument<Number>("value") ?: -1.0).toFloat()
                        if (!isValidVolumeStream(stream) || value !in 0f..1f) {
                            result.error("INVALID_ARGS", "音量参数无效", null)
                        } else {
                            setVolume(stream!!, value, result)
                        }
                    }
                    "setAutoRotate" -> {
                        val enabled = call.argument<Boolean>("enabled")
                        if (enabled == null) result.error("INVALID_ARGS", "自动旋转参数无效", null)
                        else setAutoRotate(enabled, result)
                    }
                    "setRefreshRate" -> {
                        val refreshRate = (call.argument<Number>("value") ?: 0).toFloat()
                        setRefreshRate(refreshRate, result)
                    }
                    "openDefaultAppsSettings" -> openSettingsPage(
                        Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
                        result,
                    )
                    "openDoNotDisturbSettings" -> openSettingsPage(
                        Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS),
                        result,
                    )
                    "openNotificationSettings" -> {
                        val appPackage = call.argument<String>("packageName")
                        if (appPackage != null && !isValidPackageName(appPackage)) {
                            result.error("INVALID_ARGS", "packageName 无效", null)
                        } else {
                            val intent = if (appPackage.isNullOrBlank()) {
                                Intent(Settings.ACTION_SETTINGS)
                            } else {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            }
                            if (!appPackage.isNullOrBlank()) {
                                intent.putExtra(Settings.EXTRA_APP_PACKAGE, appPackage)
                            }
                            openSettingsPage(intent, result)
                        }
                    }
                    "portProbe" -> {
                        val host = call.argument<String>("host")?.trim()
                        val port = (call.argument<Number>("port") ?: 0).toInt()
                        if (!isValidProbeHost(host) || port !in 1..65535) result.error("INVALID_ARGS", "端口参数无效", null)
                        else portProbe(host!!, port, result)
                    }
                    "appPermissions" -> {
                        val appPackage = call.argument<String>("packageName")
                        if (!isValidPackageName(appPackage)) result.error("INVALID_ARGS", "packageName 无效", null)
                        else appPermissions(appPackage!!, result)
                    }
                    "setAppAlias" -> {
                        val alias = call.argument<String>("alias")?.trim()
                        val appPackage = call.argument<String>("packageName")?.trim()
                        if (alias.isNullOrBlank() || alias.length > 40 || !isValidPackageName(appPackage)) {
                            result.error("INVALID_ARGS", "别名参数无效", null)
                        } else {
                            val aliases = deviceFilesPrefs.getStringSet("app_aliases", emptySet())
                                .orEmpty().toMutableSet()
                            aliases.removeAll { it.substringBefore('\u0000') == alias }
                            aliases.add("$alias\u0000$appPackage")
                            deviceFilesPrefs.edit().putStringSet("app_aliases", aliases).apply()
                            result.success(mapOf("alias" to alias, "packageName" to appPackage))
                        }
                    }
                    "listAppAliases" -> {
                        result.success(
                            deviceFilesPrefs.getStringSet("app_aliases", emptySet()).orEmpty()
                                .mapNotNull {
                                    val parts = it.split('\u0000', limit = 2)
                                    if (parts.size == 2) mapOf("alias" to parts[0], "packageName" to parts[1]) else null
                                }
                        )
                    }
                    "launchDeepLink" -> {
                        val appPackage = call.argument<String>("packageName")?.trim()
                        val rawUri = call.argument<String>("uri")?.trim()
                        if (!isValidPackageName(appPackage) || rawUri.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "深链参数无效", null)
                        } else {
                            launchDeepLink(appPackage!!, rawUri, result)
                        }
                    }
                    "inspectAppPrivateData" -> {
                        val operation = call.argument<String>("operation")
                        val appPackage = call.argument<String>("packageName")?.trim()
                        val relativePath = call.argument<String>("relativePath").orEmpty()
                        if (!isValidPackageName(appPackage) ||
                            (operation != "list" && operation != "read") ||
                            !isAllowedPrivateAppPath(relativePath) ||
                            (operation == "read" &&
                                (!isAllowedPrivateTextFile(relativePath) ||
                                    relativePath.isBlank()))
                        ) {
                            result.error("INVALID_ARGS", "应用私有目录只读参数无效", null)
                        } else {
                            inspectAppPrivateData(
                                operation!!,
                                appPackage!!,
                                relativePath,
                                result
                            )
                        }
                    }
                    "networkProbe" -> {
                        val host = call.argument<String>("host")?.trim()
                        if (!isValidProbeHost(host)) {
                            result.error("INVALID_ARGS", "网络探测主机无效", null)
                        } else {
                            networkProbe(host!!, result)
                        }
                    }
                    "searchFilesFiltered" -> {
                        val query = call.argument<String>("query")?.trim().orEmpty()
                        val extension = call.argument<String>("extension")?.trim()?.lowercase()
                        val after = call.argument<Number>("modifiedAfterMs")?.toLong()
                        val before = call.argument<Number>("modifiedBeforeMs")?.toLong()
                        if (query.isBlank()) {
                            result.error("INVALID_ARGS", "query 不能为空", null)
                        } else {
                            searchFilesFiltered(query, extension, after, before, result)
                        }
                    }
                    "refreshSearchIndex" -> refreshSearchIndex(result)
                    "fileOperationBatch" -> {
                        val operation = call.argument<String>("operation")
                        val rawUris = call.argument<List<*>>("uris")
                        val uris = rawUris?.filterIsInstance<String>().orEmpty()
                        val destinationUri = call.argument<String>("destinationUri")
                        if (operation !in setOf("delete", "copy", "move") ||
                            rawUris == null ||
                            rawUris.size != uris.size ||
                            uris.isEmpty() ||
                            uris.size > MAX_SAF_BATCH_OPERATIONS ||
                            uris.distinct().size != uris.size ||
                            (operation == "delete" && destinationUri != null) ||
                            (operation != "delete" &&
                                destinationUri?.startsWith("content://") != true)
                        ) {
                            result.error("INVALID_ARGS", "批量 SAF 文件操作参数无效", null)
                        } else {
                            fileOperationBatch(
                                operation!!,
                                uris,
                                destinationUri,
                                result,
                            )
                        }
                    }
                    "fileOperation" -> {
                        val operation = call.argument<String>("operation")
                        val rawUri = call.argument<String>("uri")
                        val destinationUri = call.argument<String>("destinationUri")
                        val newName = call.argument<String>("newName")
                        if (operation !in setOf("rename", "delete", "copy", "move") ||
                            rawUri.isNullOrBlank() ||
                            (operation == "rename" && !isValidDocumentName(newName)) ||
                            (operation == "delete" &&
                                (destinationUri != null || newName != null)) ||
                            ((operation == "copy" || operation == "move") &&
                                (destinationUri.isNullOrBlank() || newName != null))
                        ) {
                            result.error("INVALID_ARGS", "SAF 文件操作参数无效", null)
                        } else {
                            fileOperation(
                                operation!!,
                                rawUri,
                                destinationUri,
                                newName,
                                result,
                            )
                        }
                    }
                    "shareFile" -> {
                        val rawUri = call.argument<String>("uri")
                        if (rawUri.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "uri 不能为空", null)
                        } else {
                            shareAuthorizedFile(rawUri, result)
                        }
                    }
                    "launchAppByName" -> {
                        val query = call.argument<String>("query")?.trim().orEmpty()
                        if (query.isBlank()) {
                            result.error("INVALID_ARGS", "应用名称不能为空", null)
                        } else {
                            launchAppByName(query, result)
                        }
                    }
                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "packageName 不能为空", null)
                        } else {
                            launchInstalledApp(packageName, result)
                        }
                    }
                    "chooseFolder" -> {
                        if (pendingDirectoryPicker != null) {
                            result.error("BUSY", "文件夹选择器已打开", null)
                        } else {
                            pendingDirectoryPicker = result
                            try {
                                startActivityForResult(
                                    Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                                    ),
                                    9102
                                )
                            } catch (e: Exception) {
                                pendingDirectoryPicker = null
                                result.error("UNAVAILABLE", e.message, null)
                            }
                        }
                    }
                    "searchFiles" -> {
                        val query = call.argument<String>("query")?.trim().orEmpty()
                        val requestId = call.argument<String>("requestId").orEmpty()
                        if (query.isEmpty()) {
                            result.error("INVALID_ARGS", "query 不能为空", null)
                        } else if (requestId.isEmpty()) {
                            result.error("INVALID_ARGS", "requestId 不能为空", null)
                        } else if (pendingSearches.containsKey(requestId)) {
                            result.error("DUPLICATE_REQUEST", "搜索请求已存在", null)
                        } else {
                            pendingSearches[requestId] = result
                            deviceSearchExecutor.execute {
                                val searchResult = runCatching {
                                    searchAuthorizedFiles(query, requestId)
                                }
                                mainHandler.post {
                                    val pending = pendingSearches.remove(requestId)
                                    if (pending != null) {
                                        searchResult.fold(
                                            onSuccess = pending::success,
                                            onFailure = {
                                                pending.error(
                                                    "SEARCH_FAILED",
                                                    it.message ?: "文件搜索失败",
                                                    null
                                                )
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    "cancelSearch" -> {
                        val requestId = call.argument<String>("requestId").orEmpty()
                        synchronized(cancelledSearches) {
                            cancelledSearches.add(requestId)
                        }
                        pendingSearches.remove(requestId)
                        result.success(true)
                    }
                    "listAuthorizedFolders" -> {
                        result.success(listAuthorizedFolders())
                    }
                    "removeAuthorizedFolder" -> {
                        val rawUri = call.argument<String>("uri")
                        if (rawUri.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "uri 不能为空", null)
                        } else {
                            removeAuthorizedFolder(rawUri, result)
                        }
                    }
                    "openFile" -> {
                        val rawUri = call.argument<String>("uri")
                        if (rawUri.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "uri 不能为空", null)
                        } else {
                            openAuthorizedFile(rawUri, result)
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
                    "startDetached" -> {
                        val command = call.argument<String>("command")
                        val workingDirectory = call.argument<String>("workingDirectory")
                        val rootfsPath = call.argument<String>("rootfsPath")
                        val runtimeLibraryPath = call.argument<String>("runtimeLibraryPath")
                        val ownerToken = call.argument<String>("ownerToken")
                        val logPath = call.argument<String>("logPath")
                        val completionPath = call.argument<String>("completionPath")
                        if (command == null || workingDirectory == null || rootfsPath == null ||
                            runtimeLibraryPath == null || ownerToken == null || logPath == null ||
                            completionPath == null
                        ) {
                            result.error("INVALID_ARGS", "detached 参数不完整", null)
                            return@setMethodCallHandler
                        }
                        val timeoutMs = (call.argument<Number>("timeoutMs") ?: 86400000L).toLong()
                        result.success(
                            runner.startDetached(
                                command = command,
                                workingDirectory = workingDirectory,
                                rootfsPath = rootfsPath,
                                runtimeLibraryPath = runtimeLibraryPath,
                                timeoutMs = timeoutMs,
                                ownerToken = ownerToken,
                                logPath = logPath,
                                completionPath = completionPath,
                            ),
                        )
                    }
                    "verifyDetached" -> {
                        val pid = (call.argument<Number>("pid") ?: 0).toInt()
                        val ownerToken = call.argument<String>("ownerToken") ?: ""
                        result.success(runner.verifyDetached(pid, ownerToken))
                    }
                    "stopDetached" -> {
                        val pid = (call.argument<Number>("pid") ?: 0).toInt()
                        val ownerToken = call.argument<String>("ownerToken") ?: ""
                        result.success(runner.stopDetached(pid, ownerToken))
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
        pendingDirectoryPicker?.error("CANCELLED", "页面已关闭", null)
        pendingDirectoryPicker = null
        pendingSearches.values.forEach {
            it.error("CANCELLED", "页面已关闭", null)
        }
        pendingSearches.clear()
        synchronized(cancelledSearches) { cancelledSearches.clear() }
        deviceSearchExecutor.shutdownNow()
        builtinLinuxRunner?.stop()
        deviceBackupManager.shutdown()
        privilegedControl.shutdown()
        automationChannel = null
        super.onDestroy()
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (privilegedControl.onActivityResult(requestCode, resultCode)) return
        if (requestCode != 9102) return
        val pending = pendingDirectoryPicker ?: return
        pendingDirectoryPicker = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            pending.error("CANCELLED", "用户取消了文件夹授权", null)
            return
        }
        try {
            val flags = data.flags and (
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            if (flags and Intent.FLAG_GRANT_READ_URI_PERMISSION == 0) {
                throw SecurityException("系统未返回可持久化的读取授权")
            }
            contentResolver.takePersistableUriPermission(uri, flags)
            val roots = deviceFilesPrefs.getStringSet("authorized_roots", emptySet())
                .orEmpty().toMutableSet()
            roots.add(uri.toString())
            deviceFilesPrefs.edit().putStringSet("authorized_roots", roots).apply()
            pending.success(mapOf("authorized" to true))
        } catch (e: Exception) {
            pending.error(
                "PERMISSION_FAILED",
                e.message ?: "无法保留文件夹授权",
                null
            )
        }
    }

    private fun listLaunchableApps(): List<Map<String, String>> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(intent, 0)
            .mapNotNull { resolve ->
                val activity = resolve.activityInfo ?: return@mapNotNull null
                val appPackage = activity.packageName
                if (appPackage == packageName) return@mapNotNull null
                mapOf(
                    "packageName" to appPackage,
                    "label" to resolve.loadLabel(packageManager).toString()
                )
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["label"]?.lowercase() }
    }

    private fun deviceInfo(): Map<String, Any> = mapOf(
        "manufacturer" to Build.MANUFACTURER,
        "brand" to Build.BRAND,
        "model" to Build.MODEL,
        "androidVersion" to Build.VERSION.RELEASE,
        "sdk" to Build.VERSION.SDK_INT,
        "fingerprint" to Build.FINGERPRINT,
    )

    private fun systemStatus(): Map<String, Any> {
        val battery = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val activity = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo().also(activity::getMemoryInfo)
        val batteryPct = battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val selinux = runCatching {
            File("/sys/fs/selinux/enforce").readText().trim() == "1"
        }.getOrDefault(false)
        val kernel = System.getProperty("os.version").orEmpty()
        val cpu = runCatching {
            val line = File("/proc/stat").readLines().firstOrNull { it.startsWith("cpu ") }
            val values = line?.trim()?.split(Regex("\\s+"))?.drop(1)?.mapNotNull(String::toLongOrNull).orEmpty()
            val idle = values.getOrNull(3) ?: 0L
            val total = values.sum()
            mapOf("cores" to Runtime.getRuntime().availableProcessors(), "totalJiffies" to total, "idleJiffies" to idle)
        }.getOrDefault(mapOf("cores" to Runtime.getRuntime().availableProcessors()))
        val temperatures = runCatching {
            File("/sys/class/thermal").listFiles()
                .orEmpty()
                .filter { it.name.startsWith("thermal_zone") }
                .mapNotNull { zone ->
                    val raw = File(zone, "temp").takeIf(File::exists)?.readText()?.trim()?.toDoubleOrNull()
                    if (raw == null) null else mapOf("zone" to zone.name, "celsius" to (if (raw > 1000) raw / 1000 else raw))
                }
        }.getOrDefault(emptyList())
        val mounts = runCatching {
            File("/proc/mounts").readLines().take(200).map { it.split(' ').take(4) }
        }.getOrDefault(emptyList())
        return mapOf(
            "batteryPercent" to batteryPct,
            "memoryTotalBytes" to memory.totalMem,
            "memoryAvailableBytes" to memory.availMem,
            "memoryLow" to memory.lowMemory,
            "kernelVersion" to kernel,
            "selinuxEnforcing" to selinux,
            "cpu" to cpu,
            "temperatures" to temperatures,
            "mounts" to mounts,
        )
    }

    private fun trafficInfo(): Map<String, Any> {
        val uid = TrafficStats.getUidRxBytes(android.os.Process.myUid())
        val uod = TrafficStats.getUidTxBytes(android.os.Process.myUid())
        val totalRx = TrafficStats.getTotalRxBytes()
        val totalTx = TrafficStats.getTotalTxBytes()
        return mapOf(
            "appRxBytes" to if (uid < 0) 0L else uid,
            "appTxBytes" to if (uod < 0) 0L else uod,
            "totalRxBytes" to if (totalRx < 0) 0L else totalRx,
            "totalTxBytes" to if (totalTx < 0) 0L else totalTx,
        )
    }

    private fun systemSettings(): Map<String, Any> {
        val resolver = contentResolver
        val brightness = runCatching {
            Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS)
        }.getOrDefault(-1)
        val autoRotate = runCatching {
            Settings.System.getInt(resolver, Settings.System.ACCELEROMETER_ROTATION) == 1
        }.getOrDefault(false)
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val wifiEnabled = runCatching {
            (getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager)
                .isWifiEnabled
        }.getOrDefault(false)
        val bluetoothEnabled = runCatching {
            Settings.Global.getInt(resolver, Settings.Global.BLUETOOTH_ON, 0) == 1
        }.getOrDefault(false)
        val airplaneMode = runCatching {
            Settings.Global.getInt(resolver, Settings.Global.AIRPLANE_MODE_ON, 0) == 1
        }.getOrDefault(false)
        val locationEnabled = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                (getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager)
                    .isLocationEnabled
            } else {
                Settings.Secure.getInt(resolver, Settings.Secure.LOCATION_MODE, 0) !=
                    Settings.Secure.LOCATION_MODE_OFF
            }
        }.getOrDefault(false)
        val dnd = runCatching {
            (getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager)
                .currentInterruptionFilter != android.app.NotificationManager.INTERRUPTION_FILTER_ALL
        }.getOrDefault(false)
        val displayModes = runCatching {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.supportedModes
                .map { it.refreshRate.toDouble() }
                .distinct()
                .sorted()
        }.getOrDefault(emptyList())
        val animationScales = runCatching {
            mapOf(
                "window" to Settings.Global.getFloat(
                    resolver,
                    Settings.Global.WINDOW_ANIMATION_SCALE,
                    1f,
                ).toDouble(),
                "transition" to Settings.Global.getFloat(
                    resolver,
                    Settings.Global.TRANSITION_ANIMATION_SCALE,
                    1f,
                ).toDouble(),
                "animator" to Settings.Global.getFloat(
                    resolver,
                    Settings.Global.ANIMATOR_DURATION_SCALE,
                    1f,
                ).toDouble(),
            )
        }.getOrDefault(emptyMap())
        return mapOf(
            "brightness" to if (brightness < 0) -1.0 else brightness / 255.0,
            "autoRotate" to autoRotate,
            "musicVolume" to audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() /
                audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1),
            "ringVolume" to audio.getStreamVolume(AudioManager.STREAM_RING).toDouble() /
                audio.getStreamMaxVolume(AudioManager.STREAM_RING).coerceAtLeast(1),
            "wifiEnabled" to wifiEnabled,
            "bluetoothEnabled" to bluetoothEnabled,
            "airplaneModeEnabled" to airplaneMode,
            "locationEnabled" to locationEnabled,
            "doNotDisturbEnabled" to dnd,
            "fontScale" to runCatching {
                Settings.System.getFloat(resolver, Settings.System.FONT_SCALE, 1f).toDouble()
            }.getOrDefault(1.0),
            "refreshRates" to displayModes,
            "peakRefreshRate" to runCatching {
                Settings.System.getFloat(resolver, "peak_refresh_rate", 0f).toDouble()
            }.getOrDefault(0.0),
            "minRefreshRate" to runCatching {
                Settings.System.getFloat(resolver, "min_refresh_rate", 0f).toDouble()
            }.getOrDefault(0.0),
            "animationScales" to animationScales,
        )
    }

    private fun setBrightness(value: Float, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.System.canWrite(this)) {
            runPrivilegedAppCommand(
                "settings put system screen_brightness ${(value * 255).toInt()}",
                result,
            )
            return
        }
        try {
            Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, (value * 255).toInt())
            result.success(mapOf("value" to value))
        } catch (e: Exception) {
            result.error("SETTINGS_FAILED", e.message ?: "亮度调整失败", null)
        }
    }

    /** 固定模板的设置写入命令：经 Root/Shizuku 执行，否则引导授予“修改系统设置”。 */
    private fun runPrivilegedAppCommand(command: String, result: MethodChannel.Result) =
        privilegedControl.runSettingsCommand(command, result)

    private fun isValidVolumeStream(stream: String?): Boolean =
        stream in setOf("music", "ring", "alarm", "notification", "voice_call")

    private fun setVolume(stream: String, value: Float, result: MethodChannel.Result) {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val streamType = when (stream) {
            "ring" -> AudioManager.STREAM_RING
            "alarm" -> AudioManager.STREAM_ALARM
            "notification" -> AudioManager.STREAM_NOTIFICATION
            "voice_call" -> AudioManager.STREAM_VOICE_CALL
            else -> AudioManager.STREAM_MUSIC
        }
        val max = audio.getStreamMaxVolume(streamType).coerceAtLeast(1)
        audio.setStreamVolume(streamType, (value * max).toInt(), 0)
        result.success(mapOf("stream" to stream, "value" to value))
    }

    private fun setAutoRotate(enabled: Boolean, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.System.canWrite(this)) {
            runPrivilegedAppCommand(
                "settings put system accelerometer_rotation ${if (enabled) 1 else 0}",
                result,
            )
            return
        }
        try {
            Settings.System.putInt(
                contentResolver,
                Settings.System.ACCELEROMETER_ROTATION,
                if (enabled) 1 else 0,
            )
            result.success(mapOf("enabled" to enabled))
        } catch (e: Exception) {
            result.error("SETTINGS_FAILED", e.message ?: "自动旋转调整失败", null)
        }
    }

    private fun setRefreshRate(value: Float, result: MethodChannel.Result) {
        if (!value.isFinite() || value !in 30f..240f) {
            result.error("INVALID_ARGS", "刷新率必须在 30 到 240 Hz 范围内", null)
            return
        }
        @Suppress("DEPRECATION")
        val supported = windowManager.defaultDisplay.supportedModes
            .any { kotlin.math.abs(it.refreshRate - value) <= 0.2f }
        if (!supported) {
            result.error("UNSUPPORTED_VALUE", "此刷新率不受当前屏幕支持", null)
            return
        }
        val normalized = String.format(java.util.Locale.US, "%.2f", value)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.System.canWrite(this)) {
            runPrivilegedAppCommand(
                "settings put system peak_refresh_rate $normalized && " +
                    "settings put system min_refresh_rate $normalized",
                result,
            )
            return
        }
        try {
            val peak = Settings.System.putFloat(contentResolver, "peak_refresh_rate", value)
            val minimum = Settings.System.putFloat(contentResolver, "min_refresh_rate", value)
            if (!peak || !minimum) {
                result.error("SETTINGS_FAILED", "系统拒绝刷新率设置", null)
            } else {
                result.success(mapOf("refreshRate" to value, "supported" to true))
            }
        } catch (e: Exception) {
            result.error("SETTINGS_FAILED", e.message ?: "刷新率设置失败", null)
        }
    }

    private fun openSettingsPage(intent: Intent, result: MethodChannel.Result) {
        try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(mapOf("opened" to true, "userActionRequired" to true))
        } catch (e: ActivityNotFoundException) {
            result.error("UNAVAILABLE", "设备没有对应的系统设置页面", null)
        } catch (e: Exception) {
            result.error("SETTINGS_FAILED", e.message ?: "无法打开系统设置页面", null)
        }
    }

    private fun traceroute(host: String, result: MethodChannel.Result) {
        Thread {
            try {
                val process = ProcessBuilder("traceroute", "-m", "8", "-w", "1", host)
                    .redirectErrorStream(true)
                    .start()
                val output = process.inputStream.bufferedReader().readText().take(16000)
                val finished = process.waitFor(12, java.util.concurrent.TimeUnit.SECONDS)
                if (!finished) process.destroyForcibly()
                runOnUiThread {
                    result.success(
                        mapOf(
                            "host" to host,
                            "output" to output,
                            "completed" to finished,
                            "exitCode" to if (finished) process.exitValue() else -1,
                        )
                    )
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.success(
                        mapOf(
                            "host" to host,
                            "output" to "",
                            "completed" to false,
                            "error" to (e.message ?: "设备不支持 traceroute"),
                        )
                    )
                }
            }
        }.start()
    }

    private fun portProbe(host: String, port: Int, result: MethodChannel.Result) {
        val started = System.currentTimeMillis()
        try {
            java.net.Socket().use { socket ->
                socket.connect(java.net.InetSocketAddress(host, port), 3000)
            }
            result.success(mapOf("host" to host, "port" to port, "reachable" to true, "elapsedMs" to System.currentTimeMillis() - started))
        } catch (e: Exception) {
            result.success(mapOf("host" to host, "port" to port, "reachable" to false, "elapsedMs" to System.currentTimeMillis() - started, "error" to (e.message ?: "连接失败")))
        }
    }

    private fun appPermissions(appPackage: String, result: MethodChannel.Result) {
        try {
            val info = packageManager.getPackageInfo(appPackage, PackageManager.GET_PERMISSIONS)
            val requested = info.requestedPermissions.orEmpty()
            val flags = info.requestedPermissionsFlags ?: IntArray(requested.size)
            result.success(mapOf(
                "packageName" to appPackage,
                "permissions" to requested.mapIndexed { index, permission ->
                    mapOf("name" to permission, "granted" to (flags.getOrNull(index)?.and(android.content.pm.PackageInfo.REQUESTED_PERMISSION_GRANTED) != 0))
                },
            ))
        } catch (e: PackageManager.NameNotFoundException) {
            result.error("NOT_FOUND", "应用未安装或当前不可见", null)
        }
    }

    private fun launchDeepLink(
        appPackage: String,
        rawUri: String,
        result: MethodChannel.Result,
    ) {
        try {
            val uri = Uri.parse(rawUri)
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                `package` = appPackage
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(packageManager) == null) {
                result.error("NO_LAUNCH_INTENT", "应用没有可处理该深链的入口", null)
                return
            }
            startActivity(intent)
            result.success(mapOf("started" to true, "packageName" to appPackage, "uri" to rawUri))
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message ?: "深链启动失败", null)
        }
    }

    private fun storageInfo(): Map<String, Any> {
        val data = StatFs(filesDir.absolutePath)
        val bytes = data.blockSizeLong
        return mapOf(
            "totalBytes" to data.blockCountLong * bytes,
            "availableBytes" to data.availableBlocksLong * bytes,
            "freeBytes" to data.freeBlocksLong * bytes,
        )
    }

    private fun networkInfo(): Map<String, Any> {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = manager.activeNetwork
        val capabilities = network?.let(manager::getNetworkCapabilities)
        val linkProperties = network?.let(manager::getLinkProperties)
        val proxy = linkProperties?.httpProxy
        val transports = buildList {
            if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) add("wifi")
            if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true) add("cellular")
            if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true) add("ethernet")
            if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) == true) add("bluetooth")
            if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) add("vpn")
            if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_USB) == true) add("usb")
        }
        val networkInfo = mutableMapOf<String, Any>(
            "connected" to (network != null && capabilities != null),
            "validated" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            "metered" to manager.isActiveNetworkMetered,
            "transports" to transports,
            "vpn" to (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true),
            "dnsServers" to linkProperties?.dnsServers.orEmpty().mapNotNull { it.hostAddress },
            "domains" to (linkProperties?.domains ?: ""),
        )
        if (proxy != null) {
            networkInfo["httpProxy"] = mapOf(
                "host" to proxy.host,
                "port" to proxy.port,
                "exclusionList" to proxy.exclusionList.toList(),
                "pacFileUrl" to proxy.pacFileUrl.toString(),
            )
        }
        return networkInfo
    }

    /**
     * Clears only the app's cache and code_cache directories. `pm clear` also
     * deletes credentials, preferences, and databases, so it is not a cache
     * operation and must never be used here.
     */
    private fun appInfo(appPackage: String, result: MethodChannel.Result) {
        try {
            val info = packageManager.getApplicationInfo(appPackage, 0)
            val packageInfo = packageManager.getPackageInfo(appPackage, 0)
            result.success(
                mapOf(
                    "packageName" to appPackage,
                    "label" to packageManager.getApplicationLabel(info).toString(),
                    "versionName" to (packageInfo.versionName ?: ""),
                    "versionCode" to (if (Build.VERSION.SDK_INT >= 28) {
                        packageInfo.longVersionCode
                    } else {
                        @Suppress("DEPRECATION") packageInfo.versionCode.toLong()
                    }),
                    "enabled" to info.enabled,
                    "systemApp" to ((info.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0),
                )
            )
        } catch (e: PackageManager.NameNotFoundException) {
            result.error("NOT_FOUND", "应用未安装或当前不可见", null)
        }
    }

    private fun isValidPackageName(value: String?): Boolean =
        value != null && Regex("^[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+$").matches(value)



    private fun isAllowedPrivateAppPath(path: String): Boolean {
        if (path.isEmpty()) return true
        if (path.length > MAX_APP_PRIVATE_RELATIVE_PATH_LENGTH ||
            path.contains('\u0000') ||
            path.any { it.code < 0x20 || it.code == 0x7f } ||
            path.contains('\\') ||
            path.startsWith('/') ||
            path.endsWith('/')
        ) {
            return false
        }
        return path.split('/').all { segment ->
            segment.isNotEmpty() && segment != "." && segment != ".."
        }
    }

    private fun isAllowedPrivateTextFile(path: String): Boolean =
        path.substringAfterLast('.', "").lowercase() in APP_PRIVATE_TEXT_EXTENSIONS

    /**
     * Reads only within the selected app's user-0 data directory. Paths are
     * canonicalized on-device and symlinks resolving outside that directory are
     * rejected before either listing or reading.
     */
    private fun inspectAppPrivateData(
        operation: String,
        appPackage: String,
        relativePath: String,
        result: MethodChannel.Result
    ) {
        appPrivateDataExecutor.execute {
            try {
                val dollar = '$'
                val appRoot = "/data/user/0/$appPackage"
                val escapedRoot = appRoot.replace("'", "'\\''")
                val escapedRelativePath = relativePath.replace("'", "'\\''")
                val targetExpression = if (relativePath.isEmpty()) {
                    "\"${dollar}app_root\""
                } else {
                    "\"${dollar}app_root\"/'$escapedRelativePath'"
                }
                val action = when (operation) {
                    "list" -> """
                        [ "${dollar}target" ] && [ -d "${dollar}target" ] || exit 26
                        ls -lan -- "${dollar}target" | head -n 101
                    """.trimIndent()
                    "read" -> """
                        [ -f "${dollar}target" ] || exit 27
                        head -c ${MAX_APP_PRIVATE_FILE_BYTES + 1} "${dollar}target"
                    """.trimIndent()
                    else -> {
                        mainHandler.post {
                            result.error("INVALID_ARGS", "不支持的应用私有目录操作", null)
                        }
                        return@execute
                    }
                }
                val command = """
                    data_root=${dollar}(readlink -f -- '/data/user/0') || exit 20
                    app_root=${dollar}(readlink -f -- '$escapedRoot') || exit 21
                    expected_app_root="${dollar}data_root/$appPackage"
                    [ "${dollar}app_root" = "${dollar}expected_app_root" ] || exit 22
                    [ -d "${dollar}app_root" ] || exit 23
                    target=${dollar}(readlink -f -- $targetExpression) || exit 24
                    case "${dollar}target" in "${dollar}app_root" | "${dollar}app_root"/*) ;; *) exit 25 ;; esac
                    $action
                """.trimIndent()
                val process = ProcessBuilder("su", "-c", command)
                    .redirectErrorStream(true)
                    .start()
                val maxOutput = if (operation == "read") {
                    MAX_APP_PRIVATE_FILE_BYTES
                } else {
                    MAX_APP_PRIVATE_LIST_BYTES
                }
                val outputTask = java.util.concurrent.FutureTask {
                    process.inputStream.use { it.readNBytes(maxOutput + 1) }
                }
                Thread(outputTask, "app-private-data-output").apply {
                    isDaemon = true
                    start()
                }
                val finished = process.waitFor(30, java.util.concurrent.TimeUnit.SECONDS)
                if (!finished) {
                    process.destroyForcibly()
                    outputTask.cancel(true)
                    mainHandler.post {
                        result.error("TIMEOUT", "读取应用私有目录超时", null)
                    }
                    return@execute
                }
                val output = outputTask.get(2, java.util.concurrent.TimeUnit.SECONDS)
                if (process.exitValue() != 0) {
                    val message = when (process.exitValue()) {
                        22, 25 -> "目标路径解析到应用私有目录之外，已拒绝"
                        23, 26, 27 -> "应用、目录或文件不存在，或当前 Root 无权读取"
                        else -> "Root 无法访问该应用私有目录（状态 ${process.exitValue()}）"
                    }
                    mainHandler.post {
                        result.error("APP_PRIVATE_DATA_FAILED", message, null)
                    }
                    return@execute
                }
                val truncated = output.size > maxOutput ||
                    (operation == "list" && output.count { it == 10.toByte() } >= 101)
                val boundedOutput =
                    if (output.size > maxOutput) output.copyOf(maxOutput) else output
                val response = if (operation == "list") {
                    mapOf(
                        "packageName" to appPackage,
                        "path" to appRoot + if (relativePath.isEmpty()) "" else "/$relativePath",
                        "text" to boundedOutput.toString(Charsets.UTF_8),
                        "truncated" to truncated
                    )
                } else {
                    val content = decodePrivateAppText(boundedOutput, truncated)
                    mapOf(
                        "packageName" to appPackage,
                        "path" to "$appRoot/$relativePath",
                        "content" to content,
                        "bytes" to boundedOutput.size,
                        "truncated" to truncated
                    )
                }
                mainHandler.post { result.success(response) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error(
                        "ROOT_REQUIRED",
                        e.message ?: "无法通过 Root 读取应用私有目录",
                        null
                    )
                }
            }
        }
    }

    private fun decodePrivateAppText(bytes: ByteArray, truncated: Boolean): String {
        val minimumLength = if (truncated) (bytes.size - 3).coerceAtLeast(0) else bytes.size
        for (length in bytes.size downTo minimumLength) {
            val decoder = Charsets.UTF_8.newDecoder()
                .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
            try {
                return decoder.decode(java.nio.ByteBuffer.wrap(bytes, 0, length)).toString()
            } catch (_: java.nio.charset.CharacterCodingException) {
                if (!truncated) break
            }
        }
        throw IllegalArgumentException("该文件不是受支持的 UTF-8 文本文件")
    }


    private fun isValidProbeHost(host: String?): Boolean {
        if (host.isNullOrBlank() || host.length > 253 ||
            host.any { it.isWhitespace() || it in "'\"`;|&<>$()" }
        ) {
            return false
        }
        return Regex("^[A-Za-z0-9][A-Za-z0-9.:-]*$").matches(host)
    }


    private fun networkProbe(host: String, result: MethodChannel.Result) {
        val startedAt = System.currentTimeMillis()
        try {
            val resolved = java.net.InetAddress.getByName(host)
            val reachable = resolved.isReachable(3000)
            result.success(
                mapOf(
                    "host" to host,
                    "address" to resolved.hostAddress.orEmpty(),
                    "resolved" to true,
                    "reachable" to reachable,
                    "elapsedMs" to (System.currentTimeMillis() - startedAt),
                )
            )
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "host" to host,
                    "resolved" to false,
                    "reachable" to false,
                    "elapsedMs" to (System.currentTimeMillis() - startedAt),
                    "error" to (e.message ?: "网络探测失败"),
                )
            )
        }
    }

    private fun searchFilesFiltered(
        query: String,
        extension: String?,
        modifiedAfterMs: Long?,
        modifiedBeforeMs: Long?,
        result: MethodChannel.Result,
    ) {
        deviceSearchExecutor.execute {
            try {
                val roots = deviceFilesPrefs.getStringSet("authorized_roots", emptySet())
                    .orEmpty().sorted()
                if (roots.isEmpty()) {
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "needsFolderPermission" to true,
                                "files" to emptyList<Map<String, String>>(),
                                "indexUsed" to false,
                            )
                        )
                    }
                    return@execute
                }

                val refreshed = ensureSearchIndexFresh(roots)
                val search = safSearchIndex.search(
                    roots,
                    query,
                    extension,
                    modifiedAfterMs,
                    modifiedBeforeMs,
                )
                mainHandler.post {
                    result.success(
                        mapOf(
                            "needsFolderPermission" to false,
                            "files" to search.files,
                            "truncated" to search.truncated,
                            "indexUsed" to true,
                            "indexRefreshedRoots" to refreshed.indexedRoots,
                            "indexedDocuments" to refreshed.indexedDocuments,
                            "indexComplete" to refreshed.complete,
                            "indexUpdatedAtMs" to search.indexedAtMs,
                            "incompleteRoots" to search.incompleteRoots,
                        )
                    )
                }
            } catch (e: SecurityException) {
                mainHandler.post {
                    result.error("PERMISSION_DENIED", e.message ?: "文件夹读取权限已失效", null)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("SEARCH_FAILED", e.message ?: "文件索引搜索失败", null)
                }
            }
        }
    }

    private data class SearchIndexRefreshSummary(
        val indexedRoots: Int,
        val indexedDocuments: Int,
        val complete: Boolean,
    )

    private data class SearchIndexBuild(
        val documents: List<SafIndexedDocument>,
        val visitedDocuments: Int,
        val complete: Boolean,
        val cancelled: Boolean,
    )

    private fun refreshSearchIndex(result: MethodChannel.Result) {
        deviceSearchExecutor.execute {
            try {
                val roots = deviceFilesPrefs.getStringSet("authorized_roots", emptySet())
                    .orEmpty().sorted()
                if (roots.isEmpty()) {
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "needsFolderPermission" to true,
                                "indexedRoots" to 0,
                                "indexedDocuments" to 0,
                                "complete" to true,
                            )
                        )
                    }
                    return@execute
                }
                val summary = ensureSearchIndexFresh(roots, force = true)
                mainHandler.post {
                    result.success(
                        mapOf(
                            "needsFolderPermission" to false,
                            "indexedRoots" to summary.indexedRoots,
                            "indexedDocuments" to summary.indexedDocuments,
                            "complete" to summary.complete,
                        )
                    )
                }
            } catch (e: SecurityException) {
                mainHandler.post {
                    result.error("PERMISSION_DENIED", e.message ?: "文件夹读取权限已失效", null)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("INDEX_FAILED", e.message ?: "文件索引更新失败", null)
                }
            }
        }
    }

    private fun ensureSearchIndexFresh(
        rootUris: List<String>,
        force: Boolean = false,
        requestId: String? = null,
    ): SearchIndexRefreshSummary {
        val now = System.currentTimeMillis()
        var indexedRoots = 0
        var indexedDocuments = 0
        var allComplete = true
        for (rawRoot in rootUris) {
            if (requestId != null && isSearchCancelled(requestId)) {
                allComplete = false
                break
            }
            val existing = safSearchIndex.state(rawRoot)
            val fresh = existing != null &&
                now - existing.indexedAtMs < SEARCH_INDEX_MAX_AGE_MS
            if (!force && fresh) {
                allComplete = allComplete && existing!!.complete
                continue
            }
            val build = buildSearchIndex(rawRoot, requestId)
            if (build.cancelled) {
                allComplete = false
                break
            }
            safSearchIndex.replaceRoot(
                rawRoot,
                build.documents,
                System.currentTimeMillis(),
                build.complete,
            )
            indexedRoots++
            indexedDocuments += build.documents.size
            allComplete = allComplete && build.complete
        }
        return SearchIndexRefreshSummary(indexedRoots, indexedDocuments, allComplete)
    }

    private fun buildSearchIndex(rawRoot: String, requestId: String?): SearchIndexBuild {
        val tree = Uri.parse(rawRoot)
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val rootDocument = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
        val documents = mutableListOf<SafIndexedDocument>()
        var visited = 0
        var truncated = false
        var cancelled = false

        fun walk(document: Uri, depth: Int) {
            if (truncated || cancelled) return
            if (requestId != null && isSearchCancelled(requestId)) {
                cancelled = true
                return
            }
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree,
                DocumentsContract.getDocumentId(document),
            )
            contentResolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                    DocumentsContract.Document.COLUMN_SIZE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                )
                val nameColumn = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                )
                val mimeColumn = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                )
                val modifiedColumn = cursor.getColumnIndex(
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                )
                val sizeColumn = cursor.getColumnIndex(
                    DocumentsContract.Document.COLUMN_SIZE,
                )
                while (cursor.moveToNext() && !truncated && !cancelled) {
                    if (requestId != null && isSearchCancelled(requestId)) {
                        cancelled = true
                        break
                    }
                    if (visited >= MAX_SEARCH_DOCUMENTS) {
                        truncated = true
                        break
                    }
                    visited++
                    val documentId = cursor.getString(idColumn)
                    val name = cursor.getString(nameColumn) ?: continue
                    val mimeType = cursor.getString(mimeColumn).orEmpty()
                    val child = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
                    if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (depth + 1 >= MAX_SEARCH_DEPTH) {
                            truncated = true
                        } else {
                            walk(child, depth + 1)
                        }
                    } else {
                        documents.add(
                            SafIndexedDocument(
                                uri = child.toString(),
                                name = name,
                                mimeType = mimeType,
                                modifiedAtMs = if (
                                    modifiedColumn >= 0 && !cursor.isNull(modifiedColumn)
                                ) cursor.getLong(modifiedColumn) else 0L,
                                sizeBytes = if (
                                    sizeColumn >= 0 && !cursor.isNull(sizeColumn)
                                ) cursor.getLong(sizeColumn) else 0L,
                            )
                        )
                    }
                }
            }
        }

        walk(rootDocument, 0)
        return SearchIndexBuild(
            documents = documents,
            visitedDocuments = visited,
            complete = !truncated && !cancelled,
            cancelled = cancelled,
        )
    }

    private fun walkDocumentsFiltered(
        tree: Uri,
        document: Uri,
        needle: String,
        extension: String?,
        modifiedAfterMs: Long?,
        modifiedBeforeMs: Long?,
        matches: MutableList<Map<String, String>>,
        depth: Int,
        budget: SearchBudget,
    ) {
        if (budget.exhausted) return
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getDocumentId(document)
        )
        contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null, null, null
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val modifiedColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext() && !budget.exhausted) {
                val id = cursor.getString(idColumn)
                val name = cursor.getString(nameColumn) ?: continue
                val mime = cursor.getString(mimeColumn)
                budget.visit(depth, matches.size)
                val child = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    walkDocumentsFiltered(tree, child, needle, extension, modifiedAfterMs, modifiedBeforeMs, matches, depth + 1, budget)
                } else {
                    val modified = if (modifiedColumn >= 0 && !cursor.isNull(modifiedColumn)) cursor.getLong(modifiedColumn) else null
                    val extensionMatches = extension == null ||
                        name.lowercase().endsWith(if (extension.startsWith(".")) extension else ".$extension")
                    val timeMatches = (modifiedAfterMs == null || (modified ?: Long.MIN_VALUE) >= modifiedAfterMs) &&
                        (modifiedBeforeMs == null || (modified ?: Long.MAX_VALUE) <= modifiedBeforeMs)
                    if (name.lowercase().contains(needle) && extensionMatches && timeMatches) {
                        matches.add(mapOf("name" to name, "uri" to child.toString(), "modifiedAtMs" to (modified ?: 0L).toString()))
                    }
                }
            }
        }
    }

    private fun shareAuthorizedFile(rawUri: String, result: MethodChannel.Result) {
        val uri = Uri.parse(rawUri)
        val authorizedTrees = deviceFilesPrefs.getStringSet("authorized_roots", emptySet())
            .orEmpty().map(Uri::parse)
        val allowed = uri.scheme == "content" && authorizedTrees.any { tree ->
            runCatching {
                DocumentsContract.isTreeUri(tree) &&
                    uri.authority == tree.authority &&
                    DocumentsContract.getDocumentId(uri).startsWith(
                        DocumentsContract.getTreeDocumentId(tree) + "/"
                    )
            }.getOrDefault(false)
        }
        if (!allowed) {
            result.error("PERMISSION_DENIED", "文件不属于已授权目录", null)
            return
        }
        try {
            val mime = contentResolver.getType(uri) ?: "*/*"
            startActivity(Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                clipData = ClipData.newRawUri("NEXUS file", uri)
            })
            result.success(mapOf("started" to true))
        } catch (e: Exception) {
            result.error("SHARE_FAILED", e.message ?: "分享文件失败", null)
        }
    }

    private data class AuthorizedSafDocument(
        val treeUri: Uri,
        val documentUri: Uri,
        val documentId: String,
        val treeDocumentId: String,
    )

    private fun isValidDocumentName(value: String?): Boolean =
        !value.isNullOrBlank() &&
            value.length <= 255 &&
            value != "." &&
            value != ".." &&
            value.none { it == '/' || it == '\\' || it.code < 0x20 || it.code == 0x7f }

    private fun authorizedSafDocument(rawUri: String): AuthorizedSafDocument? {
        val candidate = runCatching { Uri.parse(rawUri) }.getOrNull() ?: return null
        if (candidate.scheme != "content") return null
        val roots = deviceFilesPrefs.getStringSet("authorized_roots", emptySet())
            .orEmpty()
        for (rawTree in roots) {
            val tree = runCatching { Uri.parse(rawTree) }.getOrNull() ?: continue
            val treeId = runCatching { DocumentsContract.getTreeDocumentId(tree) }
                .getOrNull() ?: continue
            if (candidate == tree &&
                runCatching { DocumentsContract.isTreeUri(candidate) }.getOrDefault(false)
            ) {
                val rootDocument = DocumentsContract.buildDocumentUriUsingTree(tree, treeId)
                return AuthorizedSafDocument(tree, rootDocument, treeId, treeId)
            }
            val documentId = runCatching { DocumentsContract.getDocumentId(candidate) }
                .getOrNull() ?: continue
            if (candidate.authority == tree.authority &&
                (documentId == treeId || documentId.startsWith("$treeId/"))
            ) {
                val documentUri =
                    DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
                return AuthorizedSafDocument(tree, documentUri, documentId, treeId)
            }
        }
        return null
    }

    private fun hasPersistedWriteGrant(treeUri: Uri): Boolean =
        contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission && it.isWritePermission
        }

    private fun documentParentUri(document: AuthorizedSafDocument): Uri? {
        if (document.documentId == document.treeDocumentId) return null
        val parentId = document.documentId.substringBeforeLast(
            '/',
            document.treeDocumentId,
        )
        if (parentId != document.treeDocumentId &&
            !parentId.startsWith("${document.treeDocumentId}/")
        ) {
            return null
        }
        return DocumentsContract.buildDocumentUriUsingTree(document.treeUri, parentId)
    }

    private fun fileOperation(
        operation: String,
        rawUri: String,
        rawDestinationUri: String?,
        newName: String?,
        result: MethodChannel.Result,
    ) {
        deviceSearchExecutor.execute {
            try {
                val source = authorizedSafDocument(rawUri)
                    ?: throw SecurityException("源文件不属于用户已授权的 SAF 目录")
                if (source.documentId == source.treeDocumentId) {
                    throw IllegalArgumentException("不能直接删除、重命名或复制授权目录本身")
                }
                if (!hasPersistedWriteGrant(source.treeUri)) {
                    throw SecurityException("该文件夹没有持久写入授权，请重新选择并授权文件夹")
                }
                val changedUri = when (operation) {
                    "rename" -> {
                        if (!isValidDocumentName(newName)) {
                            throw IllegalArgumentException("新文件名无效")
                        }
                        DocumentsContract.renameDocument(
                            contentResolver,
                            source.documentUri,
                            newName!!,
                        ) ?: throw IOException("DocumentsProvider 未能重命名该文件")
                    }
                    "delete" -> {
                        if (!DocumentsContract.deleteDocument(
                                contentResolver,
                                source.documentUri,
                            )
                        ) {
                            throw IOException("DocumentsProvider 未能删除该文件")
                        }
                        null
                    }
                    "copy", "move" -> {
                        val destination = authorizedSafDocument(rawDestinationUri.orEmpty())
                            ?: throw SecurityException("目标目录不属于用户已授权的 SAF 目录")
                        if (destination.treeUri != source.treeUri) {
                            throw IllegalArgumentException(
                                "复制和移动仅支持同一个已授权 DocumentsProvider 目录",
                            )
                        }
                        if (contentResolver.getType(destination.documentUri) !=
                            DocumentsContract.Document.MIME_TYPE_DIR
                        ) {
                            throw IllegalArgumentException("目标 URI 必须指向目录")
                        }
                        val writeGranted =
                            hasPersistedWriteGrant(destination.treeUri)
                        if (!writeGranted) {
                            throw SecurityException("目标目录没有持久写入授权")
                        }
                        if (operation == "copy") {
                            DocumentsContract.copyDocument(
                                contentResolver,
                                source.documentUri,
                                destination.documentUri,
                            ) ?: throw IOException("DocumentsProvider 不支持复制该文件")
                        } else {
                            val sourceParent = documentParentUri(source)
                                ?: throw IllegalArgumentException("无法确定源文件父目录")
                            DocumentsContract.moveDocument(
                                contentResolver,
                                source.documentUri,
                                sourceParent,
                                destination.documentUri,
                            ) ?: throw IOException("DocumentsProvider 不支持移动该文件")
                        }
                    }
                    else -> throw IllegalArgumentException("不支持的 SAF 文件操作")
                }
                safSearchIndex.removeRoot(source.treeUri.toString())
                mainHandler.post {
                    result.success(
                        mapOf(
                            "applied" to true,
                            "operation" to operation,
                            "sourceUri" to rawUri,
                            "resultUri" to (changedUri?.toString() ?: ""),
                        )
                    )
                }
            } catch (e: SecurityException) {
                mainHandler.post {
                    result.error("PERMISSION_DENIED", e.message ?: "SAF 写入授权不足", null)
                }
            } catch (e: UnsupportedOperationException) {
                mainHandler.post {
                    result.error(
                        "UNSUPPORTED_OPERATION",
                        "该存储提供方不支持此文件操作",
                        null,
                    )
                }
            } catch (e: IllegalArgumentException) {
                mainHandler.post {
                    result.error("INVALID_ARGS", e.message ?: "SAF 文件操作参数无效", null)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("FILE_OPERATION_FAILED", e.message ?: "SAF 文件操作失败", null)
                }
            }
        }
    }

    private fun fileOperationBatch(
        operation: String,
        rawUris: List<String>,
        rawDestinationUri: String?,
        result: MethodChannel.Result,
    ) {
        deviceSearchExecutor.execute {
            try {
                val sources = rawUris.map { rawUri ->
                    val source = authorizedSafDocument(rawUri)
                        ?: throw SecurityException("源文件不属于用户已授权的 SAF 目录")
                    if (source.documentId == source.treeDocumentId) {
                        throw IllegalArgumentException("不能把授权目录本身作为批量操作目标")
                    }
                    if (contentResolver.getType(source.documentUri) ==
                        DocumentsContract.Document.MIME_TYPE_DIR
                    ) {
                        throw IllegalArgumentException("批量操作只接受文件，不接受目录")
                    }
                    if (!hasPersistedWriteGrant(source.treeUri)) {
                        throw SecurityException("源目录没有持久写入授权，请重新授权")
                    }
                    source
                }

                val destination = if (operation == "delete") {
                    null
                } else {
                    val target = authorizedSafDocument(rawDestinationUri.orEmpty())
                        ?: throw SecurityException("目标目录不属于用户已授权的 SAF 目录")
                    if (!hasPersistedWriteGrant(target.treeUri)) {
                        throw SecurityException("目标目录没有持久写入授权")
                    }
                    if (contentResolver.getType(target.documentUri) !=
                        DocumentsContract.Document.MIME_TYPE_DIR
                    ) {
                        throw IllegalArgumentException("目标 URI 必须指向目录")
                    }
                    if (sources.any { it.treeUri != target.treeUri }) {
                        throw IllegalArgumentException(
                            "批量复制和移动仅支持同一个已授权 DocumentsProvider 目录",
                        )
                    }
                    target
                }

                // Invalidate before attempting provider calls. A provider may
                // partially apply a batch before reporting its first failure.
                (sources.map { it.treeUri.toString() } +
                    listOfNotNull(destination?.treeUri?.toString()))
                    .distinct()
                    .forEach(safSearchIndex::removeRoot)

                val outcomes = mutableListOf<Map<String, Any>>()
                var appliedCount = 0
                for ((index, source) in sources.withIndex()) {
                    val rawUri = rawUris[index]
                    try {
                        val changedUri = when (operation) {
                            "delete" -> {
                                if (!DocumentsContract.deleteDocument(
                                        contentResolver,
                                        source.documentUri,
                                    )
                                ) {
                                    throw IOException("DocumentsProvider 未能删除该文件")
                                }
                                null
                            }
                            "copy" -> DocumentsContract.copyDocument(
                                contentResolver,
                                source.documentUri,
                                destination!!.documentUri,
                            ) ?: throw IOException("DocumentsProvider 不支持复制该文件")
                            "move" -> {
                                val sourceParent = documentParentUri(source)
                                    ?: throw IllegalArgumentException("无法确定源文件父目录")
                                DocumentsContract.moveDocument(
                                    contentResolver,
                                    source.documentUri,
                                    sourceParent,
                                    destination!!.documentUri,
                                ) ?: throw IOException("DocumentsProvider 不支持移动该文件")
                            }
                            else -> throw IllegalArgumentException("不支持的批量 SAF 文件操作")
                        }
                        appliedCount++
                        outcomes.add(
                            mapOf(
                                "sourceUri" to rawUri,
                                "status" to "applied",
                                "resultUri" to (changedUri?.toString() ?: ""),
                            ),
                        )
                    } catch (error: Exception) {
                        outcomes.add(
                            mapOf(
                                "sourceUri" to rawUri,
                                "status" to "failed",
                                "error" to (error.message ?: "文件操作失败").take(240),
                            ),
                        )
                    }
                }
                val failedCount = sources.size - appliedCount
                mainHandler.post {
                    result.success(
                        mapOf(
                            "operation" to operation,
                            "totalCount" to sources.size,
                            "appliedCount" to appliedCount,
                            "failedCount" to failedCount,
                            "partial" to (failedCount > 0 && appliedCount > 0),
                            "results" to outcomes,
                        ),
                    )
                }
            } catch (error: SecurityException) {
                mainHandler.post {
                    result.error(
                        "PERMISSION_DENIED",
                        error.message ?: "SAF 写入授权不足；本批次尚未执行",
                        null,
                    )
                }
            } catch (error: UnsupportedOperationException) {
                mainHandler.post {
                    result.error(
                        "UNSUPPORTED_OPERATION",
                        "该存储提供方不支持此文件操作；本批次尚未执行",
                        null,
                    )
                }
            } catch (error: IllegalArgumentException) {
                mainHandler.post {
                    result.error(
                        "INVALID_ARGS",
                        error.message ?: "SAF 文件操作参数无效；本批次尚未执行",
                        null,
                    )
                }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error(
                        "FILE_OPERATION_FAILED",
                        error.message ?: "SAF 批量文件操作失败；本批次尚未执行",
                        null,
                    )
                }
            }
        }
    }

    private fun launchInstalledApp(packageName: String, result: MethodChannel.Result) {
        val knownPackages = listLaunchableApps().mapTo(mutableSetOf()) {
            it.getValue("packageName")
        }
        if (packageName !in knownPackages) {
            result.error("NOT_FOUND", "没有找到可启动的应用", null)
            return
        }
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
                ?: run {
                    result.error("NOT_FOUND", "没有找到可启动的应用", null)
                    return
                }
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(mapOf("started" to true))
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message ?: "应用启动失败", null)
        }
    }

    private fun launchAppByName(query: String, result: MethodChannel.Result) {
        val aliasPackage = deviceFilesPrefs.getStringSet("app_aliases", emptySet())
            .orEmpty()
            .mapNotNull {
                val parts = it.split('\u0000', limit = 2)
                if (parts.size == 2 &&
                    normalizeAppName(parts[0]) == normalizeAppName(query)
                ) {
                    parts[1]
                } else {
                    null
                }
            }
            .singleOrNull()
        if (aliasPackage != null) {
            launchInstalledApp(aliasPackage, result)
            return
        }
        val candidates = listLaunchableApps()
        val ranked = candidates.mapNotNull { app ->
            val label = app["label"].orEmpty()
            val score = appNameMatchScore(query, label) ?: return@mapNotNull null
            app + ("score" to score.toString())
        }.sortedByDescending { it["score"]?.toIntOrNull() ?: 0 }

        if (ranked.isEmpty()) {
            result.error(
                "NOT_FOUND",
                "没有找到名称匹配“$query”的可启动应用；请检查应用是否已安装且对系统可见",
                null
            )
            return
        }

        val highestScore = ranked.first()["score"]?.toIntOrNull() ?: 0
        val best = ranked.filter { (it["score"]?.toIntOrNull() ?: 0) == highestScore }
        if (best.size != 1) {
            result.success(
                mapOf(
                    "status" to "ambiguous",
                    "candidates" to best.map {
                        mapOf("label" to it["label"], "packageName" to it["packageName"])
                    }
                )
            )
            return
        }

        val selected = best.single()
        val packageName = selected["packageName"] ?: run {
            result.error("NOT_FOUND", "匹配的应用没有有效包名", null)
            return
        }
        val knownPackages = candidates.mapTo(mutableSetOf()) {
            it.getValue("packageName")
        }
        if (packageName !in knownPackages) {
            result.error("NOT_FOUND", "匹配的应用已不可见或已卸载，请重新查询", null)
            return
        }
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent == null) {
                result.error(
                    "NO_LAUNCH_INTENT",
                    "已找到 ${selected["label"]}，但 Android 未提供可启动入口",
                    null
                )
                return
            }
            startActivity(launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(
                mapOf(
                    "status" to "started",
                    "label" to selected["label"],
                    "packageName" to packageName
                )
            )
        } catch (e: ActivityNotFoundException) {
            result.error("NOT_FOUND", "应用启动入口已失效，请重新查询", null)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message ?: "应用启动失败", null)
        }
    }

    private fun appNameMatchScore(query: String, label: String): Int? {
        val normalizedQuery = normalizeAppName(query)
        val normalizedLabel = normalizeAppName(label)
        if (normalizedQuery.isEmpty() || normalizedLabel.isEmpty()) return null
        return when {
            normalizedQuery == normalizedLabel -> 100
            normalizedLabel.startsWith(normalizedQuery) -> 80
            normalizedLabel.contains(normalizedQuery) -> 60
            normalizedQuery.contains(normalizedLabel) && normalizedLabel.length >= 2 -> 50
            else -> null
        }
    }

    private fun normalizeAppName(value: String): String =
        value.lowercase()
            .replace(Regex("^(请|帮我|麻烦|现在)?(打开|启动|进入|切换到|切到)"), "")
            .replace(Regex("[\\s\\p{Punct}，。！？、；：‘’“”《》【】（）]+"), "")
            .trim()

    private fun listAuthorizedFolders(): List<Map<String, String>> =
        deviceFilesPrefs.getStringSet("authorized_roots", emptySet())
            .orEmpty()
            .mapNotNull { rawUri ->
                runCatching {
                    val tree = Uri.parse(rawUri)
                    mapOf(
                        "uri" to rawUri,
                        "name" to DocumentsContract.getTreeDocumentId(tree)
                            .substringAfterLast(':')
                            .ifBlank { "已授权文件夹" }
                    )
                }.getOrNull()
            }

    private fun removeAuthorizedFolder(
        rawUri: String,
        result: MethodChannel.Result
    ) {
        val roots = deviceFilesPrefs.getStringSet("authorized_roots", emptySet())
            .orEmpty().toMutableSet()
        if (!roots.remove(rawUri)) {
            result.error("NOT_FOUND", "授权文件夹不存在", null)
            return
        }
        safSearchIndex.removeRoot(rawUri)
        runCatching {
            contentResolver.releasePersistableUriPermission(
                Uri.parse(rawUri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        }
        deviceFilesPrefs.edit().putStringSet("authorized_roots", roots).apply()
        result.success(mapOf("removed" to true))
    }

    private fun searchAuthorizedFiles(
        query: String,
        requestId: String
    ): Map<String, Any> {
        val roots = deviceFilesPrefs.getStringSet("authorized_roots", emptySet())
            .orEmpty()
        if (roots.isEmpty()) {
            return mapOf(
                "needsFolderPermission" to true,
                "files" to emptyList<Map<String, String>>(),
                "truncated" to false
            )
        }
        val orderedRoots = roots.sorted()
        val refreshed = ensureSearchIndexFresh(orderedRoots, requestId = requestId)
        val search = safSearchIndex.search(orderedRoots, query)
        return mapOf(
            "needsFolderPermission" to false,
            "files" to search.files,
            "truncated" to search.truncated,
            "cancelled" to isSearchCancelled(requestId),
            "indexUsed" to true,
            "indexRefreshedRoots" to refreshed.indexedRoots,
            "indexedDocuments" to refreshed.indexedDocuments,
            "indexComplete" to refreshed.complete,
            "indexUpdatedAtMs" to search.indexedAtMs,
            "incompleteRoots" to search.incompleteRoots,
        )
    }

    private fun isSearchCancelled(requestId: String): Boolean =
        synchronized(cancelledSearches) { requestId in cancelledSearches }

    private data class SearchBudget(
        var visitedDocuments: Int = 0,
        var truncated: Boolean = false
    ) {
        val exhausted: Boolean
            get() = truncated || visitedDocuments >= MAX_SEARCH_DOCUMENTS

        fun visit(depth: Int, resultCount: Int) {
            visitedDocuments++
            if (depth >= MAX_SEARCH_DEPTH ||
                resultCount >= MAX_SEARCH_RESULTS ||
                visitedDocuments >= MAX_SEARCH_DOCUMENTS
            ) {
                truncated = true
            }
        }
    }

    private fun walkDocuments(
        tree: Uri,
        document: Uri,
        needle: String,
        matches: MutableList<Map<String, String>>,
        depth: Int,
        budget: SearchBudget,
        requestId: String
    ) {
        if (budget.exhausted || isSearchCancelled(requestId)) return
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getDocumentId(document)
        )
        contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            ),
            null,
            null,
            null
        )?.use { cursor ->
            val idColumn =
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn =
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeColumn =
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext() && !budget.exhausted &&
                !isSearchCancelled(requestId)
            ) {
                val id = cursor.getString(idColumn)
                val name = cursor.getString(nameColumn) ?: continue
                val mime = cursor.getString(mimeColumn)
                budget.visit(depth, matches.size)
                val child = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    walkDocuments(
                        tree, child, needle, matches, depth + 1, budget, requestId
                    )
                } else if (name.lowercase().contains(needle)) {
                    matches.add(mapOf("name" to name, "uri" to child.toString()))
                }
            }
        }
    }

    private fun openAuthorizedFile(rawUri: String, result: MethodChannel.Result) {
        val uri = Uri.parse(rawUri)
        val authorizedTrees = deviceFilesPrefs
            .getStringSet("authorized_roots", emptySet()).orEmpty()
            .map(Uri::parse)
        val isAuthorized = uri.scheme == "content" && authorizedTrees.any { tree ->
            runCatching {
                DocumentsContract.isTreeUri(tree) &&
                    uri.authority == tree.authority &&
                    DocumentsContract.getDocumentId(uri) !=
                    DocumentsContract.getTreeDocumentId(tree) &&
                    DocumentsContract.getDocumentId(uri).startsWith(
                        DocumentsContract.getTreeDocumentId(tree) + "/"
                    )
            }.getOrDefault(false)
        }
        if (!isAuthorized) {
            result.error("PERMISSION_DENIED", "文件不属于已授权目录", null)
            return
        }
        try {
            val mimeType = contentResolver.getType(uri) ?: "*/*"
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mimeType)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            result.success(mapOf("started" to true))
        } catch (e: ActivityNotFoundException) {
            result.error("NO_HANDLER", "没有应用可以打开这个文件", null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message ?: "打开文件失败", null)
        }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists() || !file.isFile || file.length() < 4L) {
            result.error("INVALID_APK", "更新文件不存在或不完整", null)
            return
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
            val staged = stageInstallApk(file)
            FileProvider.getUriForFile(this, "$packageName.fileprovider", staged)
        } catch (e: IllegalArgumentException) {
            result.error("INVALID_APK", "无法读取更新文件", null)
            return
        } catch (e: IOException) {
            result.error("INVALID_APK", "无法准备安装文件", null)
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

    // 工作台 APK 可能在任意可读路径。先复制进 files/updates，FileProvider 只开放这一层。
    private fun stageInstallApk(source: File): File {
        val updates = File(filesDir, "updates")
        if (!updates.isDirectory && !updates.mkdirs()) {
            throw IOException("无法创建安装目录")
        }
        val staged = File(updates, "install.apk")
        val updatesRoot = updates.canonicalFile
        val stagedCanon = staged.canonicalFile
        val prefix = updatesRoot.path + File.separator
        if (!stagedCanon.path.startsWith(prefix)) {
            throw IOException("安装路径无效")
        }
        if (source.canonicalFile != stagedCanon) {
            source.copyTo(staged, overwrite = true)
        }
        return staged
    }

    companion object {
        private const val MAX_SEARCH_DEPTH = 12
        private const val MAX_SEARCH_RESULTS = 100
        private const val MAX_SEARCH_DOCUMENTS = 10000
        private const val MAX_SAF_BATCH_OPERATIONS = 100
        private const val SEARCH_INDEX_MAX_AGE_MS = 10 * 60 * 1000L
        private const val MAX_APP_PRIVATE_FILE_BYTES = 65536
        private const val MAX_APP_PRIVATE_LIST_BYTES = 65536
        private const val MAX_APP_PRIVATE_RELATIVE_PATH_LENGTH = 512
        private val APP_PRIVATE_TEXT_EXTENSIONS = setOf(
            "conf", "csv", "ini", "json", "log", "md", "properties", "txt", "xml", "yaml", "yml"
        )
    }
}
