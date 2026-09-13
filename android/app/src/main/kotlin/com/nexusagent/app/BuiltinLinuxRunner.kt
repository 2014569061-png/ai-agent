package com.nexusagent.app

import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process as AndroidProcess
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Executes the bundled ARM64 PRoot process and returns a bounded result map. */
class BuiltinLinuxRunner(context: Context) {
    private val appContext = context.applicationContext
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val processLock = Any()
    private var activeProcess: Process? = null

    fun inspect(): Map<String, Any> {
        val abi = Build.SUPPORTED_ABIS.firstOrNull()
        val required = listOf(
            "libproot.so",
            "libproot_loader.so",
            "libandroid-shmem.so",
            "libtalloc.so",
        )
        val nativeDirectory = File(appContext.applicationInfo.nativeLibraryDir)
        val missing = required.filter { !File(nativeDirectory, it).isFile }
        val available = abi == "arm64-v8a" && missing.isEmpty()
        val detail = when {
            abi != "arm64-v8a" -> "当前设备 ABI 为 ${abi ?: "unknown"}，内置运行时只支持 ARM64。"
            missing.isNotEmpty() -> "APK 缺少原生资源：${missing.joinToString()}。"
            else -> "PRoot ARM64 与 Alpine rootfs 原生桥已就绪。"
        }
        return mapOf(
            "available" to available,
            "detail" to detail,
            "nativeLibraryDir" to nativeDirectory.absolutePath,
        )
    }

    fun run(
        command: String,
        workingDirectory: String,
        rootfsPath: String,
        runtimeLibraryPath: String,
        timeoutMs: Long,
        maxOutputBytes: Int,
        callback: (Map<String, Any>) -> Unit,
    ) {
        executor.execute {
            val result = execute(
                command = command,
                workingDirectory = workingDirectory,
                rootfsPath = rootfsPath,
                runtimeLibraryPath = runtimeLibraryPath,
                timeoutMs = timeoutMs.coerceIn(1L, 24L * 60L * 60L * 1000L),
                maxOutputBytes = maxOutputBytes.coerceIn(4 * 1024, 4 * 1024 * 1024),
            )
            mainHandler.post { callback(result) }
        }
    }

    fun stop() {
        synchronized(processLock) {
            activeProcess?.destroy()
        }
    }

    /**
     * 启动真正脱离 Flutter 调用生命周期的后台进程。普通 run 会使用
     * --kill-on-exit 保证停止语义；daemon 则必须去掉该参数，并把退出状态
     * 写入应用私有文件，App 重启后才能按 owner token 重新认领。
     */
    fun startDetached(
        command: String,
        workingDirectory: String,
        rootfsPath: String,
        runtimeLibraryPath: String,
        timeoutMs: Long,
        ownerToken: String,
        logPath: String,
        completionPath: String,
    ): Map<String, Any> {
        val processBuilder = createProcessBuilder(
            command = command,
            workingDirectory = workingDirectory,
            rootfsPath = rootfsPath,
            runtimeLibraryPath = runtimeLibraryPath,
            detached = true,
            ownerToken = ownerToken,
        ) ?: return failure("[builtin-proot] rootfs 或工作区路径无效。")
        val log = File(logPath)
        val completion = File(completionPath)
        return try {
            log.parentFile?.mkdirs()
            completion.parentFile?.mkdirs()
            if (completion.exists()) completion.delete()
            processBuilder.redirectOutput(ProcessBuilder.Redirect.to(log))
            val process = processBuilder.start()
            executor.execute {
                var timedOut = false
                var exitCode = 127
                try {
                    if (!process.waitFor(
                            timeoutMs.coerceIn(1L, 24L * 60L * 60L * 1000L),
                            TimeUnit.MILLISECONDS,
                        )
                    ) {
                        timedOut = true
                        process.destroy()
                        if (!process.waitFor(500L, TimeUnit.MILLISECONDS)) {
                            process.destroyForcibly()
                        }
                    }
                    if (!timedOut) exitCode = process.exitValue()
                } catch (_: Exception) {
                    timedOut = true
                    process.destroy()
                } finally {
                    writeCompletion(completion, exitCode, timedOut)
                }
            }
            // Android 的 java.lang.Process 在当前编译 API 中没有暴露 pid()。
            // detached 进程会继承唯一 owner token，通过 /proc 环境反查真实 PID，
            // 避免把 Process.toString() 或本地实现细节当作进程身份。
            mapOf("pid" to (findPidByOwner(ownerToken) ?: -1))
        } catch (error: Exception) {
            failure("[builtin-proot] 后台进程启动失败：${error.message ?: error.javaClass.simpleName}")
        }
    }

    fun verifyDetached(pid: Int, ownerToken: String): Boolean {
        if (pid <= 0 || ownerToken.isBlank()) return false
        val proc = File("/proc/$pid")
        if (!proc.isDirectory) return false
        return try {
            val environment = File(proc, "environ").readBytes().toString(Charsets.UTF_8)
            environment.split('\u0000').contains("NEXUS_DAEMON_OWNER=$ownerToken")
        } catch (_: Exception) {
            false
        }
    }

    fun stopDetached(pid: Int, ownerToken: String): Boolean {
        if (!verifyDetached(pid, ownerToken)) return false
        return try {
            AndroidProcess.killProcess(pid)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun findPidByOwner(ownerToken: String): Int? {
        if (ownerToken.isBlank()) return null
        val marker = "NEXUS_DAEMON_OWNER=$ownerToken"
        repeat(20) {
            val pid = File("/proc").listFiles()
                .orEmpty()
                .asSequence()
                .mapNotNull { it.name.toIntOrNull() }
                .firstOrNull { candidate ->
                    try {
                        File("/proc/$candidate/environ")
                            .readBytes()
                            .toString(Charsets.UTF_8)
                            .split('\u0000')
                            .contains(marker)
                    } catch (_: Exception) {
                        false
                    }
                }
            if (pid != null) return pid
            try {
                Thread.sleep(25L)
            } catch (_: InterruptedException) {
                return null
            }
        }
        return null
    }

    private fun execute(
        command: String,
        workingDirectory: String,
        rootfsPath: String,
        runtimeLibraryPath: String,
        timeoutMs: Long,
        maxOutputBytes: Int,
    ): Map<String, Any> {
        val inspection = inspect()
        if (inspection["available"] != true) {
            return failure("[builtin-proot] ${inspection["detail"]}")
        }

        val rootfs = File(rootfsPath)
        val workspace = File(workingDirectory)
        val runtimeLibraries = File(runtimeLibraryPath)
        val rootfsLoader = File(rootfs, "lib/ld-musl-aarch64.so.1")
        val shell = File(rootfs, "bin/sh")
        val talloc = File(runtimeLibraries, "libtalloc.so.2")
        if (!rootfs.isDirectory || !workspace.isDirectory || !runtimeLibraries.isDirectory ||
            !talloc.isFile || !rootfsLoader.isFile || !shell.isFile) {
            return failure("[builtin-proot] rootfs 或工作区路径无效。")
        }

        // archive extraction can lose POSIX execute bits on Android. PRoot's
        // loader and the guest shell must be executable before the first run.
        val nativeDirectory = File(appContext.applicationInfo.nativeLibraryDir)
        val prootLoader = File(nativeDirectory, "libproot_loader.so")
        prootLoader.setReadable(true, false)
        prootLoader.setExecutable(true, false)
        rootfsLoader.setReadable(true, false)
        rootfsLoader.setExecutable(true, false)
        shell.setReadable(true, false)
        shell.setExecutable(true, false)
        File(rootfs, "bin/busybox").setExecutable(true, false)
        File(rootfs, "sbin/apk").setExecutable(true, false)

        val proot = File(nativeDirectory, "libproot.so")
        val bind = "${workspace.canonicalPath}:/workspace"
        val processBuilder = createProcessBuilder(
            command = command,
            workingDirectory = workingDirectory,
            rootfsPath = rootfsPath,
            runtimeLibraryPath = runtimeLibraryPath,
            detached = false,
            ownerToken = null,
        ) ?: return failure("[builtin-proot] rootfs 或工作区路径无效。")

        val process = try {
            processBuilder.start()
        } catch (error: Exception) {
            return failure("[builtin-proot] 无法启动 PRoot：${error.message ?: error.javaClass.simpleName}")
        }
        synchronized(processLock) {
            activeProcess = process
        }

        val output = StringBuilder()
        val reader = Thread {
            process.inputStream.use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    synchronized(output) {
                        if (output.length < maxOutputBytes) {
                            val remaining = maxOutputBytes - output.length
                            output.append(String(buffer, 0, count.coerceAtMost(remaining), Charsets.UTF_8))
                        }
                    }
                }
            }
        }
        reader.start()

        var timedOut = false
        try {
            if (!process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)) {
                timedOut = true
                process.destroy()
                if (!process.waitFor(500L, TimeUnit.MILLISECONDS)) {
                    process.destroyForcibly()
                }
            }
            reader.join(1000L)
            val exitCode = if (timedOut) 124 else process.exitValue()
            return mapOf(
                "output" to synchronized(output) { output.toString() },
                "exitCode" to exitCode,
                "timedOut" to timedOut,
            )
        } catch (error: Exception) {
            return failure("[builtin-proot] 读取进程结果失败：${error.message ?: error.javaClass.simpleName}")
        } finally {
            synchronized(processLock) {
                if (activeProcess === process) activeProcess = null
            }
        }
    }

    private fun createProcessBuilder(
        command: String,
        workingDirectory: String,
        rootfsPath: String,
        runtimeLibraryPath: String,
        detached: Boolean,
        ownerToken: String?,
    ): ProcessBuilder? {
        val inspection = inspect()
        if (inspection["available"] != true) return null
        val rootfs = File(rootfsPath)
        val workspace = File(workingDirectory)
        val runtimeLibraries = File(runtimeLibraryPath)
        val rootfsLoader = File(rootfs, "lib/ld-musl-aarch64.so.1")
        val shell = File(rootfs, "bin/sh")
        val talloc = File(runtimeLibraries, "libtalloc.so.2")
        if (!rootfs.isDirectory || !workspace.isDirectory || !runtimeLibraries.isDirectory ||
            !talloc.isFile || !rootfsLoader.isFile || !shell.isFile
        ) return null

        val nativeDirectory = File(appContext.applicationInfo.nativeLibraryDir)
        val prootLoader = File(nativeDirectory, "libproot_loader.so")
        prootLoader.setReadable(true, false)
        prootLoader.setExecutable(true, false)
        rootfsLoader.setReadable(true, false)
        rootfsLoader.setExecutable(true, false)
        shell.setReadable(true, false)
        shell.setExecutable(true, false)
        File(rootfs, "bin/busybox").setExecutable(true, false)
        File(rootfs, "sbin/apk").setExecutable(true, false)
        val proot = File(nativeDirectory, "libproot.so")
        val bind = "${workspace.canonicalPath}:/workspace"
        val args = mutableListOf(
            proot.absolutePath,
            "-0",
        )
        if (!detached) args += "--kill-on-exit"
        args += listOf(
            "-r",
            rootfs.canonicalPath,
            // -r 不带任何宿主绑定。/dev 缺失会让 rootfs 内的 2>/dev/null 重定向
            // 直接失败；/proc /sys 缺失会破坏依赖它们的工具；DNS 则由
            // syncResolver 写入 rootfs 的 /etc/resolv.conf（Android 宿主没有
            // 可绑定的 resolv.conf，公网 DNS 作为兜底）。
            "-b",
            "/dev",
            "-b",
            "/proc",
            "-b",
            "/sys",
            "-b",
            bind,
            "-w",
            "/workspace",
            "/bin/sh",
            "-lc",
            command,
        )
        syncResolver(rootfs.canonicalPath)
        return ProcessBuilder(args).apply {
            directory(appContext.filesDir)
            redirectErrorStream(true)
            environment().apply {
                put(
                    "LD_LIBRARY_PATH",
                    "${runtimeLibraries.absolutePath}:${nativeDirectory.absolutePath}",
                )
                put("LD_PRELOAD", File(nativeDirectory, "libtalloc.so").absolutePath)
                put("PROOT_LOADER", prootLoader.canonicalPath)
                put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
                put("HOME", "/root")
                put("TMPDIR", "/tmp")
                put("PROOT_TMP_DIR", appContext.cacheDir.absolutePath)
                put("LANG", "C.UTF-8")
                put("TERM", "dumb")
                if (ownerToken != null) put("NEXUS_DAEMON_OWNER", ownerToken)
            }
        }
    }

    /** 把当前网络的 DNS 写入 rootfs 的 resolv.conf；Android 没有宿主 resolv.conf 可绑。 */
    private fun syncResolver(rootfsPath: String) {
        try {
            val servers = try {
                val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE)
                    as? ConnectivityManager
                cm?.getLinkProperties(cm.activeNetwork)?.dnsServers
                    ?.mapNotNull { it.hostAddress }
                    .orEmpty()
            } catch (_: Exception) {
                emptyList()
            }
            val list = servers.ifEmpty {
                listOf("223.5.5.5", "119.29.29.29", "8.8.8.8")
            }
            val conf = File(File(rootfsPath), "etc/resolv.conf")
            conf.parentFile?.mkdirs()
            conf.writeText(list.joinToString("\n") { "nameserver $it" } + "\n")
        } catch (_: Exception) {
            // DNS 同步失败不阻断命令执行；rootfs 内已有的 resolv.conf 仍会被使用。
        }
    }

    private fun writeCompletion(file: File, exitCode: Int, timedOut: Boolean) {
        try {
            val temp = File(file.parentFile, "${file.name}.part")
            temp.writeText(
                "{\"exitCode\":$exitCode,\"timedOut\":$timedOut}",
                Charsets.UTF_8,
            )
            if (file.exists()) file.delete()
            temp.renameTo(file)
        } catch (_: Exception) {
            // 完成文件只是认领协议的补充，日志与 /proc 仍可用于安全降级。
        }
    }

    private fun failure(message: String): Map<String, Any> = mapOf(
        "output" to message,
        "exitCode" to 127,
        "timedOut" to false,
    )
}
