package com.nexusagent.app

import android.content.Context
import android.os.ParcelFileDescriptor
import androidx.annotation.Keep
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.system.exitProcess

/**
 * Shizuku UserService 实现，运行在 Shizuku 拉起的独立进程里（uid 2000 或 0）。
 *
 * 只负责把应用侧 [PrivilegeManager] 传来的命令交给 `sh -c` 执行并转发三路流；
 * 命令本身始终由应用内固定模板生成，模型不能直接拼接命令。
 */
@Keep
class PrivilegedShellService() : IPrivilegedShell.Stub() {
    private val processes = ConcurrentHashMap<Int, Process>()
    private val nextHandle = AtomicInteger(1)

    @Keep
    @Suppress("UNUSED_PARAMETER")
    constructor(context: Context) : this()

    override fun destroy() {
        processes.values.forEach { runCatching { it.destroyForcibly() } }
        processes.clear()
        exitProcess(0)
    }

    override fun uid(): Int = android.os.Process.myUid()

    override fun start(
        command: String,
        stdin: ParcelFileDescriptor?,
        stdout: ParcelFileDescriptor?,
        stderr: ParcelFileDescriptor?,
    ): Int {
        val process = ProcessBuilder("sh", "-c", command).start()
        val handle = nextHandle.getAndIncrement()
        processes[handle] = process
        pump(process.inputStream, stdout)
        pump(process.errorStream, stderr)
        if (stdin != null) {
            Thread {
                runCatching {
                    ParcelFileDescriptor.AutoCloseInputStream(stdin).use { input ->
                        process.outputStream.use { output -> input.copyTo(output, 64 * 1024) }
                    }
                }
            }.apply { isDaemon = true }.start()
        } else {
            runCatching { process.outputStream.close() }
        }
        return handle
    }

    override fun waitFor(handle: Int, timeoutMs: Long): Int {
        val process = processes[handle] ?: return EXIT_UNKNOWN_HANDLE
        val finished = process.waitFor(timeoutMs.coerceAtLeast(1), TimeUnit.MILLISECONDS)
        if (!finished) return EXIT_TIMEOUT
        processes.remove(handle)
        return process.exitValue()
    }

    override fun kill(handle: Int) {
        processes.remove(handle)?.let { runCatching { it.destroyForcibly() } }
    }

    private fun pump(input: InputStream, target: ParcelFileDescriptor?) {
        Thread {
            runCatching {
                if (target == null) {
                    input.use { stream ->
                        val sink = ByteArray(8 * 1024)
                        while (stream.read(sink) >= 0) { /* drain */ }
                    }
                } else {
                    ParcelFileDescriptor.AutoCloseOutputStream(target).use { output ->
                        input.use { it.copyTo(output, 64 * 1024) }
                    }
                }
            }
        }.apply { isDaemon = true }.start()
    }

    companion object {
        const val EXIT_TIMEOUT = -1001
        const val EXIT_UNKNOWN_HANDLE = -1002
    }
}
