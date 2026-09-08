package com.nexusagent.app

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
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
        val processBuilder = ProcessBuilder(
            proot.absolutePath,
            "-0",
            "--kill-on-exit",
            "-r",
            rootfs.canonicalPath,
            "-b",
            bind,
            "-w",
            "/workspace",
            "/bin/sh",
            "-lc",
            command,
        )
        processBuilder.directory(appContext.filesDir)
        processBuilder.redirectErrorStream(true)
        processBuilder.environment().apply {
            put(
                "LD_LIBRARY_PATH",
                "${runtimeLibraries.absolutePath}:${nativeDirectory.absolutePath}",
            )
            // The bundled file keeps talloc's SONAME (libtalloc.so.2) while
            // using the .so suffix required by Android's native packaging.
            put("LD_PRELOAD", File(nativeDirectory, "libtalloc.so").absolutePath)
            put("PROOT_LOADER", prootLoader.canonicalPath)
            put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
            put("HOME", "/root")
            put("TMPDIR", "/tmp")
            put("PROOT_TMP_DIR", appContext.cacheDir.absolutePath)
            put("LANG", "C.UTF-8")
            put("TERM", "xterm-256color")
        }

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

    private fun failure(message: String): Map<String, Any> = mapOf(
        "output" to message,
        "exitCode" to 127,
        "timedOut" to false,
    )
}
