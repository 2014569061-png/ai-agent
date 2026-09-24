package com.nexusagent.app

import android.Manifest
import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.Settings
import androidx.core.content.ContextCompat
import rikka.shizuku.Shizuku
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** 实际执行命令的通道。 */
enum class PrivilegeBackend(val id: String, val label: String) {
    ROOT("root", "Root"),
    SHIZUKU("shizuku", "Shizuku"),
    APP("app", "应用自身权限"),
}

/** 命令需要的最低权限级别。 */
enum class PrivilegeRequirement(val id: String) {
    /** 需要 uid 0：Root，或以 Root 模式运行的 Shizuku。 */
    ROOT_UID("root_uid"),

    /** shell 级（uid 2000）即可：Root 或 Shizuku（ADB 模式也行）。 */
    SHELL("shell"),

    /** 共享存储文件：已获“所有文件访问”时以应用自身身份执行，否则 Root / Shizuku。 */
    STORAGE("storage"),
}

class PrivilegeUnavailableException(
    val requirement: PrivilegeRequirement,
    message: String,
) : Exception(message) {
    val code: String
        get() = PrivilegeManager.unavailableCode(requirement)
}

class PrivilegeTimeoutException(message: String) : Exception(message)

/** 统一的特权进程抽象：Root/应用自身是本地 Process，Shizuku 是远程进程加管道。 */
interface PrivilegedProcess {
    val backend: PrivilegeBackend
    val inputStream: InputStream
    val errorStream: InputStream
    val outputStream: OutputStream
    fun waitFor(timeoutMs: Long): Boolean
    fun exitValue(): Int
    fun destroy()
}

data class ShellOutcome(
    val backend: PrivilegeBackend,
    val exitCode: Int,
    val stdoutBytes: ByteArray,
    val stderr: String,
    val stdoutTruncated: Boolean,
) {
    val stdout: String get() = stdoutBytes.toString(Charsets.UTF_8)
}

private class LocalPrivilegedProcess(
    override val backend: PrivilegeBackend,
    private val process: Process,
) : PrivilegedProcess {
    override val inputStream: InputStream get() = process.inputStream
    override val errorStream: InputStream get() = process.errorStream
    override val outputStream: OutputStream get() = process.outputStream
    override fun waitFor(timeoutMs: Long): Boolean =
        process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
    override fun exitValue(): Int = process.exitValue()
    override fun destroy() {
        runCatching { process.destroyForcibly() }
    }
}

private class ShizukuPrivilegedProcess(
    private val service: IPrivilegedShell,
    private val handle: Int,
    override val inputStream: InputStream,
    override val errorStream: InputStream,
    override val outputStream: OutputStream,
) : PrivilegedProcess {
    override val backend: PrivilegeBackend = PrivilegeBackend.SHIZUKU

    @Volatile
    private var exit: Int? = null

    override fun waitFor(timeoutMs: Long): Boolean {
        if (exit != null) return true
        val code = try {
            service.waitFor(handle, timeoutMs)
        } catch (e: Exception) {
            throw IOException("Shizuku 服务连接中断：${e.message}")
        }
        if (code == PrivilegedShellService.EXIT_TIMEOUT) return false
        if (code == PrivilegedShellService.EXIT_UNKNOWN_HANDLE) {
            throw IOException("Shizuku 服务已重启，进程状态丢失")
        }
        exit = code
        return true
    }

    override fun exitValue(): Int = exit ?: throw IllegalThreadStateException("进程尚未结束")

    override fun destroy() {
        runCatching { service.kill(handle) }
        runCatching { outputStream.close() }
    }
}

/** Root 输出不需要写入的 stdin 占位。 */
private object ClosedOutputStream : OutputStream() {
    override fun write(b: Int) {
        throw IOException("该进程不接受标准输入")
    }
}

/**
 * 免 Root 能力的提权层：Root → Shizuku → 应用自身权限。
 *
 * - [start]/[run] 只执行应用内固定模板生成的命令；调用方负责参数校验和转义。
 * - Root 探测结果带缓存，避免每次操作都弹 su 授权框。
 * - Shizuku 通过 UserService 执行，服务进程随应用退出（daemon=false）。
 * - 所有阻塞调用都不能在主线程执行（绑定 Shizuku 服务需要主线程回调）。
 */
object PrivilegeManager {
    const val SHIZUKU_PERMISSION_REQUEST = 9301
    const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
    const val SHIZUKU_DOWNLOAD_URL = "https://shizuku.rikka.app/download/"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val bindLock = Any()
    private val permissionCallbacks = mutableListOf<(Boolean) -> Unit>()

    @Volatile private var appContext: Context? = null
    @Volatile private var initialized = false
    @Volatile private var rootGranted: Boolean? = null
    @Volatile private var rootCheckedAt = 0L
    @Volatile private var rootProbeOutput = ""
    @Volatile private var shellService: IPrivilegedShell? = null
    @Volatile private var bindLatch: CountDownLatch? = null
    @Volatile private var serviceArgs: Shizuku.UserServiceArgs? = null

    private val permissionListener = Shizuku.OnRequestPermissionResultListener { code, grant ->
        if (code != SHIZUKU_PERMISSION_REQUEST) return@OnRequestPermissionResultListener
        val granted = grant == PackageManager.PERMISSION_GRANTED
        val callbacks = synchronized(permissionCallbacks) {
            permissionCallbacks.toList().also { permissionCallbacks.clear() }
        }
        callbacks.forEach { runCatching { it(granted) } }
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        shellService = null
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            if (binder != null && binder.pingBinder()) {
                shellService = IPrivilegedShell.Stub.asInterface(binder)
            }
            bindLatch?.countDown()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            shellService = null
        }
    }

    fun init(context: Context) {
        appContext = context.applicationContext
        if (initialized) return
        initialized = true
        runCatching {
            Shizuku.addRequestPermissionResultListener(permissionListener)
            Shizuku.addBinderDeadListener(binderDeadListener)
        }
    }

    private fun context(): Context =
        appContext ?: throw IllegalStateException("PrivilegeManager 未初始化")

    // ------------------------------------------------------------------
    // 状态探测
    // ------------------------------------------------------------------

    /** 阻塞探测 Root（缓存：已授权 10 分钟、未授权 60 秒）。不能在主线程调用。 */
    fun rootAvailable(forceProbe: Boolean = false): Boolean {
        val cached = rootGranted
        val age = System.currentTimeMillis() - rootCheckedAt
        if (!forceProbe && cached != null &&
            age < if (cached) ROOT_CACHE_GRANTED_MS else ROOT_CACHE_DENIED_MS
        ) {
            return cached
        }
        var granted = false
        var output = ""
        try {
            val process = ProcessBuilder("su", "-c", "id").redirectErrorStream(true).start()
            val reader = Thread {
                output = runCatching {
                    process.inputStream.bufferedReader().readText().trim().take(160)
                }.getOrDefault("")
            }.apply { start() }
            val finished = process.waitFor(ROOT_PROBE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            if (!finished) process.destroyForcibly()
            reader.join(500)
            granted = finished && process.exitValue() == 0 && output.contains("uid=0")
        } catch (_: Exception) {
            granted = false
        }
        rootGranted = granted
        rootProbeOutput = output
        rootCheckedAt = System.currentTimeMillis()
        return granted
    }

    /** 只读缓存，不触发 su（给主线程用）。 */
    fun cachedRootAvailable(): Boolean? = rootGranted

    fun invalidateRoot() {
        rootGranted = null
        rootCheckedAt = 0L
    }

    fun shizukuInstalled(): Boolean = runCatching {
        context().packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0)
        true
    }.getOrDefault(false)

    fun shizukuRunning(): Boolean = runCatching { Shizuku.pingBinder() }.getOrDefault(false)

    private fun shizukuPreV11(): Boolean = runCatching { Shizuku.isPreV11() }.getOrDefault(false)

    fun shizukuPermissionGranted(): Boolean =
        shizukuRunning() && !shizukuPreV11() && runCatching {
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        }.getOrDefault(false)

    fun shizukuUid(): Int? =
        if (shizukuRunning()) runCatching { Shizuku.getUid() }.getOrNull() else null

    fun shizukuReady(): Boolean = shizukuPermissionGranted()

    fun shizukuState(): Map<String, Any?> {
        val running = shizukuRunning()
        val preV11 = running && shizukuPreV11()
        val granted = running && !preV11 && shizukuPermissionGranted()
        val uid = if (running) shizukuUid() else null
        val permanentlyDenied = running && !granted && !preV11 && runCatching {
            Shizuku.shouldShowRequestPermissionRationale()
        }.getOrDefault(false)
        return mapOf(
            "installed" to shizukuInstalled(),
            "running" to running,
            "permissionGranted" to granted,
            "permanentlyDenied" to permanentlyDenied,
            "preV11" to preV11,
            "uid" to uid,
            "mode" to when (uid) {
                null -> null
                0 -> "root"
                2000 -> "adb"
                else -> "other"
            },
            "version" to if (running) runCatching { Shizuku.getVersion() }.getOrNull() else null,
            "serviceConnected" to (shellService?.asBinder()?.pingBinder() == true),
        )
    }

    fun rootState(probe: Boolean): Map<String, Any?> {
        val granted = if (probe) rootAvailable() else (rootGranted ?: false)
        val suPresent = listOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/debug_ramdisk/su",
        ).any { java.io.File(it).exists() } ||
            java.io.File("/data/adb/magisk").exists() || java.io.File("/data/adb/ksu").exists()
        return mapOf(
            "rootGranted" to granted,
            "probed" to (probe || rootGranted != null),
            "suPresent" to suPresent,
            "uidOutput" to rootProbeOutput,
            "manager" to when {
                java.io.File("/data/adb/magisk").exists() -> "magisk"
                java.io.File("/data/adb/ksu").exists() -> "kernelsu"
                java.io.File("/data/adb/ap").exists() -> "apatch"
                else -> "unknown"
            },
        )
    }

    // ------------------------------------------------------------------
    // 特殊权限
    // ------------------------------------------------------------------

    fun allFilesAccess(): Boolean {
        val ctx = context()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            granted(ctx, Manifest.permission.READ_EXTERNAL_STORAGE) &&
                granted(ctx, Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }
    }

    fun usageAccess(): Boolean {
        val ctx = context()
        val appOps = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                ctx.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                ctx.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun notificationPolicyAccess(): Boolean {
        val manager = context().getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.isNotificationPolicyAccessGranted
    }

    fun writeSettings(): Boolean = Settings.System.canWrite(context())

    fun writeSecureSettings(): Boolean =
        granted(context(), "android.permission.WRITE_SECURE_SETTINGS")

    fun readLogs(): Boolean = granted(context(), "android.permission.READ_LOGS")

    fun vpnPrepared(): Boolean = runCatching { VpnService.prepare(context()) == null }
        .getOrDefault(false)

    fun installPackagesAllowed(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            context().packageManager.canRequestPackageInstalls()

    fun bluetoothConnect(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            granted(context(), Manifest.permission.BLUETOOTH_CONNECT)

    fun permissionState(): Map<String, Boolean> = mapOf(
        "allFilesAccess" to allFilesAccess(),
        "usageAccess" to usageAccess(),
        "notificationPolicy" to notificationPolicyAccess(),
        "writeSettings" to writeSettings(),
        "writeSecureSettings" to writeSecureSettings(),
        "readLogs" to readLogs(),
        "vpnPrepared" to vpnPrepared(),
        "installPackages" to installPackagesAllowed(),
        "bluetoothConnect" to bluetoothConnect(),
    )

    private fun granted(ctx: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(ctx, permission) == PackageManager.PERMISSION_GRANTED

    /**
     * 通过 Root/Shizuku 一次性给自己授予免 Root 路径需要的特殊权限。
     * 命令只含本应用包名与固定权限名；每一项独立返回结果。
     */
    fun grantSelfPermissions(): List<Map<String, Any?>> {
        val pkg = context().packageName
        val steps = mutableListOf(
            "writeSecureSettings" to "pm grant $pkg android.permission.WRITE_SECURE_SETTINGS",
            "readLogs" to "pm grant $pkg android.permission.READ_LOGS",
            "usageAccess" to "appops set $pkg GET_USAGE_STATS allow",
            "writeSettings" to "appops set $pkg WRITE_SETTINGS allow",
            "notificationPolicy" to "cmd notification allow_dnd $pkg",
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            steps.add("allFilesAccess" to "appops set $pkg MANAGE_EXTERNAL_STORAGE allow")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            steps.add("installPackages" to "appops set $pkg REQUEST_INSTALL_PACKAGES allow")
        }
        return steps.map { (key, command) ->
            try {
                val outcome = run(PrivilegeRequirement.SHELL, command, timeoutMs = 8000)
                mapOf(
                    "permission" to key,
                    "command" to command,
                    "granted" to (outcome.exitCode == 0),
                    "executedVia" to outcome.backend.id,
                    "output" to (outcome.stdout + outcome.stderr).trim().take(300),
                )
            } catch (e: Exception) {
                mapOf(
                    "permission" to key,
                    "command" to command,
                    "granted" to false,
                    "error" to (e.message ?: "授权失败"),
                )
            }
        }
    }

    // ------------------------------------------------------------------
    // Shizuku 授权与服务绑定
    // ------------------------------------------------------------------

    /** 回调总在主线程执行。 */
    fun requestShizukuPermission(callback: (Boolean, String?) -> Unit) {
        val deliver: (Boolean, String?) -> Unit = { granted, reason ->
            mainHandler.post { callback(granted, reason) }
        }
        if (!shizukuRunning()) {
            deliver(
                false,
                if (shizukuInstalled()) "Shizuku 已安装但未启动，请先在 Shizuku 中通过无线调试或 Root 启动服务"
                else "未检测到 Shizuku，请先安装并启动 Shizuku",
            )
            return
        }
        if (shizukuPreV11()) {
            deliver(false, "Shizuku 版本过旧（低于 v11），请升级")
            return
        }
        if (shizukuPermissionGranted()) {
            deliver(true, null)
            return
        }
        synchronized(permissionCallbacks) {
            permissionCallbacks.add { granted ->
                deliver(granted, if (granted) null else "用户拒绝了 Shizuku 授权")
            }
        }
        mainHandler.post {
            runCatching { Shizuku.requestPermission(SHIZUKU_PERMISSION_REQUEST) }
                .onFailure { error ->
                    val callbacks = synchronized(permissionCallbacks) {
                        permissionCallbacks.toList().also { permissionCallbacks.clear() }
                    }
                    callbacks.forEach { it(false) }
                    deliver(false, error.message)
                }
        }
    }

    private fun userServiceArgs(ctx: Context): Shizuku.UserServiceArgs {
        serviceArgs?.let { return it }
        val debuggable = (ctx.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val updated = runCatching {
            ctx.packageManager.getPackageInfo(ctx.packageName, 0).lastUpdateTime
        }.getOrDefault(0L)
        val version = ((updated / 1000L) % Int.MAX_VALUE).toInt() + SERVICE_PROTOCOL_VERSION
        return Shizuku.UserServiceArgs(
            ComponentName(ctx.packageName, PrivilegedShellService::class.java.name)
        )
            .daemon(false)
            .processNameSuffix("privileged_shell")
            .debuggable(debuggable)
            .version(version)
            .also { serviceArgs = it }
    }

    private fun obtainShellService(): IPrivilegedShell {
        shellService?.let { if (it.asBinder().pingBinder()) return it }
        if (!shizukuReady()) throw IOException("Shizuku 未运行或未授权")
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw IllegalStateException("不能在主线程绑定 Shizuku 服务")
        }
        synchronized(bindLock) {
            shellService?.let { if (it.asBinder().pingBinder()) return it }
            val latch = CountDownLatch(1)
            bindLatch = latch
            val ctx = context()
            mainHandler.post {
                runCatching { Shizuku.bindUserService(userServiceArgs(ctx), connection) }
                    .onFailure { latch.countDown() }
            }
            latch.await(SHIZUKU_BIND_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            bindLatch = null
            return shellService ?: throw IOException("Shizuku 服务绑定超时")
        }
    }

    // ------------------------------------------------------------------
    // 执行
    // ------------------------------------------------------------------

    fun isSharedStoragePath(path: String): Boolean {
        val normalized = path.replace(Regex("/+"), "/")
        return normalized == "/sdcard" || normalized.startsWith("/sdcard/") ||
            normalized == "/storage/emulated/0" || normalized.startsWith("/storage/emulated/0/")
    }

    /**
     * 可用通道，按优先级排列。
     * 共享存储优先使用应用自身权限（最小权限）；其余按 Root → Shizuku。
     */
    fun candidates(
        requirement: PrivilegeRequirement,
        paths: List<String> = emptyList(),
        probeRoot: Boolean = true,
    ): List<PrivilegeBackend> {
        val list = mutableListOf<PrivilegeBackend>()
        if (requirement == PrivilegeRequirement.STORAGE && paths.isNotEmpty() &&
            paths.all { isSharedStoragePath(it) } && allFilesAccess()
        ) {
            list.add(PrivilegeBackend.APP)
        }
        val root = if (probeRoot) rootAvailable() else (rootGranted ?: false)
        if (root) list.add(PrivilegeBackend.ROOT)
        if (shizukuReady() &&
            (requirement != PrivilegeRequirement.ROOT_UID || shizukuUid() == 0)
        ) {
            list.add(PrivilegeBackend.SHIZUKU)
        }
        return list
    }

    fun preferredBackend(
        requirement: PrivilegeRequirement,
        paths: List<String> = emptyList(),
    ): PrivilegeBackend? = candidates(requirement, paths).firstOrNull()

    fun unavailableCode(requirement: PrivilegeRequirement): String = when (requirement) {
        PrivilegeRequirement.ROOT_UID -> "ROOT_REQUIRED"
        PrivilegeRequirement.SHELL -> "PRIVILEGE_REQUIRED"
        PrivilegeRequirement.STORAGE -> "STORAGE_PERMISSION_REQUIRED"
    }

    fun unavailableMessage(requirement: PrivilegeRequirement): String = when (requirement) {
        PrivilegeRequirement.ROOT_UID ->
            "该操作需要 uid 0：Root，或以 Root 模式启动的 Shizuku；ADB 模式的 Shizuku 无权执行"
        PrivilegeRequirement.SHELL ->
            "该操作需要 Root 或已授权的 Shizuku；两者都不可用（可在“设备能力”页连接 Shizuku）"
        PrivilegeRequirement.STORAGE ->
            "需要“所有文件访问”权限、Root 或 Shizuku；/data/local/tmp 只能通过 Root/Shizuku 访问"
    }

    fun unavailableDetails(requirement: PrivilegeRequirement): Map<String, Any?> = mapOf(
        "requirement" to requirement.id,
        "rootAvailable" to (rootGranted ?: false),
        "shizukuRunning" to shizukuRunning(),
        "shizukuPermissionGranted" to shizukuPermissionGranted(),
        "shizukuUid" to shizukuUid(),
        "allFilesAccess" to runCatching { allFilesAccess() }.getOrDefault(false),
    )

    /** 启动进程。调用方负责关闭流与等待结束。不能在主线程调用。 */
    fun start(
        requirement: PrivilegeRequirement,
        command: String,
        paths: List<String> = emptyList(),
        acceptsStdin: Boolean = false,
    ): PrivilegedProcess {
        val backends = candidates(requirement, paths)
        if (backends.isEmpty()) {
            throw PrivilegeUnavailableException(requirement, unavailableMessage(requirement))
        }
        var lastError: Exception? = null
        for (backend in backends) {
            try {
                return startWith(backend, command, acceptsStdin)
            } catch (e: Exception) {
                lastError = e
                if (backend == PrivilegeBackend.ROOT) invalidateRoot()
                if (backend == PrivilegeBackend.SHIZUKU) shellService = null
            }
        }
        throw PrivilegeUnavailableException(
            requirement,
            "特权通道启动失败：${lastError?.message ?: "未知错误"}",
        )
    }

    private fun startWith(
        backend: PrivilegeBackend,
        command: String,
        acceptsStdin: Boolean,
    ): PrivilegedProcess = when (backend) {
        PrivilegeBackend.ROOT ->
            LocalPrivilegedProcess(backend, ProcessBuilder("su", "-c", command).start())
        PrivilegeBackend.APP ->
            LocalPrivilegedProcess(backend, ProcessBuilder("sh", "-c", command).start())
        PrivilegeBackend.SHIZUKU -> {
            val service = obtainShellService()
            val stdoutPipe = ParcelFileDescriptor.createPipe()
            val stderrPipe = ParcelFileDescriptor.createPipe()
            val stdinPipe = if (acceptsStdin) ParcelFileDescriptor.createPipe() else null
            try {
                val handle = service.start(command, stdinPipe?.get(0), stdoutPipe[1], stderrPipe[1])
                ShizukuPrivilegedProcess(
                    service = service,
                    handle = handle,
                    inputStream = ParcelFileDescriptor.AutoCloseInputStream(stdoutPipe[0]),
                    errorStream = ParcelFileDescriptor.AutoCloseInputStream(stderrPipe[0]),
                    outputStream = stdinPipe?.let {
                        ParcelFileDescriptor.AutoCloseOutputStream(it[1])
                    } ?: ClosedOutputStream,
                )
            } catch (e: Exception) {
                runCatching { stdoutPipe[0].close() }
                runCatching { stderrPipe[0].close() }
                runCatching { stdinPipe?.get(1)?.close() }
                throw e
            } finally {
                // 远端已持有副本；本地关闭写端/读端，EOF 才能正确传递。
                runCatching { stdoutPipe[1].close() }
                runCatching { stderrPipe[1].close() }
                runCatching { stdinPipe?.get(0)?.close() }
            }
        }
    }

    /**
     * 执行并收集输出。超时抛 [PrivilegeTimeoutException]；无可用通道抛
     * [PrivilegeUnavailableException]。退出码非 0 不抛异常，由调用方判断。
     */
    fun run(
        requirement: PrivilegeRequirement,
        command: String,
        timeoutMs: Long = DEFAULT_TIMEOUT_MS,
        paths: List<String> = emptyList(),
        maxStdoutBytes: Int = DEFAULT_MAX_OUTPUT,
    ): ShellOutcome {
        val process = start(requirement, command, paths)
        runCatching { process.outputStream.close() }
        val stdout = ByteArrayOutputStream()
        var truncated = false
        val stderr = StringBuilder()
        val outThread = Thread {
            runCatching {
                process.inputStream.use { input ->
                    val buffer = ByteArray(16 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        val room = maxStdoutBytes - stdout.size()
                        if (room > 0) stdout.write(buffer, 0, minOf(room, read))
                        if (read > room) truncated = true
                    }
                }
            }
        }.apply { start() }
        val errThread = Thread {
            runCatching {
                process.errorStream.bufferedReader().forEachLine {
                    if (stderr.length < 4000) stderr.appendLine(it)
                }
            }
        }.apply { start() }
        val finished = try {
            process.waitFor(timeoutMs)
        } catch (e: IOException) {
            process.destroy()
            throw e
        }
        if (!finished) {
            process.destroy()
            outThread.join(500)
            errThread.join(500)
            throw PrivilegeTimeoutException(
                "${process.backend.label} 命令超过 ${timeoutMs / 1000} 秒未完成，已终止"
            )
        }
        outThread.join(3000)
        errThread.join(1000)
        val exit = process.exitValue()
        if (process.backend == PrivilegeBackend.ROOT && exit != 0 &&
            (stderr.contains("not allowed", true) || stderr.contains("denied", true) &&
                stderr.contains("su", true))
        ) {
            invalidateRoot()
        }
        return ShellOutcome(
            backend = process.backend,
            exitCode = exit,
            stdoutBytes = stdout.toByteArray(),
            stderr = stderr.toString().trim(),
            stdoutTruncated = truncated,
        )
    }

    private const val ROOT_CACHE_GRANTED_MS = 10 * 60 * 1000L
    private const val ROOT_CACHE_DENIED_MS = 60 * 1000L
    private const val ROOT_PROBE_TIMEOUT_MS = 10_000L
    private const val SHIZUKU_BIND_TIMEOUT_MS = 8_000L
    private const val SERVICE_PROTOCOL_VERSION = 1
    const val DEFAULT_TIMEOUT_MS = 8_000L
    const val DEFAULT_MAX_OUTPUT = 256 * 1024
}
