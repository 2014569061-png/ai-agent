package com.nexusagent.app

import android.app.assist.AssistStructure
import android.content.Context
import android.text.InputType
import android.view.View
import java.util.ArrayDeque

/** Bounded readable-text extraction; never reads AssistContent extras, screenshots or input values. */
object AssistTextExtractor {
    data class Text(val sourcePackage: String, val sourceLabel: String, val text: String, val truncated: Boolean)
    fun eligible(inputType: Int, className: String?, blocked: Boolean, visibility: Int): Boolean =
        !blocked && visibility == View.VISIBLE && inputType == InputType.TYPE_NULL &&
            className?.contains("EditText", ignoreCase = true) != true

    fun extract(context: Context, structure: AssistStructure?): Text? {
        if (structure == null) return null
        return try {
            val source = structure.activityComponent?.packageName ?: return null
            if (!source.matches(Regex("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+"))) return null
            if (structure.windowNodeCount == 0) return null
            val label = try {
                @Suppress("DEPRECATION")
                context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(source, 0)).toString()
            } catch (_: Exception) { source }
            val safeLabel = label.filter { !Character.isISOControl(it) && Character.getType(it) != Character.FORMAT.toInt() }.take(80).ifBlank { source.take(80) }
            val work = ArrayDeque<Pair<AssistStructure.ViewNode, Int>>()
            for (i in 0 until minOf(structure.windowNodeCount, 4)) work.add(structure.getWindowNodeAt(i).rootViewNode to 0)
            val text = StringBuilder()
            var visited = 0
            var truncated = structure.windowNodeCount > 4
            while (work.isNotEmpty() && visited < 256 && text.length < 8000) {
                val (node, depth) = work.removeFirst()
                visited++
                if (!eligible(node.inputType, node.className, node.isAssistBlocked, node.visibility)) continue
                val value = (node.text ?: node.contentDescription)?.toString()?.replace('\u0000', ' ')?.trim()
                if (!value.isNullOrEmpty()) {
                    if (text.isNotEmpty()) text.append('\n')
                    val remaining = 8000 - text.length
                    text.append(value.take(remaining))
                    if (value.length > remaining) truncated = true
                }
                if (depth < 16) {
                    val children = minOf(node.childCount, 256 - visited - work.size)
                    for (i in 0 until children) work.add(node.getChildAt(i) to depth + 1)
                    if (children < node.childCount) truncated = true
                } else if (node.childCount > 0) truncated = true
            }
            if (work.isNotEmpty()) truncated = true
            if (text.isBlank()) null else Text(source, safeLabel, text.toString(), truncated)
        } catch (_: Exception) { null }
    }
}
