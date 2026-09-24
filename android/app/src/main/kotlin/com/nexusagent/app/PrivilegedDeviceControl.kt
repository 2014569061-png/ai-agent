package com.nexusagent.app

import android.annotation.SuppressLint
import android.app.Activity
import android.app.ActivityManager
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * 设备控制中所有“需要特权”的方法（MethodChannel `nexus/device_control` 的子集）。
 *
 * 降级顺序：Root → Shizuku → 普通系统 API → 打开系统设置页让用户手动完成。
 * 共享存储文件操作例外：已获“所有文件访问”时优先以应用自身身份执行（最小权限）。
 *
 * 返回结构统一包含：
 * - `applied`：是否已经真正生效；打开设置页时为 false。
 * - `executedVia`：root / shizuku / app / api / settings / vpn。
 * - `userActionRequired`、`partial`、`fallbackReason`（特权通道没用上的原因）。
 *
 * 命令全部由本类固定模板生成，参数先校验再 shell 转义；不接受任意命令。
 * 所有阻塞操作在后台线程执行，结果回到主线程回复 Flutter。
 */
class PrivilegedDeviceControl(private val activity: Activity) {
    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingVpn: PendingVpnRequest? = null
    private val context: Context get() = activity.applicationContext

    private class PendingVpnRequest(
        val result: MethodChannel.Result,
        val action: () -> Map<String, Any?>,
    )

    private class ControlFailure(
        val code: String,
        message: String,
        val details: Any? = null,
    ) : Exception(message)

    private data class Attempt(val value: Map<String, Any?>?, val reason: String?)

    fun handles(method: String): Boolean = method in METHODS

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "rootStatus" -> async(result) {
                PrivilegeManager.rootState(probe = true) +
                    mapOf("shizuku" to PrivilegeManager.shizukuState())
            }
            "privilegeStatus" -> {
                // 设备能力页自动加载时不探测 su，避免未经点击就弹出 Root 授权框。
                val probeRoot = call.argument<Boolean>("probeRoot") ?: true
                async(result) { privilegeStatus(probeRoot) }
            }
            "requestShizukuPermission" ->
                PrivilegeManager.requestShizukuPermission { granted, reason ->
                    result.success(
                        mapOf(
                            "granted" to granted,
                            "reason" to reason,
                            "shizuku" to PrivilegeManager.shizukuState(),
                        )
                    )
                }
            "openShizuku" -> openShizuku(result)
            "grantPermissionsViaPrivilege" -> async(result) {
                val items = PrivilegeManager.grantSelfPermissions()
                mapOf(
                    "results" to items,
                    "grantedCount" to items.count { it["granted"] == true },
                    "permissions" to PrivilegeManager.permissionState(),
                )
            }
            "openSpecialPermission" -> openSpecialPermission(call.argument<String>("kind"), result)
            "openAppDetails" -> {
                val appPackage = call.argument<String>("packageName")?.trim()
                if (!isValidPackageName(appPackage)) invalid(result, "packageName 无效")
                else async(result) {
                    guided(appDetailsIntent(appPackage!!), "已打开应用详情页", null)
                }
            }
            "refreshDns" -> async(result) {
                requireRootUid("ndc resolver flushdefaultif", "刷新 DNS 缓存需要 Root；免 Root 可切换一次飞行模式或 Wi-Fi 达到同样效果")
            }
            "setWifi" -> withEnabled(call, result, "Wi-Fi 开关参数无效") { setWifi(it) }
            "setBluetooth" -> withEnabled(call, result, "蓝牙开关参数无效") { setBluetooth(it) }
            "setAirplaneMode" -> withEnabled(call, result, "飞行模式参数无效") { setAirplaneMode(it) }
            "setLocationEnabled" -> withEnabled(call, result, "定位开关参数无效") { setLocation(it) }
            "setDoNotDisturb" -> withEnabled(call, result, "勿扰模式参数无效") { setDoNotDisturb(it) }
            "setFontScale" -> {
                val scale = (call.argument<Number>("value") ?: 0).toFloat()
                if (scale !in 0.85f..1.4f) invalid(result, "字体缩放范围必须为 0.85 到 1.4")
                else async(result) { setFontScale(scale) }
            }
            "setAnimationScale" -> {
                val scale = (call.argument<Number>("value") ?: -1).toFloat()
                if (scale !in 0f..10f) invalid(result, "动画倍率范围必须为 0 到 10")
                else async(result) { setAnimationScale(scale) }
            }
            "stopApp" -> withPackage(call, result) { stopApp(it) }
            "restartApp" -> withPackage(call, result) { restartApp(it) }
            "clearAppCache" -> withPackage(call, result) { clearAppCache(it) }
            "killProcess" -> {
                val pid = (call.argument<Number>("pid") ?: 0).toInt()
                val processName = call.argument<String>("processName")?.trim()
                if (pid <= 1 || !isValidProcessName(processName) ||
                    pid == android.os.Process.myPid()
                ) {
                    invalid(result, "PID 或进程名无效")
                } else {
                    async(result) { killProcess(pid, processName!!) }
                }
            }
            "restartService" -> {
                val serviceName = call.argument<String>("serviceName")?.trim()
                if (serviceName == null || serviceName !in RESTARTABLE_ANDROID_SERVICES) {
                    invalid(result, "服务名不在允许重启的白名单中")
                } else {
                    async(result) {
                        requireRootUid("setprop ctl.restart $serviceName", "重启系统服务需要 Root（uid 0）")
                    }
                }
            }
            "runningProcesses" -> asyncAny(result) { runningProcesses() }
            "foregroundApps" -> asyncAny(result) { foregroundApps() }
            "recentApps" -> asyncAny(result) { recentApps() }
            "logcatTail" -> {
                val lines = (call.argument<Number>("lines") ?: 120).toInt().coerceIn(1, 500)
                async(result) { logcatTail(lines) }
            }
            "crashLogs" -> {
                val appPackage = call.argument<String>("packageName")
                if (appPackage != null && !isValidPackageName(appPackage)) {
                    invalid(result, "packageName 无效")
                } else {
                    async(result) { crashLogs(appPackage) }
                }
            }
            "directorySize" -> withPath(call, result, "path", "路径不在允许范围内") { directorySize(it) }
            "readRootFile" -> withPath(call, result, "path", "文件路径不在允许范围内") { readFile(it) }
            "listRootFiles" -> withPath(call, result, "path", "文件路径不在允许范围内") { listFiles(it) }
            "writeRootFile" -> {
                val path = call.argument<String>("path")?.trim()
                val content = call.argument<String>("content")
                if (!isAllowedFilePath(path) || content == null ||
                    content.toByteArray(Charsets.UTF_8).size > MAX_FILE_BYTES
                ) {
                    invalid(result, "文件写入参数无效")
                } else {
                    async(result) {
                        runPrivileged(
                            PrivilegeRequirement.STORAGE,
                            "printf '%s' ${shellQuote(content)} > ${shellQuote(path!!)}",
                            paths = listOf(path),
                        )
                    }
                }
            }
            "deleteRootFile" -> {
                val path = call.argument<String>("path")?.trim()
                if (!isAllowedFilePath(path) || isStorageRoot(path)) {
                    invalid(result, "只能删除白名单目录下的文件")
                } else {
                    async(result) {
                        runPrivileged(
                            PrivilegeRequirement.STORAGE,
                            "rm -f -- ${shellQuote(path!!)}",
                            paths = listOf(path),
                        )
                    }
                }
            }
            "moveRootFile" -> {
                val source = call.argument<String>("source")?.trim()
                val destination = call.argument<String>("destination")?.trim()
                if (!isAllowedFilePath(source) || !isAllowedFilePath(destination) ||
                    isStorageRoot(source) || isStorageRoot(destination)
                ) {
                    invalid(result, "文件移动参数无效")
                } else {
                    async(result) {
                        runPrivileged(
                            PrivilegeRequirement.STORAGE,
                            "mv -n -- ${shellQuote(source!!)} ${shellQuote(destination!!)}",
                            paths = listOf(source, destination),
                        )
                    }
                }
            }
            "compressRootFiles" -> {
                val sources = call.argument<List<String>>("sources").orEmpty()
                val destination = call.argument<String>("destination")?.trim()
                if (sources.isEmpty() || sources.size > 50 ||
                    sources.any { !isAllowedFilePath(it) } ||
                    !isAllowedFilePath(destination) || isStorageRoot(destination)
                ) {
                    invalid(result, "压缩路径参数无效")
                } else {
                    async(result) { compress(sources, destination!!) }
                }
            }
            "extractRootArchive" -> {
                val archive = call.argument<String>("archive")?.trim()
                val destination = call.argument<String>("destination")?.trim()
                if (!isAllowedFilePath(archive) || !isAllowedFilePath(destination) ||
                    isStorageRoot(archive) || isStorageRoot(destination)
                ) {
                    invalid(result, "解压路径参数无效")
                } else {
                    async(result) {
                        runPrivileged(
                            PrivilegeRequirement.STORAGE,
                            "mkdir -p ${shellQuote(destination!!)} && tar -xzf " +
                                "${shellQuote(archive!!)} -C ${shellQuote(destination)}",
                            paths = listOf(archive, destination),
                            timeoutMs = LONG_TIMEOUT_MS,
                        )
                    }
                }
            }
            "setFirewallPortRule" -> {
                val protocol = call.argument<String>("protocol")
                val rawPort = call.argument<Number>("port")
                val port = rawPort?.toInt()
                val enabled = call.argument<Boolean>("enabled")
                if (protocol !in setOf("tcp", "udp") ||
                    port == null || port !in 1..65535 ||
                    rawPort.toDouble() != port.toDouble() ||
                    enabled == null
                ) {
                    invalid(result, "防火墙规则仅接受 tcp/udp 和 1–65535 端口")
                } else {
                    async(result) {
                        requireRootUid(
                            firewallScript(protocol!!, port, enabled),
                            "端口防火墙需要 Root（iptables）。免 Root 可改用按应用断网" +
                                "（set_app_network_block）或域名屏蔽（set_hosts_block）",
                        )
                    }
                }
            }
            "setHostsBlock" -> {
                val domain = call.argument<String>("domain")?.trim()?.lowercase()
                val enabled = call.argument<Boolean>("enabled")
                if (!isValidDomain(domain) || enabled == null) {
                    invalid(result, "hosts 操作需要有效域名和 enabled 布尔值")
                } else {
                    setHostsBlock(domain!!, enabled, result)
                }
            }
            "networkFilterStatus" -> async(result) { NetworkFilterStore.status(context) }
            "setNetworkFilterEnabled" -> {
                val enabled = call.argument<Boolean>("enabled")
                if (enabled == null) invalid(result, "enabled 参数无效")
                else if (enabled) {
                    withVpnConsent(result) {
                        NetworkFilterStore.setEnabled(context, true)
                        mapOf("applied" to true, "executedVia" to "vpn", "enabled" to true)
                    }
                } else {
                    finishVpn(result) {
                        NetworkFilterStore.setEnabled(context, false)
                        mapOf("applied" to true, "executedVia" to "vpn", "enabled" to false)
                    }
                }
            }
            "setAppNetworkBlock" -> {
                val appPackage = call.argument<String>("packageName")?.trim()
                val enabled = call.argument<Boolean>("enabled")
                when {
                    !isValidPackageName(appPackage) || enabled == null ->
                        invalid(result, "需要有效 packageName 和 enabled 布尔值")
                    appPackage == activity.packageName ->
                        invalid(result, "不能对 NEXUS 自身断网")
                    else -> applyVpnRule(result, enabled) {
                        val previously = NetworkFilterStore.setApp(context, appPackage!!, enabled)
                        mapOf(
                            "applied" to true,
                            "executedVia" to "vpn",
                            "packageName" to appPackage,
                            "blocked" to enabled,
                            "previouslyBlocked" to previously,
                            "undo" to mapOf("packageName" to appPackage, "enabled" to previously),
                        )
                    }
                }
            }
            "setDomainBlock" -> {
                val domain = call.argument<String>("domain")?.trim()?.lowercase()
                val enabled = call.argument<Boolean>("enabled")
                if (!isValidDomain(domain) || enabled == null) {
                    invalid(result, "需要有效域名和 enabled 布尔值")
                } else {
                    applyVpnRule(result, enabled) { domainRule(domain!!, enabled) }
                }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * MainActivity 中亮度/自动旋转/刷新率在缺少 WRITE_SETTINGS 时的写入：
     * 先走 Root/Shizuku，都不可用则打开“修改系统设置”授权页。命令来自调用方固定模板。
     */
    fun runSettingsCommand(command: String, result: MethodChannel.Result) {
        async(result) {
            val attempt = attempt(PrivilegeRequirement.SHELL, command)
            attempt.value ?: guided(
                Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${activity.packageName}")),
                "需要允许 NEXUS“修改系统设置”，已打开授权页；授权后重试即可",
                attempt.reason,
            )
        }
    }

    /** 返回 true 表示请求码属于本模块。 */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != VPN_REQUEST_CODE) return false
        val pending = pendingVpn ?: return true
        pendingVpn = null
        if (resultCode == Activity.RESULT_OK) {
            finishVpn(pending.result, pending.action)
        } else {
            pending.result.error(
                "PERMISSION_DENIED",
                "用户拒绝了 VPN 连接授权；规则未修改",
                null,
            )
        }
        return true
    }

    fun shutdown() {
        pendingVpn?.result?.error("CANCELLED", "页面已关闭", null)
        pendingVpn = null
        executor.shutdownNow()
    }

    // ------------------------------------------------------------------
    // 状态
    // ------------------------------------------------------------------

    private fun privilegeStatus(probeRoot: Boolean): Map<String, Any?> {
        val root = PrivilegeManager.rootState(probe = probeRoot)
        val shizuku = PrivilegeManager.shizukuState()
        val permissions = PrivilegeManager.permissionState()
        val rootOk = root["rootGranted"] == true
        val shizukuOk = shizuku["permissionGranted"] == true
        val shizukuRoot = shizukuOk && shizuku["uid"] == 0
        val shell = when {
            rootOk -> "root"
            shizukuOk -> "shizuku"
            else -> null
        }
        val rootUid = when {
            rootOk -> "root"
            shizukuRoot -> "shizuku"
            else -> null
        }
        val storage = when {
            permissions["allFilesAccess"] == true -> "app"
            else -> shell
        }
        return mapOf(
            "root" to root,
            "shizuku" to shizuku,
            "permissions" to permissions,
            "networkFilter" to NetworkFilterStore.status(context),
            "sdkInt" to Build.VERSION.SDK_INT,
            "routes" to mapOf(
                "shell" to shell,
                "rootUid" to rootUid,
                "storage" to storage,
                "storageDataLocalTmp" to shell,
            ),
        )
    }

    // ------------------------------------------------------------------
    // 系统设置
    // ------------------------------------------------------------------

    private fun setWifi(enabled: Boolean): Map<String, Any?> {
        val attempt = attempt(PrivilegeRequirement.SHELL, "svc wifi ${onOff(enabled, "enable", "disable")}")
        attempt.value?.let { return it + mapOf("enabled" to enabled) }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val wifi = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            val ok = runCatching { wifi.setWifiEnabled(enabled) }.getOrDefault(false)
            if (ok) return api(attempt.reason, mapOf("enabled" to enabled))
        }
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Intent(Settings.Panel.ACTION_WIFI)
        } else {
            Intent(Settings.ACTION_WIFI_SETTINGS)
        }
        return guided(intent, "已打开 Wi-Fi 面板，请手动${onOff(enabled, "开启", "关闭")} Wi-Fi", attempt.reason)
    }

    @SuppressLint("MissingPermission")
    private fun setBluetooth(enabled: Boolean): Map<String, Any?> {
        val primary = attempt(
            PrivilegeRequirement.SHELL,
            "cmd bluetooth_manager ${onOff(enabled, "enable", "disable")}",
        )
        primary.value?.let { return it + mapOf("enabled" to enabled) }
        var reason = primary.reason
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && reason?.contains("不可用") != true) {
            val legacy = attempt(
                PrivilegeRequirement.SHELL,
                "svc bluetooth ${onOff(enabled, "enable", "disable")}",
            )
            legacy.value?.let { return it + mapOf("enabled" to enabled) }
            reason = listOfNotNull(reason, legacy.reason).joinToString("；")
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && PrivilegeManager.bluetoothConnect()) {
            val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            @Suppress("DEPRECATION")
            val ok = adapter != null && runCatching {
                if (enabled) adapter.enable() else adapter.disable()
            }.getOrDefault(false)
            if (ok) return api(reason, mapOf("enabled" to enabled))
        }
        return if (enabled && PrivilegeManager.bluetoothConnect()) {
            guided(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), "已弹出系统开启蓝牙确认框，请点击允许", reason)
        } else {
            guided(
                Intent(Settings.ACTION_BLUETOOTH_SETTINGS),
                "已打开蓝牙设置页，请手动${onOff(enabled, "开启", "关闭")}蓝牙",
                reason,
            )
        }
    }

    private fun setAirplaneMode(enabled: Boolean): Map<String, Any?> {
        val attempt = attempt(
            PrivilegeRequirement.SHELL,
            "cmd connectivity airplane-mode ${onOff(enabled, "enable", "disable")}",
        )
        attempt.value?.let { return it + mapOf("enabled" to enabled) }
        return guided(
            Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS),
            "已打开飞行模式设置页，请手动${onOff(enabled, "开启", "关闭")}",
            attempt.reason,
        )
    }

    private fun setLocation(enabled: Boolean): Map<String, Any?> {
        val primary = attempt(
            PrivilegeRequirement.SHELL,
            "cmd location set-location-enabled $enabled --user current",
        )
        primary.value?.let { return it + mapOf("enabled" to enabled) }
        var reason = primary.reason
        if (reason?.contains("不可用") != true) {
            val legacy = attempt(
                PrivilegeRequirement.SHELL,
                "settings put secure location_mode ${if (enabled) 3 else 0}",
            )
            legacy.value?.let { return it + mapOf("enabled" to enabled) }
            reason = listOfNotNull(reason, legacy.reason).joinToString("；")
        }
        return guided(
            Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS),
            "已打开定位设置页，请手动${onOff(enabled, "开启", "关闭")}定位",
            reason,
        )
    }

    private fun setDoNotDisturb(enabled: Boolean): Map<String, Any?> {
        val attempt = attempt(
            PrivilegeRequirement.SHELL,
            "cmd notification set_dnd ${onOff(enabled, "on", "off")}",
        )
        attempt.value?.let { return it + mapOf("enabled" to enabled) }
        if (PrivilegeManager.notificationPolicyAccess()) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.setInterruptionFilter(
                if (enabled) NotificationManager.INTERRUPTION_FILTER_PRIORITY
                else NotificationManager.INTERRUPTION_FILTER_ALL
            )
            return api(attempt.reason, mapOf("enabled" to enabled, "filter" to if (enabled) "priority" else "all"))
        }
        return guided(
            Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS),
            "需要先授予 NEXUS“勿扰权限”，已打开授权页；授权后重试即可直接切换",
            attempt.reason,
        )
    }

    private fun setFontScale(value: Float): Map<String, Any?> {
        val normalized = String.format(Locale.US, "%.2f", value)
        if (PrivilegeManager.writeSettings()) {
            val ok = runCatching {
                Settings.System.putFloat(context.contentResolver, Settings.System.FONT_SCALE, value)
            }.getOrDefault(false)
            if (ok) return api(null, mapOf("fontScale" to value))
        }
        val attempt = attempt(PrivilegeRequirement.SHELL, "settings put system font_scale $normalized")
        attempt.value?.let { return it + mapOf("fontScale" to value) }
        return guided(
            Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${activity.packageName}")),
            "需要允许 NEXUS“修改系统设置”，已打开授权页；授权后重试即可",
            attempt.reason,
        )
    }

    private fun setAnimationScale(value: Float): Map<String, Any?> {
        val normalized = String.format(Locale.US, "%.2f", value)
        val command = ANIMATION_KEYS.joinToString(" && ") { "settings put global $it $normalized" }
        val attempt = attempt(PrivilegeRequirement.SHELL, command)
        attempt.value?.let { return it + mapOf("animationScale" to value) }
        if (PrivilegeManager.writeSecureSettings()) {
            val ok = runCatching {
                ANIMATION_KEYS.all { Settings.Global.putFloat(context.contentResolver, it, value) }
            }.getOrDefault(false)
            if (ok) return api(attempt.reason, mapOf("animationScale" to value))
        }
        return guided(
            Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS),
            "已打开开发者选项，请手动调整三项动画缩放；连接 Shizuku 后可一键授予 WRITE_SECURE_SETTINGS 实现直接修改",
            attempt.reason,
        )
    }

    // ------------------------------------------------------------------
    // 应用与进程
    // ------------------------------------------------------------------

    private fun stopApp(appPackage: String): Map<String, Any?> {
        val attempt = attempt(PrivilegeRequirement.SHELL, "am force-stop $appPackage")
        attempt.value?.let { return it + mapOf("packageName" to appPackage) }
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        runCatching { manager.killBackgroundProcesses(appPackage) }
        return guided(
            appDetailsIntent(appPackage),
            "已结束该应用的后台进程；它若仍有前台服务，请在应用详情页点“强制停止”",
            attempt.reason,
            mapOf("partial" to true, "killedBackgroundProcesses" to true, "packageName" to appPackage),
        )
    }

    private fun restartApp(appPackage: String): Map<String, Any?> {
        val launch = context.packageManager.getLaunchIntentForPackage(appPackage)
            ?: throw ControlFailure("NOT_FOUND", "没有找到可启动的应用")
        val attempt = attempt(PrivilegeRequirement.SHELL, "am force-stop $appPackage")
        val stopped = attempt.value
        if (stopped == null) {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            runCatching { manager.killBackgroundProcesses(appPackage) }
        }
        if (!launchOnMain(launch)) throw ControlFailure("LAUNCH_FAILED", "应用重启失败：无法启动")
        return if (stopped != null) {
            stopped + mapOf("packageName" to appPackage, "relaunched" to true)
        } else {
            mapOf(
                "applied" to true,
                "executedVia" to "api",
                "partial" to true,
                "packageName" to appPackage,
                "relaunched" to true,
                "fallbackReason" to attempt.reason,
                "message" to "无特权时只能结束后台进程后重新打开；应用若有前台服务可能不会真正重启",
            )
        }
    }

    private fun clearAppCache(appPackage: String): Map<String, Any?> {
        val primary = attempt(PrivilegeRequirement.ROOT_UID, clearCacheScript(appPackage))
        primary.value?.let { return it + mapOf("packageName" to appPackage) }
        var reason = primary.reason
        if (Build.VERSION.SDK_INT >= 34) {
            val shell = attempt(PrivilegeRequirement.SHELL, "pm clear --cache-only $appPackage")
            shell.value?.let { return it + mapOf("packageName" to appPackage) }
            reason = listOfNotNull(reason, shell.reason).joinToString("；")
        }
        return guided(
            appDetailsIntent(appPackage),
            "已打开应用详情页，请进入“存储”点击“清除缓存”（不要点“清除数据”）",
            reason,
            mapOf("packageName" to appPackage),
        )
    }

    private fun killProcess(pid: Int, processName: String): Map<String, Any?> =
        requireRootUid(
            killScript(pid, processName),
            "结束其它应用的进程需要 Root（uid 0）；免 Root 请改用 stop_app 停止整个应用",
            exitMessages = mapOf(
                31 to "进程不存在或无法读取",
                32 to "PID 对应的进程名不匹配，已拒绝结束",
                33 to "发送 SIGTERM 失败",
            ),
        )

    private fun runningProcesses(): List<Map<String, Any?>> {
        if (PrivilegeManager.preferredBackend(PrivilegeRequirement.SHELL) != null) {
            runCatching {
                val outcome = PrivilegeManager.run(
                    PrivilegeRequirement.SHELL,
                    "ps -A -o PID,UID,RSS,NAME",
                    timeoutMs = 6000,
                )
                if (outcome.exitCode == 0) {
                    val items = outcome.stdout.lineSequence().drop(1).mapNotNull { line ->
                        val parts = line.trim().split(Regex("\\s+"), limit = 4)
                        if (parts.size < 4) return@mapNotNull null
                        val pid = parts[0].toIntOrNull() ?: return@mapNotNull null
                        mapOf(
                            "pid" to pid,
                            "uid" to parts[1],
                            "rssKb" to (parts[2].toLongOrNull() ?: 0L),
                            "processName" to parts[3],
                            "source" to outcome.backend.id,
                        )
                    }.toList()
                    if (items.isNotEmpty()) return items.take(MAX_PROCESSES)
                }
            }
        }
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return manager.runningAppProcesses.orEmpty().map { process ->
            mapOf(
                "processName" to process.processName,
                "pid" to process.pid,
                "importance" to process.importance,
                "packages" to process.pkgList.toList(),
                "source" to "app",
                "scope" to "仅本应用可见的进程；连接 Shizuku 或 Root 后可列出全部进程",
            )
        }
    }

    private fun foregroundApps(): List<Map<String, Any?>> {
        if (PrivilegeManager.usageAccess()) {
            val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val end = System.currentTimeMillis()
            val events = manager.queryEvents(end - 10 * 60 * 1000L, end)
            val event = UsageEvents.Event()
            var lastPackage: String? = null
            var lastAt = 0L
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                @Suppress("DEPRECATION")
                val resumed = event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
                if (resumed && event.packageName != activity.packageName) {
                    lastPackage = event.packageName
                    lastAt = event.timeStamp
                }
            }
            return listOfNotNull(
                lastPackage?.let {
                    mapOf("packageName" to it, "lastForegroundMs" to lastAt, "source" to "usage_stats")
                }
            )
        }
        if (PrivilegeManager.preferredBackend(PrivilegeRequirement.SHELL) != null) {
            runCatching {
                val outcome = PrivilegeManager.run(
                    PrivilegeRequirement.SHELL,
                    "dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | head -n 3",
                    timeoutMs = 6000,
                )
                val match = Regex("u\\d+ ([A-Za-z0-9_.]+)/").find(outcome.stdout)
                if (match != null) {
                    return listOf(
                        mapOf("packageName" to match.groupValues[1], "source" to outcome.backend.id)
                    )
                }
            }
        }
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return manager.runningAppProcesses.orEmpty()
            .filter { it.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND }
            .map { process ->
                mapOf(
                    "processName" to process.processName,
                    "pid" to process.pid,
                    "importance" to process.importance,
                    "packages" to process.pkgList.toList(),
                    "source" to "app",
                )
            }
    }

    private fun recentApps(): List<Map<String, Any?>> {
        if (!PrivilegeManager.usageAccess()) return emptyList()
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        return manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, end - 24 * 3600 * 1000L, end)
            .orEmpty()
            .filter { it.totalTimeInForeground > 0 && it.packageName != activity.packageName }
            .groupBy { it.packageName }
            .map { (pkg, stats) ->
                mapOf(
                    "packageName" to pkg,
                    "lastTimeUsed" to stats.maxOf { it.lastTimeUsed },
                    "foregroundMs" to stats.sumOf { it.totalTimeInForeground },
                    "source" to "usage_stats",
                )
            }
            .sortedByDescending { it["lastTimeUsed"] as Long }
            .take(20)
    }

    // ------------------------------------------------------------------
    // 日志
    // ------------------------------------------------------------------

    private fun logcatTail(lines: Int): Map<String, Any?> {
        val command = "logcat -d -t $lines"
        val privileged = runLogcat(command, MAX_LOG_CHARS)
        if (privileged != null) return privileged
        return try {
            val process = ProcessBuilder("logcat", "-d", "-t", lines.toString())
                .redirectErrorStream(true).start()
            val output = process.inputStream.bufferedReader().readText().takeLast(MAX_LOG_CHARS)
            if (!process.waitFor(3, TimeUnit.SECONDS)) process.destroyForcibly()
            mapOf(
                "text" to output,
                "truncated" to (output.length >= MAX_LOG_CHARS),
                "source" to "app",
                "scope" to if (PrivilegeManager.readLogs()) "all" else "app_only",
            )
        } catch (e: Exception) {
            mapOf("text" to "", "error" to (e.message ?: "无法读取 Logcat"), "source" to "app")
        }
    }

    private fun crashLogs(appPackage: String?): Map<String, Any?> {
        val raw: String
        val source: String
        val completed: Boolean
        val privileged = runCatching {
            if (PrivilegeManager.preferredBackend(PrivilegeRequirement.SHELL) == null) null
            else PrivilegeManager.run(
                PrivilegeRequirement.SHELL,
                "logcat -d -v threadtime -b main,crash",
                timeoutMs = 8000,
                maxStdoutBytes = 4 * 1024 * 1024,
            )
        }.getOrNull()
        if (privileged != null && privileged.exitCode == 0) {
            raw = privileged.stdout
            source = privileged.backend.id
            completed = true
        } else {
            val process = ProcessBuilder("logcat", "-d", "-v", "threadtime")
                .redirectErrorStream(true).start()
            raw = process.inputStream.bufferedReader().readText()
            completed = process.waitFor(5, TimeUnit.SECONDS)
            if (!completed) process.destroyForcibly()
            source = "app"
        }
        val filtered = raw.lineSequence()
            .filter { line ->
                (line.contains("FATAL EXCEPTION") || line.contains("AndroidRuntime") ||
                    line.contains("Process:")) &&
                    (appPackage == null || line.contains(appPackage))
            }
            .toList()
            .takeLast(800)
            .joinToString("\n")
            .take(MAX_LOG_CHARS)
        return mapOf(
            "packageName" to (appPackage ?: ""),
            "text" to filtered,
            "truncated" to (filtered.length >= MAX_LOG_CHARS),
            "completed" to completed,
            "source" to source,
            "scope" to if (source != "app" || PrivilegeManager.readLogs()) "all" else "app_only",
        )
    }

    private fun runLogcat(command: String, maxChars: Int): Map<String, Any?>? {
        if (PrivilegeManager.preferredBackend(PrivilegeRequirement.SHELL) == null) return null
        return runCatching {
            val outcome = PrivilegeManager.run(PrivilegeRequirement.SHELL, command, timeoutMs = 6000)
            if (outcome.exitCode != 0) return null
            val text = outcome.stdout.takeLast(maxChars)
            mapOf(
                "text" to text,
                "truncated" to (text.length >= maxChars || outcome.stdoutTruncated),
                "source" to outcome.backend.id,
                "scope" to "all",
            )
        }.getOrNull()
    }

    // ------------------------------------------------------------------
    // 文件
    // ------------------------------------------------------------------

    private fun directorySize(path: String): Map<String, Any?> {
        val outcome = PrivilegeManager.run(
            PrivilegeRequirement.STORAGE,
            "du -sk -- ${shellQuote(path)}",
            timeoutMs = LONG_TIMEOUT_MS,
            paths = listOf(path),
        )
        checkOutcome(outcome)
        val kb = outcome.stdout.trim().substringBefore('\t').substringBefore(' ').toLongOrNull() ?: 0L
        return mapOf("path" to path, "bytes" to kb * 1024L, "executedVia" to outcome.backend.id)
    }

    private fun readFile(path: String): Map<String, Any?> {
        val outcome = PrivilegeManager.run(
            PrivilegeRequirement.STORAGE,
            "head -c ${MAX_FILE_BYTES + 1} -- ${shellQuote(path)}",
            paths = listOf(path),
            maxStdoutBytes = MAX_FILE_BYTES + 1,
        )
        checkOutcome(outcome)
        val bytes = outcome.stdoutBytes
        val truncated = bytes.size > MAX_FILE_BYTES
        val content = if (truncated) bytes.copyOf(MAX_FILE_BYTES) else bytes
        return mapOf(
            "path" to path,
            "content" to content.toString(Charsets.UTF_8),
            "truncated" to truncated,
            "bytes" to content.size,
            "executedVia" to outcome.backend.id,
        )
    }

    private fun listFiles(path: String): Map<String, Any?> {
        val outcome = PrivilegeManager.run(
            PrivilegeRequirement.STORAGE,
            "ls -la -- ${shellQuote(path)}",
            paths = listOf(path),
            maxStdoutBytes = MAX_LIST_BYTES,
        )
        checkOutcome(outcome)
        return mapOf(
            "path" to path,
            "text" to outcome.stdout,
            "truncated" to outcome.stdoutTruncated,
            "executedVia" to outcome.backend.id,
        )
    }

    private fun compress(sources: List<String>, destination: String): Map<String, Any?> {
        val command = buildString {
            append("tar -czf ")
            append(shellQuote(destination))
            append(" --")
            sources.forEach {
                append(' ')
                append(shellQuote(it))
            }
        }
        return runPrivileged(
            PrivilegeRequirement.STORAGE,
            command,
            paths = sources + destination,
            timeoutMs = LONG_TIMEOUT_MS,
        )
    }

    // ------------------------------------------------------------------
    // 网络过滤
    // ------------------------------------------------------------------

    private fun setHostsBlock(domain: String, enabled: Boolean, result: MethodChannel.Result) {
        executor.execute {
            val attempt = attempt(PrivilegeRequirement.ROOT_UID, hostsScript(domain, enabled))
            mainHandler.post {
                val value = attempt.value
                if (value != null) {
                    result.success(value + mapOf("domain" to domain, "enabled" to enabled))
                } else {
                    applyVpnRule(result, enabled) {
                        domainRule(domain, enabled) + mapOf("fallbackReason" to attempt.reason)
                    }
                }
            }
        }
    }

    private fun domainRule(domain: String, enabled: Boolean): Map<String, Any?> {
        val previously = NetworkFilterStore.setDomain(context, domain, enabled)
        return mapOf(
            "applied" to true,
            "executedVia" to "vpn",
            "domain" to domain,
            "blocked" to enabled,
            "previouslyBlocked" to previously,
            "undo" to mapOf("domain" to domain, "enabled" to previously),
        )
    }

    /** 开启规则需要 VPN 授权；关闭规则直接生效（规则清空后 VPN 自动停止）。 */
    private fun applyVpnRule(
        result: MethodChannel.Result,
        enabling: Boolean,
        action: () -> Map<String, Any?>,
    ) {
        if (enabling) {
            withVpnConsent(result) {
                val value = action()
                NetworkFilterStore.setEnabled(context, true)
                value
            }
        } else {
            finishVpn(result, action)
        }
    }

    private fun withVpnConsent(result: MethodChannel.Result, action: () -> Map<String, Any?>) {
        val intent = try {
            VpnService.prepare(activity)
        } catch (e: Exception) {
            result.error("UNAVAILABLE", e.message ?: "设备不支持 VPN", null)
            return
        }
        if (intent == null) {
            finishVpn(result, action)
            return
        }
        if (pendingVpn != null) {
            result.error("BUSY", "已有一个 VPN 授权请求在等待用户处理", null)
            return
        }
        pendingVpn = PendingVpnRequest(result, action)
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, VPN_REQUEST_CODE)
        } catch (e: Exception) {
            pendingVpn = null
            result.error("UNAVAILABLE", e.message ?: "无法打开 VPN 授权弹窗", null)
        }
    }

    private fun finishVpn(result: MethodChannel.Result, action: () -> Map<String, Any?>) {
        async(result) {
            val value = action()
            NetworkFilterVpnService.sync(context)
            Thread.sleep(VPN_SETTLE_MS)
            val status = NetworkFilterStore.status(context)
            val shouldRun = status["enabled"] == true && status["desiredMode"] != null
            if (shouldRun && status["running"] != true) {
                val error = NetworkFilterVpnService.lastError
                if (error != null) throw ControlFailure("VPN_START_FAILED", "规则已保存，但 VPN 启动失败：$error")
            }
            value + mapOf(
                "filter" to status,
                "vpnRunning" to status["running"],
                "mode" to status["mode"],
            )
        }
    }

    // ------------------------------------------------------------------
    // 权限页
    // ------------------------------------------------------------------

    private fun openShizuku(result: MethodChannel.Result) {
        val launch = context.packageManager.getLaunchIntentForPackage(PrivilegeManager.SHIZUKU_PACKAGE)
        val intent = launch ?: Intent(Intent.ACTION_VIEW, Uri.parse(PrivilegeManager.SHIZUKU_DOWNLOAD_URL))
        try {
            activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(mapOf("opened" to true, "installed" to (launch != null)))
        } catch (e: ActivityNotFoundException) {
            result.error("UNAVAILABLE", "无法打开 Shizuku 或下载页", null)
        }
    }

    private fun openSpecialPermission(kind: String?, result: MethodChannel.Result) {
        val pkgUri = Uri.parse("package:${activity.packageName}")
        if (kind == "vpn") {
            withVpnConsent(result) {
                mapOf("granted" to true, "permissions" to PrivilegeManager.permissionState())
            }
            return
        }
        val intent = when (kind) {
            "all_files" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, pkgUri)
            } else {
                appDetailsIntent(activity.packageName)
            }
            "usage" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            "notification_policy" -> Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            "write_settings" -> Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, pkgUri)
            "install_packages" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, pkgUri)
            } else {
                Intent(Settings.ACTION_SECURITY_SETTINGS)
            }
            "bluetooth" -> appDetailsIntent(activity.packageName)
            else -> {
                invalid(result, "kind 仅支持 all_files/usage/notification_policy/write_settings/install_packages/vpn/bluetooth")
                return
            }
        }
        try {
            activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(mapOf("opened" to true, "kind" to kind, "userActionRequired" to true))
        } catch (e: Exception) {
            try {
                activity.startActivity(appDetailsIntent(activity.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(mapOf("opened" to true, "kind" to kind, "fallback" to "app_details", "userActionRequired" to true))
            } catch (_: Exception) {
                result.error("UNAVAILABLE", "设备没有对应的权限设置页面", null)
            }
        }
    }

    // ------------------------------------------------------------------
    // 执行辅助
    // ------------------------------------------------------------------

    private fun attempt(
        requirement: PrivilegeRequirement,
        command: String,
        paths: List<String> = emptyList(),
        timeoutMs: Long = PrivilegeManager.DEFAULT_TIMEOUT_MS,
    ): Attempt = try {
        Attempt(runPrivileged(requirement, command, paths, timeoutMs), null)
    } catch (e: PrivilegeUnavailableException) {
        Attempt(null, "特权通道不可用：${e.message}")
    } catch (e: PrivilegeTimeoutException) {
        Attempt(null, e.message)
    } catch (e: ControlFailure) {
        Attempt(null, e.message)
    } catch (e: IOException) {
        Attempt(null, e.message)
    }

    private fun runPrivileged(
        requirement: PrivilegeRequirement,
        command: String,
        paths: List<String> = emptyList(),
        timeoutMs: Long = PrivilegeManager.DEFAULT_TIMEOUT_MS,
        exitMessages: Map<Int, String> = emptyMap(),
    ): Map<String, Any?> {
        val outcome = PrivilegeManager.run(requirement, command, timeoutMs, paths)
        checkOutcome(outcome, exitMessages)
        return mapOf(
            "applied" to true,
            "executedVia" to outcome.backend.id,
            "output" to outcome.stdout.trim().take(500),
        )
    }

    /** 只有 Root 能做的操作：不可用时抛出带替代建议的明确错误。 */
    private fun requireRootUid(
        command: String,
        unavailableHint: String,
        exitMessages: Map<Int, String> = emptyMap(),
    ): Map<String, Any?> = try {
        runPrivileged(PrivilegeRequirement.ROOT_UID, command, exitMessages = exitMessages)
    } catch (e: PrivilegeUnavailableException) {
        throw ControlFailure(
            "ROOT_REQUIRED",
            unavailableHint,
            PrivilegeManager.unavailableDetails(PrivilegeRequirement.ROOT_UID),
        )
    }

    private fun checkOutcome(outcome: ShellOutcome, exitMessages: Map<Int, String> = emptyMap()) {
        if (outcome.exitCode == 0) return
        val error = outcome.stderr.ifBlank { outcome.stdout }.trim().take(400)
        val detail = exitMessages[outcome.exitCode] ?: error.ifBlank { "退出码 ${outcome.exitCode}" }
        val code = when {
            outcome.backend == PrivilegeBackend.ROOT &&
                (error.contains("not allowed", true) ||
                    (error.contains("denied", true) && error.contains("su", true))) -> "ROOT_DENIED"
            error.contains("avc:", true) || error.contains("SELinux", true) -> "SELINUX_DENIED"
            error.contains("Permission denied", true) || error.contains("SecurityException") ->
                "PERMISSION_DENIED"
            outcome.backend == PrivilegeBackend.ROOT -> "ROOT_COMMAND_FAILED"
            else -> "PRIVILEGED_COMMAND_FAILED"
        }
        throw ControlFailure(
            code,
            "${outcome.backend.label} 执行失败：$detail",
            mapOf("executedVia" to outcome.backend.id, "exitCode" to outcome.exitCode),
        )
    }

    private fun api(reason: String?, extra: Map<String, Any?>): Map<String, Any?> =
        mapOf("applied" to true, "executedVia" to "api", "fallbackReason" to reason) + extra

    private fun guided(
        intent: Intent,
        message: String,
        reason: String?,
        extra: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> {
        val opened = launchOnMain(intent) || launchOnMain(Intent(Settings.ACTION_SETTINGS))
        if (!opened) throw ControlFailure("UNAVAILABLE", "设备没有对应的系统设置页面", mapOf("fallbackReason" to reason))
        return mapOf(
            "applied" to false,
            "executedVia" to "settings",
            "userActionRequired" to true,
            "opened" to true,
            "message" to message,
            "fallbackReason" to reason,
        ) + extra
    }

    private fun launchOnMain(intent: Intent): Boolean {
        val latch = CountDownLatch(1)
        var ok = false
        mainHandler.post {
            ok = try {
                activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (_: Exception) {
                false
            }
            latch.countDown()
        }
        latch.await(3, TimeUnit.SECONDS)
        return ok
    }

    private fun appDetailsIntent(appPackage: String): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$appPackage"))

    private fun async(result: MethodChannel.Result, block: () -> Map<String, Any?>) =
        asyncAny(result, block)

    private fun asyncAny(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: ControlFailure) {
                mainHandler.post { result.error(e.code, e.message, e.details) }
            } catch (e: PrivilegeUnavailableException) {
                mainHandler.post {
                    result.error(e.code, e.message, PrivilegeManager.unavailableDetails(e.requirement))
                }
            } catch (e: PrivilegeTimeoutException) {
                mainHandler.post { result.error("TIMEOUT", e.message, null) }
            } catch (e: SecurityException) {
                mainHandler.post { result.error("PERMISSION_DENIED", e.message ?: "权限被拒绝", null) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("DEVICE_CONTROL_FAILED", e.message ?: "设备操作失败", null)
                }
            }
        }
    }

    private fun withEnabled(
        call: MethodCall,
        result: MethodChannel.Result,
        message: String,
        block: (Boolean) -> Map<String, Any?>,
    ) {
        val enabled = call.argument<Boolean>("enabled")
        if (enabled == null) invalid(result, message) else async(result) { block(enabled) }
    }

    private fun withPackage(
        call: MethodCall,
        result: MethodChannel.Result,
        block: (String) -> Map<String, Any?>,
    ) {
        val appPackage = call.argument<String>("packageName")?.trim()
        if (!isValidPackageName(appPackage)) invalid(result, "packageName 无效")
        else async(result) { block(appPackage!!) }
    }

    private fun withPath(
        call: MethodCall,
        result: MethodChannel.Result,
        key: String,
        message: String,
        block: (String) -> Map<String, Any?>,
    ) {
        val path = call.argument<String>(key)?.trim()
        if (!isAllowedFilePath(path)) invalid(result, message) else async(result) { block(path!!) }
    }

    private fun invalid(result: MethodChannel.Result, message: String) =
        result.error("INVALID_ARGS", message, null)

    private fun onOff(enabled: Boolean, on: String, off: String): String = if (enabled) on else off

    // ------------------------------------------------------------------
    // 校验（与 MainActivity 原规则保持一致）
    // ------------------------------------------------------------------

    private fun isValidPackageName(value: String?): Boolean =
        value != null && Regex("^[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+$").matches(value)

    private fun isValidProcessName(value: String?): Boolean =
        value != null &&
            value.length <= 255 &&
            Regex("^[A-Za-z0-9_./:-]+$").matches(value) &&
            value !in PROTECTED_PROCESSES

    private fun isAllowedFilePath(path: String?): Boolean {
        if (path.isNullOrBlank() || !path.startsWith("/") ||
            path.contains('\u0000') || path.contains("/../") ||
            path.endsWith("/..") || path.contains("/./") || path.endsWith("/.")
        ) {
            return false
        }
        val normalized = path.replace(Regex("/+"), "/")
        return FILE_ROOTS.any { root -> normalized == root || normalized.startsWith("$root/") }
    }

    private fun isStorageRoot(path: String?): Boolean {
        val normalized = path?.replace(Regex("/+"), "/") ?: return false
        return normalized in FILE_ROOTS
    }

    private fun isValidDomain(value: String?): Boolean {
        if (value.isNullOrBlank() || value.length > 253 || !value.contains('.') ||
            value.endsWith('.')
        ) {
            return false
        }
        return value.split('.').all { label ->
            label.length <= 63 && label.matches(Regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$"))
        }
    }

    private fun shellQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"

    // ------------------------------------------------------------------
    // Root 脚本模板（自 MainActivity 原样迁移）
    // ------------------------------------------------------------------

    private fun firewallScript(protocol: String, port: Int, enabled: Boolean): String {
        val comment = "nexus_agent_${protocol}_${port}"
        val rule = "-p $protocol --dport $port -m comment --comment $comment -j REJECT"
        val desiredState = if (enabled) "true" else "false"
        val command = """
            enabled=$desiredState
            apply_rule() {
              firewall_bin="${'$'}1"
              shift
              if [ "${'$'}enabled" = "true" ]; then
                if ! "${'$'}firewall_bin" -w -C OUTPUT "${'$'}@" >/dev/null 2>&1; then
                  "${'$'}firewall_bin" -w -I OUTPUT 1 "${'$'}@" || return 1
                fi
              else
                while "${'$'}firewall_bin" -w -C OUTPUT "${'$'}@" >/dev/null 2>&1; do
                  "${'$'}firewall_bin" -w -D OUTPUT "${'$'}@" || return 1
                done
              fi
            }
            command -v iptables >/dev/null 2>&1 || exit 40
            apply_rule iptables $rule || exit 41
            ipv6_status=unavailable
            if command -v ip6tables >/dev/null 2>&1; then
              if apply_rule ip6tables $rule; then
                ipv6_status=applied
              else
                ipv6_status=failed
              fi
            fi
            echo "ipv4=applied ipv6=${'$'}ipv6_status protocol=$protocol port=$port enabled=$desiredState"
        """.trimIndent()
        return command
    }

    private fun hostsScript(domain: String, enabled: Boolean): String {
        val desiredState = if (enabled) "true" else "false"
        val command = """
            hosts=/system/etc/hosts
            domain='$domain'
            enabled=$desiredState
            marker="# nexus-agent:${'$'}domain"
            [ -f "${'$'}hosts" ] && [ ! -L "${'$'}hosts" ] || exit 50
            if [ "${'$'}enabled" = "true" ] && awk -v domain="${'$'}domain" -v marker="${'$'}marker" '
              /^[[:space:]]*#/ { next }
              {
                for (i = 2; i <= NF; i++) {
                  if (${'$'}i == domain && index(${'$'}0, marker) == 0) found = 1
                }
              }
              END { exit !found }
            ' "${'$'}hosts"; then
              exit 51
            fi
            temp="${'$'}hosts.nexus-agent.${'$'}${'$'}.tmp"
            backup="${'$'}hosts.nexus-agent.${'$'}${'$'}.backup"
            cp -p -- "${'$'}hosts" "${'$'}backup" || exit 52
            cp -p -- "${'$'}hosts" "${'$'}temp" || {
              rm -f -- "${'$'}backup"
              exit 53
            }
            awk -v marker="${'$'}marker" 'index(${'$'}0, marker) == 0 { print }' \
              "${'$'}hosts" > "${'$'}temp" || {
                rm -f -- "${'$'}temp" "${'$'}backup"
                exit 54
              }
            if [ "${'$'}enabled" = "true" ]; then
              printf '0.0.0.0 %s # nexus-agent:%s\n:: %s # nexus-agent:%s\n' \
                "${'$'}domain" "${'$'}domain" "${'$'}domain" "${'$'}domain" >> "${'$'}temp" || {
                  rm -f -- "${'$'}temp" "${'$'}backup"
                  exit 55
                }
            fi
            cat "${'$'}temp" > "${'$'}hosts" || {
              cat "${'$'}backup" > "${'$'}hosts"
              rm -f -- "${'$'}temp" "${'$'}backup"
              exit 56
            }
            restorecon "${'$'}hosts" >/dev/null 2>&1 || true
            rm -f -- "${'$'}temp" "${'$'}backup"
            echo "hosts=/system/etc/hosts domain=${'$'}domain enabled=${'$'}enabled"
        """.trimIndent()
        return command
    }

    private fun clearCacheScript(appPackage: String): String {
        val escapedPackage = appPackage.replace("'", "'\\''")
        val command = """
            data_root=${'$'}(readlink -f -- '/data/user/0') || exit 20
            app_root=${'$'}(readlink -f -- '/data/user/0/$escapedPackage') || exit 21
            expected_root="${'$'}data_root/$escapedPackage"
            [ "${'$'}app_root" = "${'$'}expected_root" ] || exit 22
            [ -d "${'$'}app_root" ] || exit 23
            for cache_name in cache code_cache; do
              cache_path="${'$'}app_root/${'$'}cache_name"
              if [ -d "${'$'}cache_path" ] && [ ! -L "${'$'}cache_path" ]; then
                find "${'$'}cache_path" -mindepth 1 -maxdepth 50 -delete || exit 24
              fi
            done
            echo 'cache cleared; app data preserved'
        """.trimIndent()
        return command
    }

    private fun killScript(pid: Int, processName: String): String {
        val escapedName = processName.replace("'", "'\\''")
        val command = """
            cmdline="/proc/$pid/cmdline"
            [ -r "${'$'}cmdline" ] || exit 31
            actual=${'$'}(tr '\000' '\n' < "${'$'}cmdline" | head -n 1)
            [ "${'$'}actual" = '$escapedName' ] || exit 32
            kill -TERM $pid || exit 33
            echo 'SIGTERM sent after PID and process-name verification'
        """.trimIndent()
        return command
    }

    companion object {
        const val VPN_REQUEST_CODE = 9310
        private const val MAX_FILE_BYTES = 65536
        private const val MAX_LIST_BYTES = 32768
        private const val MAX_LOG_CHARS = 120_000
        private const val MAX_PROCESSES = 500
        private const val LONG_TIMEOUT_MS = 120_000L
        private const val VPN_SETTLE_MS = 600L
        private val FILE_ROOTS = listOf("/sdcard", "/storage/emulated/0", "/data/local/tmp")
        private val RESTARTABLE_ANDROID_SERVICES = setOf("logd", "statsd")
        private val ANIMATION_KEYS = listOf(
            "window_animation_scale",
            "transition_animation_scale",
            "animator_duration_scale",
        )
        private val PROTECTED_PROCESSES = setOf(
            "init",
            "system_server",
            "zygote",
            "zygote64",
            "surfaceflinger",
            "servicemanager",
            "hwservicemanager",
        )

        private val METHODS = setOf(
            "rootStatus", "privilegeStatus", "requestShizukuPermission", "openShizuku",
            "grantPermissionsViaPrivilege", "openSpecialPermission", "openAppDetails",
            "refreshDns", "setWifi", "setBluetooth", "setAirplaneMode", "setLocationEnabled",
            "setDoNotDisturb", "setFontScale", "setAnimationScale",
            "stopApp", "restartApp", "clearAppCache", "killProcess", "restartService",
            "runningProcesses", "foregroundApps", "recentApps", "logcatTail", "crashLogs",
            "directorySize", "readRootFile", "listRootFiles", "writeRootFile", "deleteRootFile",
            "moveRootFile", "compressRootFiles", "extractRootArchive",
            "setFirewallPortRule", "setHostsBlock",
            "networkFilterStatus", "setNetworkFilterEnabled", "setAppNetworkBlock", "setDomainBlock",
        )
    }
}
