package com.nexusagent.app

import android.content.Context
import android.os.SystemClock
import android.os.Handler
import android.os.Looper

/** Process-local, single-slot transfer. No preferences, files, URLs or logs contain text. */
object AssistantContextHandoff {
    data class Payload(val id: String, val sourcePackage: String, val sourceLabel: String,
        val text: String, val capturedAtMillis: Long, val capturedElapsed: Long, val truncated: Boolean) {
        fun remaining() = 120000L - (SystemClock.elapsedRealtime() - capturedElapsed)
    }
    private var pending: Payload? = null
    private var listenerOwner: Any? = null
    private var changed: (() -> Unit)? = null
    private val expiry = Handler(Looper.getMainLooper())

    fun listen(owner: Any, callback: () -> Unit) { listenerOwner = owner; changed = callback }
    fun detach(owner: Any) { if (listenerOwner === owner) { listenerOwner = null; changed = null } }
    fun stage(payload: Payload): Boolean {
        if (pending?.remaining()?.let { it <= 0 } == true) pending = null
        if (pending != null || payload.remaining() <= 0) return false
        pending = payload
        expiry.removeCallbacksAndMessages(null)
        expiry.postDelayed({ if (pending?.id == payload.id) clear() }, payload.remaining())
        try { changed?.invoke() } catch (_: Exception) { /* Cold-start peek retains ownership. */ }
        return true
    }
    fun peek(context: Context): Map<String, Any>? {
        val value = pending ?: return null
        if (value.remaining() <= 0 || AssistantRoleBridge.locked(context) ||
            AssistantRoleBridge.status(context)["connected"] != true) { clear(); return null }
        return mapOf("version" to 1, "id" to value.id, "sourcePackage" to value.sourcePackage,
            "sourceLabel" to value.sourceLabel, "text" to value.text,
            "capturedAtMillis" to value.capturedAtMillis, "remainingMs" to value.remaining(),
            "truncated" to value.truncated)
    }
    fun acknowledge(id: String): Boolean {
        if (pending?.id != id) return false
        clear()
        return true
    }
    fun clear() { pending = null; expiry.removeCallbacksAndMessages(null) }
}
