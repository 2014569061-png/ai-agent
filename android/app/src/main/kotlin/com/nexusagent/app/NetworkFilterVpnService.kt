package com.nexusagent.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * 免 Root 网络过滤规则存储（SharedPreferences `nexus_network_filter`）。
 *
 * - domains：被屏蔽的域名（同时屏蔽其所有子域名）。
 * - apps：被断网的应用包名。
 * - enabled：用户是否开启过滤；VPN 被系统收回时自动置为 false。
 */
object NetworkFilterStore {
    private const val PREFS = "nexus_network_filter"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_DOMAINS = "domains"
    private const val KEY_APPS = "apps"
    const val MAX_DOMAINS = 500
    const val MAX_APPS = 100

    val blockedQueries = AtomicLong(0)
    val forwardedQueries = AtomicLong(0)
    val droppedPackets = AtomicLong(0)
    private val recent = ArrayDeque<Map<String, Any?>>()

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun domains(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_DOMAINS, emptySet()).orEmpty().toSet()

    fun apps(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_APPS, emptySet()).orEmpty().toSet()

    /** 返回修改前该项是否已在列表中。 */
    fun setDomain(context: Context, domain: String, blocked: Boolean): Boolean {
        val current = domains(context).toMutableSet()
        val previously = domain in current
        if (blocked) {
            if (!previously && current.size >= MAX_DOMAINS) {
                throw IllegalStateException("屏蔽域名已达上限 $MAX_DOMAINS 条")
            }
            current.add(domain)
        } else {
            current.remove(domain)
        }
        prefs(context).edit().putStringSet(KEY_DOMAINS, current).apply()
        return previously
    }

    fun setApp(context: Context, packageName: String, blocked: Boolean): Boolean {
        val current = apps(context).toMutableSet()
        val previously = packageName in current
        if (blocked) {
            if (!previously && current.size >= MAX_APPS) {
                throw IllegalStateException("断网应用已达上限 $MAX_APPS 个")
            }
            current.add(packageName)
        } else {
            current.remove(packageName)
        }
        prefs(context).edit().putStringSet(KEY_APPS, current).apply()
        return previously
    }

    fun recordBlocked(domain: String, packageName: String?, reason: String) {
        blockedQueries.incrementAndGet()
        synchronized(recent) {
            recent.addFirst(
                mapOf(
                    "domain" to domain,
                    "packageName" to packageName,
                    "reason" to reason,
                    "atMs" to System.currentTimeMillis(),
                )
            )
            while (recent.size > 30) recent.removeLast()
        }
    }

    fun recentBlocked(): List<Map<String, Any?>> = synchronized(recent) { recent.toList() }

    fun matchesDomain(domain: String, blocked: Set<String>): String? {
        var candidate = domain.lowercase().trimEnd('.')
        while (candidate.isNotEmpty()) {
            if (candidate in blocked) return candidate
            val dot = candidate.indexOf('.')
            if (dot < 0) break
            candidate = candidate.substring(dot + 1)
        }
        return null
    }

    /** 期望的工作模式；null 表示没有规则、无需运行 VPN。 */
    fun desiredMode(context: Context): String? {
        val domains = domains(context)
        val apps = apps(context)
        return when {
            domains.isNotEmpty() -> "dns"
            apps.isNotEmpty() -> "app_full"
            else -> null
        }
    }

    fun status(context: Context): Map<String, Any?> = mapOf(
        "enabled" to isEnabled(context),
        "running" to NetworkFilterVpnService.running,
        "mode" to NetworkFilterVpnService.activeMode,
        "desiredMode" to desiredMode(context),
        "vpnPrepared" to (runCatching { VpnService.prepare(context) == null }.getOrDefault(false)),
        "domains" to domains(context).sorted(),
        "apps" to apps(context).sorted(),
        "unresolvedApps" to NetworkFilterVpnService.unresolvedApps.toList().sorted(),
        "perAppDnsSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q),
        "blockedQueries" to blockedQueries.get(),
        "forwardedQueries" to forwardedQueries.get(),
        "droppedPackets" to droppedPackets.get(),
        "recentBlocked" to recentBlocked(),
        "upstreamDns" to NetworkFilterVpnService.upstreamDescription,
        "lastError" to NetworkFilterVpnService.lastError,
        "limitations" to listOf(
            "域名屏蔽基于 DNS：应用自带 DoH/DoT、系统“私人 DNS”设为指定主机名或直接用 IP 连接时可绕过",
            "同时有屏蔽域名和断网应用时，断网应用按 DNS 阻断（需 Android 10+），直接用 IP 连接的流量仍可通过",
            "只有断网应用时，这些应用的全部流量都会被丢弃（完整阻断）",
            "Android 同时只允许一个 VPN；启用后会断开其它 VPN/代理类应用",
            "端口级防火墙需要 Root（iptables），本地 VPN 不做逐包转发",
        ),
    )
}

/**
 * 本地 VPN 过滤器（无需 Root）。
 *
 * 两种工作模式：
 * 1. `dns`：有屏蔽域名时，VPN 只接管一个虚拟 DNS 地址（10.111.222.1）。系统 DNS 查询
 *    进入本服务：命中屏蔽域名、或来自断网应用（Android 10+ 可识别来源应用）则返回
 *    NXDOMAIN，其余转发给底层网络的 DNS。其它流量不经过 VPN，不影响网速。
 * 2. `app_full`：只有断网应用时，只把这些应用纳入 VPN 并路由全部流量，然后丢弃，
 *    实现完整断网；其它应用完全不受影响。
 *
 * 本应用自身始终排除在 VPN 之外，避免上游 DNS 查询回环。
 */
class NetworkFilterVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var forwarders: ExecutorService? = null
    private val writeLock = Any()

    @Volatile private var blockedDomains: Set<String> = emptySet()
    @Volatile private var blockedUids: Set<Int> = emptySet()
    @Volatile private var uidPackages: Map<Int, String> = emptyMap()
    @Volatile private var upstream: List<InetAddress> = emptyList()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopFilter()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_RELOAD, ACTION_START -> startFilter()
            else -> {
                // 系统“始终开启的 VPN”或重启后拉起：沿用已保存规则。
                NetworkFilterStore.setEnabled(this, true)
                startFilter()
            }
        }
        return if (running) START_STICKY else START_NOT_STICKY
    }

    override fun onRevoke() {
        // 用户在系统里断开或其它 VPN 接管：视为关闭过滤，不自动抢回。
        NetworkFilterStore.setEnabled(this, false)
        lastError = "VPN 权限已被系统收回（用户断开或其它 VPN 接管）"
        stopFilter()
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopFilter()
        super.onDestroy()
    }

    private fun startFilter() {
        val mode = NetworkFilterStore.desiredMode(this)
        if (!NetworkFilterStore.isEnabled(this) || mode == null) {
            stopFilter()
            stopSelf()
            return
        }
        stopFilter()
        try {
            loadRules()
            val builder = Builder()
                .setSession("NEXUS 网络过滤")
                .setMtu(MTU)
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ).let { builder.setConfigureIntent(it) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setBlocking(true)
                builder.setMetered(false)
            }
            if (mode == "dns") {
                builder.addAddress(VPN_ADDRESS, 32)
                builder.addDnsServer(DNS_ADDRESS)
                builder.addRoute(DNS_ADDRESS, 32)
                builder.addDisallowedApplication(packageName)
            } else {
                val allowed = uidPackages.values.toSet()
                if (allowed.isEmpty()) {
                    throw IllegalStateException("断网应用都无法解析（可能已卸载），未启动 VPN")
                }
                builder.addAddress(VPN_ADDRESS, 32)
                builder.addAddress(VPN_ADDRESS6, 128)
                builder.addRoute("0.0.0.0", 0)
                builder.addRoute("::", 0)
                builder.addDnsServer(DNS_ADDRESS)
                allowed.forEach { pkg ->
                    runCatching { builder.addAllowedApplication(pkg) }
                }
            }
            val established = builder.establish()
                ?: throw IllegalStateException("系统拒绝建立 VPN：需要先在弹窗中允许 VPN 连接")
            tun = established
            activeMode = mode
            running = true
            lastError = null
            forwarders = Executors.newFixedThreadPool(4)
            worker = Thread({ packetLoop(established) }, "nexus-network-filter").apply {
                isDaemon = true
                start()
            }
        } catch (e: Exception) {
            lastError = e.message ?: "VPN 启动失败"
            stopFilter()
        }
    }

    private fun stopFilter() {
        running = false
        activeMode = null
        runCatching { tun?.close() }
        tun = null
        worker?.interrupt()
        worker = null
        forwarders?.shutdownNow()
        forwarders = null
    }

    private fun loadRules() {
        blockedDomains = NetworkFilterStore.domains(this)
        val uids = mutableMapOf<Int, String>()
        val unresolved = mutableSetOf<String>()
        NetworkFilterStore.apps(this).forEach { pkg ->
            val uid = runCatching { packageManager.getApplicationInfo(pkg, 0).uid }.getOrNull()
            if (uid == null) unresolved.add(pkg) else uids[uid] = pkg
        }
        uidPackages = uids
        blockedUids = uids.keys
        unresolvedApps = unresolved
        upstream = resolveUpstreamDns()
        upstreamDescription = upstream.map { it.hostAddress.orEmpty() }
    }

    /** 本应用不在 VPN 内，activeNetwork 即底层网络。 */
    private fun resolveUpstreamDns(): List<InetAddress> {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val servers = runCatching {
            cm.getLinkProperties(cm.activeNetwork)?.dnsServers.orEmpty()
        }.getOrDefault(emptyList())
            .filter { it.hostAddress != DNS_ADDRESS }
        val fallback = FALLBACK_DNS.mapNotNull { runCatching { InetAddress.getByName(it) }.getOrNull() }
        return (servers + fallback).distinct().take(4)
    }

    private fun packetLoop(fd: ParcelFileDescriptor) {
        val input = FileInputStream(fd.fileDescriptor)
        val output = FileOutputStream(fd.fileDescriptor)
        val buffer = ByteArray(MTU)
        while (running && !Thread.currentThread().isInterrupted) {
            val length = try {
                input.read(buffer)
            } catch (e: IOException) {
                if (!running) break
                // 旧系统为非阻塞 fd，读空时抛 EAGAIN。
                sleepQuietly(20)
                continue
            }
            if (length <= 0) {
                sleepQuietly(20)
                continue
            }
            val packet = buffer.copyOf(length)
            if (activeMode == "app_full") {
                NetworkFilterStore.droppedPackets.incrementAndGet()
                continue
            }
            handleDnsPacket(packet, output)
        }
    }

    private fun handleDnsPacket(packet: ByteArray, output: FileOutputStream) {
        if (packet.size < 28 || (packet[0].toInt() ushr 4) != 4) {
            NetworkFilterStore.droppedPackets.incrementAndGet()
            return
        }
        val ihl = (packet[0].toInt() and 0x0F) * 4
        val protocol = packet[9].toInt() and 0xFF
        if (protocol != OsConstants.IPPROTO_UDP || packet.size < ihl + 8 + 12) {
            // DNS over TCP / DoT 到虚拟地址：丢弃，客户端会回退到 UDP。
            NetworkFilterStore.droppedPackets.incrementAndGet()
            return
        }
        val srcIp = packet.copyOfRange(12, 16)
        val dstIp = packet.copyOfRange(16, 20)
        val srcPort = u16(packet, ihl)
        val dstPort = u16(packet, ihl + 2)
        if (dstPort != 53) {
            NetworkFilterStore.droppedPackets.incrementAndGet()
            return
        }
        val udpLength = u16(packet, ihl + 4)
        val payloadEnd = minOf(packet.size, ihl + udpLength)
        if (payloadEnd <= ihl + 8 + 12) return
        val query = packet.copyOfRange(ihl + 8, payloadEnd)
        val question = parseQuestion(query) ?: run {
            NetworkFilterStore.droppedPackets.incrementAndGet()
            return
        }
        val ownerPackage = ownerPackage(srcIp, srcPort, dstIp)
        val matchedDomain = NetworkFilterStore.matchesDomain(question.name, blockedDomains)
        if (ownerPackage != null || matchedDomain != null) {
            NetworkFilterStore.recordBlocked(
                question.name,
                ownerPackage,
                if (ownerPackage != null) "app_blocked" else "domain:$matchedDomain",
            )
            writeResponse(output, dstIp, srcIp, srcPort, nxdomain(query, question.end))
            return
        }
        val pool = forwarders ?: return
        runCatching {
            pool.execute {
                val answer = forward(query) ?: return@execute
                NetworkFilterStore.forwardedQueries.incrementAndGet()
                writeResponse(output, dstIp, srcIp, srcPort, answer)
            }
        }
    }

    /** Android 10+：识别 DNS 查询来自哪个应用，命中断网应用则返回包名。 */
    private fun ownerPackage(srcIp: ByteArray, srcPort: Int, dstIp: ByteArray): String? {
        if (blockedUids.isEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return runCatching {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val uid = cm.getConnectionOwnerUid(
                OsConstants.IPPROTO_UDP,
                InetSocketAddress(InetAddress.getByAddress(srcIp), srcPort),
                InetSocketAddress(InetAddress.getByAddress(dstIp), 53),
            )
            if (uid in blockedUids) uidPackages[uid] else null
        }.getOrNull()
    }

    private fun forward(query: ByteArray): ByteArray? {
        for (server in upstream) {
            try {
                DatagramSocket().use { socket ->
                    protect(socket)
                    socket.soTimeout = UPSTREAM_TIMEOUT_MS
                    socket.send(DatagramPacket(query, query.size, server, 53))
                    val buffer = ByteArray(4096)
                    val response = DatagramPacket(buffer, buffer.size)
                    socket.receive(response)
                    if (response.length >= 12 &&
                        buffer[0] == query[0] && buffer[1] == query[1]
                    ) {
                        return buffer.copyOf(response.length)
                    }
                }
            } catch (_: Exception) {
                // 换下一个上游。
            }
        }
        return null
    }

    private fun writeResponse(
        output: FileOutputStream,
        sourceIp: ByteArray,
        destinationIp: ByteArray,
        destinationPort: Int,
        payload: ByteArray,
    ) {
        val total = 20 + 8 + payload.size
        if (total > MTU) return
        val packet = ByteArray(total)
        packet[0] = 0x45
        put16(packet, 2, total)
        put16(packet, 4, (System.nanoTime() and 0xFFFF).toInt())
        packet[6] = 0x40 // DF
        packet[8] = 64
        packet[9] = OsConstants.IPPROTO_UDP.toByte()
        System.arraycopy(sourceIp, 0, packet, 12, 4)
        System.arraycopy(destinationIp, 0, packet, 16, 4)
        put16(packet, 10, ipChecksum(packet, 0, 20))
        put16(packet, 20, 53)
        put16(packet, 22, destinationPort)
        put16(packet, 24, 8 + payload.size)
        put16(packet, 26, 0) // IPv4 允许 UDP 校验和为 0
        System.arraycopy(payload, 0, packet, 28, payload.size)
        synchronized(writeLock) {
            runCatching { output.write(packet) }
        }
    }

    private data class Question(val name: String, val end: Int)

    private fun parseQuestion(query: ByteArray): Question? {
        if (query.size < 12) return null
        val flags = u16(query, 2)
        if (flags and 0x8000 != 0) return null // 不是查询
        if (u16(query, 4) < 1) return null
        var offset = 12
        val labels = mutableListOf<String>()
        while (true) {
            if (offset >= query.size) return null
            val len = query[offset].toInt() and 0xFF
            if (len == 0) {
                offset += 1
                break
            }
            if (len and 0xC0 != 0 || offset + 1 + len > query.size || labels.size > 127) return null
            labels.add(String(query, offset + 1, len, Charsets.US_ASCII))
            offset += 1 + len
        }
        if (offset + 4 > query.size) return null
        return Question(labels.joinToString(".").lowercase(), offset + 4)
    }

    private fun nxdomain(query: ByteArray, questionEnd: Int): ByteArray {
        val response = query.copyOf(questionEnd)
        val requestFlags = u16(query, 2)
        val opcode = requestFlags and 0x7800
        val rd = requestFlags and 0x0100
        put16(response, 2, 0x8000 or opcode or rd or 0x0080 or 0x0003)
        put16(response, 4, 1)
        put16(response, 6, 0)
        put16(response, 8, 0)
        put16(response, 10, 0)
        return response
    }

    private fun ipChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0L
        var i = offset
        while (i < offset + length) {
            sum += ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            i += 2
        }
        while (sum shr 16 != 0L) sum = (sum and 0xFFFF) + (sum shr 16)
        return (sum.inv() and 0xFFFF).toInt()
    }

    private fun u16(data: ByteArray, offset: Int): Int =
        ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)

    private fun put16(data: ByteArray, offset: Int, value: Int) {
        data[offset] = (value ushr 8).toByte()
        data[offset + 1] = value.toByte()
    }

    private fun sleepQuietly(ms: Long) {
        try {
            Thread.sleep(ms)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    companion object {
        const val ACTION_START = "com.nexusagent.app.network_filter.START"
        const val ACTION_STOP = "com.nexusagent.app.network_filter.STOP"
        const val ACTION_RELOAD = "com.nexusagent.app.network_filter.RELOAD"
        private const val VPN_ADDRESS = "10.111.222.2"
        private const val VPN_ADDRESS6 = "fd00:6e78:7573::2"
        private const val DNS_ADDRESS = "10.111.222.1"
        private const val MTU = 1500
        private const val UPSTREAM_TIMEOUT_MS = 4000
        private val FALLBACK_DNS = listOf("223.5.5.5", "119.29.29.29", "1.1.1.1")

        @Volatile var running = false
            private set
        @Volatile var activeMode: String? = null
            private set
        @Volatile var lastError: String? = null
        @Volatile var unresolvedApps: Set<String> = emptySet()
            private set
        @Volatile var upstreamDescription: List<String> = emptyList()
            private set

        /** 按当前规则启动/重载/停止；调用前需确认 VPN 已获用户授权。 */
        fun sync(context: Context) {
            val shouldRun = NetworkFilterStore.isEnabled(context) &&
                NetworkFilterStore.desiredMode(context) != null
            val action = when {
                !shouldRun -> ACTION_STOP
                running -> ACTION_RELOAD
                else -> ACTION_START
            }
            if (action == ACTION_STOP && !running) return
            context.startService(
                Intent(context, NetworkFilterVpnService::class.java).setAction(action)
            )
        }
    }
}
