package com.nexusagent.app

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.app.assist.AssistStructure
import android.app.assist.AssistContent
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.util.UUID

class NexusVoiceInteractionSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession = NexusAssistantSession(this)
}

/** A real system session surface; the existing Flutter chat owns all work. */
private class NexusAssistantSession(private val appContext: Context) : VoiceInteractionSession(appContext) {
    private var message: TextView? = null
    private var open: Button? = null
    private var read: Button? = null
    private var use: Button? = null
    private var snapshot: AssistantContextHandoff.Payload? = null
    private var requested = false
    private var awaiting = false
    private var closed = false
    private var capturedElapsed = 0L
    private var capturedMillis = 0L
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreateContentView(): View {
        val padding = (24 * appContext.resources.displayMetrics.density).toInt()
        return LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
            setBackgroundColor(Color.rgb(22, 26, 37))
            addView(TextView(appContext).apply {
                text = "NEXUS 系统助手"
                textSize = 22f
                setTextColor(Color.WHITE)
            })
            message = TextView(appContext).apply {
                textSize = 16f
                setTextColor(Color.LTGRAY)
                setPadding(0, padding / 2, 0, padding / 2)
            }.also { addView(it) }
            open = Button(appContext).apply {
                text = "打开助手"
                setOnClickListener { openAssistant() }
            }.also { addView(it) }
            addView(TextView(appContext).apply {
                text = "仅在点击下方按钮后读取本页文字，可能包含敏感信息；下一步可编辑后加入草稿。不截图、不自动发送。"
                textSize = 14f
                setTextColor(Color.LTGRAY)
            })
            read = Button(appContext).apply {
                text = "读取本页文字（仅本次）"
                setOnClickListener { readPage() }
            }.also { addView(it) }
            use = Button(appContext).apply {
                text = "核对文字并带入助手"
                visibility = View.GONE
                setOnClickListener { transferPage() }
            }.also { addView(it) }
            addView(Button(appContext).apply {
                text = "关闭"
                setOnClickListener { hide() }
            })
        }
    }

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        // No showWhenLocked/dismissKeyguard: the OS lock boundary is preserved.
        window?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val locked = AssistantRoleBridge.locked(appContext)
        val connected = AssistantRoleBridge.status(appContext)["connected"] == true
        if (!requested || locked || !connected) message?.text = when {
            locked -> "请先解锁手机，再打开助手。"
            !connected -> "NEXUS 当前不是已激活的默认助手，请在系统设置中重新选择。"
            else -> "打开助手输入文字，或点击下方按钮单次读取本页文字。"
        }
        open?.isEnabled = connected && !locked
        read?.isEnabled = connected && !locked && !requested
        if (locked || !connected) { awaiting = false; snapshot = null; use?.visibility = View.GONE }
    }

    private fun allowed() = !closed && !AssistantRoleBridge.locked(appContext) &&
        AssistantRoleBridge.status(appContext)["connected"] == true

    private fun readPage() {
        if (!allowed() || requested) return
        requested = true
        awaiting = true
        read?.isEnabled = false
        capturedElapsed = SystemClock.elapsedRealtime()
        capturedMillis = System.currentTimeMillis()
        message?.text = "正在读取本次页面文字…"
        // This instance accepts exactly one capture. The IPC snapshots the
        // context flags synchronously; restore the default immediately after it.
        try {
            setDisabledShowContext(SHOW_WITH_SCREENSHOT)
            show(Bundle().apply { putBoolean("nexus.one_shot_context", true) }, SHOW_WITH_ASSIST)
        } catch (_: Exception) {
            awaiting = false
            message?.text = "系统未能读取页面文字，请使用系统分享。"
        } finally {
            try { setDisabledShowContext(SHOW_WITH_ASSIST or SHOW_WITH_SCREENSHOT) } catch (_: Exception) {}
        }
        handler.postDelayed({
            if (awaiting) { awaiting = false; message?.text = "读取已超时，请关闭后重试或使用系统分享。" }
        }, 8000)
    }

    @Suppress("DEPRECATION")
    override fun onHandleAssist(data: Bundle?, structure: AssistStructure?, content: AssistContent?) {
        // Framework routes the primary/focused activity here on all supported
        // SDKs; secondary activities are never inspected by this session.
        if (!awaiting || !allowed() || SystemClock.elapsedRealtime() - capturedElapsed > 8000) return
        awaiting = false
        handler.removeCallbacksAndMessages(null)
        val extracted = AssistTextExtractor.extract(appContext, structure)
        if (extracted == null) {
            message?.text = "没有可读取的页面文字；应用或系统可能已保护此页面。请主动分享可分享的内容，不会绕过保护。"
            return
        }
        snapshot = AssistantContextHandoff.Payload(UUID.randomUUID().toString(), extracted.sourcePackage,
            extracted.sourceLabel, extracted.text, capturedMillis, capturedElapsed, extracted.truncated)
        message?.text = "来源：${extracted.sourceLabel}（${extracted.sourcePackage}）\n已读取${extracted.text.length}字${if (extracted.truncated) "，仅部分内容" else ""}。两分钟内有效，请核对并删除敏感信息。"
        use?.visibility = View.VISIBLE
        handler.postDelayed({ snapshot = null; use?.visibility = View.GONE
            message?.text = "页面文字已过期，请关闭后重新读取。" }, 120000 - (SystemClock.elapsedRealtime() - capturedElapsed))
    }

    private fun transferPage() {
        val value = snapshot ?: return
        if (!allowed() || value.remaining() <= 0) { snapshot = null; use?.visibility = View.GONE; return }
        if (!AssistantContextHandoff.stage(value)) {
            message?.text = "已有待处理的页面文字，请先打开助手处理，再重新读取。"
            return
        }
        openAssistant()
    }

    override fun onHide() {
        super.onHide()
        if (!closed) {
            closed = true
            awaiting = false
            snapshot = null
            handler.removeCallbacksAndMessages(null)
            // A new gesture gets a new session/binder; old callbacks cannot be
            // mistaken for the next one-time capture.
            finish()
        }
    }

    private fun openAssistant() {
        // Recheck at the action boundary, including revocation while visible.
        if (AssistantRoleBridge.locked(appContext) ||
            AssistantRoleBridge.status(appContext)["connected"] != true) {
            open?.isEnabled = false
            message?.text = "状态已变化，请解锁并重新选择默认助手。"
            return
        }
        try {
            appContext.startActivity(Intent(appContext, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("nexus://assistant")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            })
            hide()
        } catch (_: Exception) {
            message?.text = "打开助手失败，请关闭面板后从应用图标进入。"
        }
    }

    // Explicitly discard any unexpected screenshot; never save or forward it.
    override fun onHandleScreenshot(screenshot: Bitmap?) {}
    override fun onLockscreenShown() { hide() }
    override fun onDestroy() {
        closed = true; awaiting = false; snapshot = null
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
