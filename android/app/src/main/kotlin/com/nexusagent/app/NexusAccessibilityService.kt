package com.nexusagent.app

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.ArrayDeque
import java.util.UUID

/**
 * Explicit, short-lived, read-only accessibility observation.
 *
 * Accessibility events are used only as a revision counter. Node text is read
 * synchronously, and only while MainActivity is foreground and the user has
 * explicitly started a conversation-bound session.
 */
class NexusAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        val scopedInfo = serviceInfo
        scopedInfo.packageNames = arrayOf(applicationContext.packageName)
        serviceInfo = scopedInfo
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.packageName?.toString() == applicationContext.packageName &&
            isSessionActive()
        ) {
            // Do not inspect, cache, or log event text/source.
            revision += 1
        }
    }

    override fun onInterrupt() {
        endSession()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        endSession()
        super.onDestroy()
    }

    private fun isSessionActive(): Boolean =
        sessionId != null && System.currentTimeMillis() < expiresAtMs

    private fun observe(expectedOwner: String, expectedSessionId: String): Map<String, Any?> {
        if (!isSessionActive() ||
            ownerId != expectedOwner ||
            sessionId != expectedSessionId
        ) {
            return failure("SESSION_EXPIRED")
        }
        if (packageName != applicationContext.packageName) {
            return failure("OUTSIDE_SCOPE")
        }

        val root = rootInActiveWindow ?: return failure("WINDOW_UNAVAILABLE")
        if (root.packageName?.toString() != applicationContext.packageName) {
            return failure("OUTSIDE_SCOPE")
        }

        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Boolean>>()
        val labels = mutableListOf<Map<String, Any>>()
        var visited = 0
        var totalChars = 0
        var traversalTruncated = false
        queue.add(root to false)

        while (queue.isNotEmpty() && visited < MAX_VISITED_NODES &&
            labels.size < MAX_RETURNED_NODES && totalChars < MAX_TEXT_CHARS
        ) {
            val (node, sensitiveAncestor) = queue.removeFirst()
            visited += 1
            val sensitiveSubtree = sensitiveAncestor || node.isEditable || node.isPassword
            if (node.isVisibleToUser && !sensitiveSubtree) {
                val text = cleanLabel(node.text?.toString())
                val description = cleanLabel(node.contentDescription?.toString())
                val label = (text.ifEmpty { description }).take(MAX_LABEL_CHARS)
                if (label.isNotEmpty()) {
                    val remaining = MAX_TEXT_CHARS - totalChars
                    val clipped = label.take(remaining.coerceAtLeast(0))
                    if (clipped.isNotEmpty()) {
                        labels.add(
                            mapOf(
                                "id" to "n${labels.size + 1}",
                                "label" to clipped,
                                "clickable" to node.isClickable,
                                "scrollable" to node.isScrollable,
                                "checked" to node.isChecked,
                                "selected" to node.isSelected,
                            )
                        )
                        totalChars += clipped.length
                    }
                }
            }

            for (index in 0 until node.childCount) {
                val child = node.getChild(index) ?: continue
                if (visited + queue.size >= MAX_VISITED_NODES) {
                    traversalTruncated = true
                    break
                }
                queue.add(child to sensitiveSubtree)
            }
        }

        return mapOf(
            "ok" to true,
            "sessionId" to expectedSessionId,
            "packageName" to packageName,
            "revision" to revision,
            "visitedNodes" to visited,
            "truncated" to (traversalTruncated || queue.isNotEmpty() ||
                visited >= MAX_VISITED_NODES ||
                labels.size >= MAX_RETURNED_NODES || totalChars >= MAX_TEXT_CHARS),
            "nodes" to labels,
        )
    }

    private fun cleanLabel(value: String?): String =
        value.orEmpty()
            .replace(Regex("[\\p{Cc}\\p{Cf}]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()

    companion object {
        private const val SESSION_TTL_MS = 5 * 60 * 1000L
        private const val MAX_VISITED_NODES = 3000
        private const val MAX_RETURNED_NODES = 120
        private const val MAX_TEXT_CHARS = 12000
        private const val MAX_LABEL_CHARS = 160

        @Volatile
        private var instance: NexusAccessibilityService? = null

        @Volatile
        private var ownerId: String? = null

        @Volatile
        private var sessionId: String? = null

        @Volatile
        private var expiresAtMs: Long = 0

        @Volatile
        private var revision: Long = 0

        fun enabled(context: android.content.Context): Boolean {
            val enabled = android.provider.Settings.Secure.getString(
                context.contentResolver,
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val expected = android.content.ComponentName(
                context,
                NexusAccessibilityService::class.java
            ).flattenToString()
            return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
        }

        fun status(context: android.content.Context): Map<String, Any?> {
            val active = instance?.isSessionActive() == true
            return mapOf(
                "enabled" to enabled(context),
                "connected" to (instance != null),
                "sessionActive" to active,
                "sessionId" to if (active) sessionId else null,
                "expiresAtMs" to if (active) expiresAtMs else null,
            )
        }

        fun beginSession(owner: String): Map<String, Any?> {
            val service = instance ?: return failure("SERVICE_UNAVAILABLE")
            if (owner.isBlank() || owner.length > 120) return failure("INVALID_OWNER")
            if (service.packageName != service.applicationContext.packageName) {
                return failure("OUTSIDE_SCOPE")
            }
            if (service.isSessionActive()) return failure("SESSION_ALREADY_ACTIVE")

            ownerId = owner
            sessionId = UUID.randomUUID().toString()
            expiresAtMs = System.currentTimeMillis() + SESSION_TTL_MS
            revision = 0
            return mapOf(
                "ok" to true,
                "sessionId" to sessionId!!,
                "expiresAtMs" to expiresAtMs,
            )
        }

        fun observe(owner: String, expectedSessionId: String): Map<String, Any?> {
            val service = instance ?: return failure("SERVICE_UNAVAILABLE")
            return service.observe(owner, expectedSessionId)
        }

        fun endSession(owner: String? = null) {
            if (owner == null || ownerId == owner) {
                ownerId = null
                sessionId = null
                expiresAtMs = 0
                revision = 0
            }
        }

        private fun failure(code: String): Map<String, Any?> =
            mapOf("ok" to false, "code" to code)
    }
}
