package com.nexusagent.app

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import android.widget.FrameLayout
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.util.UUID

/** One foreground browser, one unique cookie/storage profile, no native JS bridge. */
class BrowserBridge(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "nexus/browser")
    private val events = EventChannel(engine.dartExecutor.binaryMessenger, "nexus/browser/events")
    private val handler = Handler(Looper.getMainLooper())
    private val script = activity.assets.open("browser_dom.js").bufferedReader().use { it.readText() }
    private var sink: EventChannel.EventSink? = null
    private var current: Session? = null
    private var foreground = true
    private var fixtureContainer: FrameLayout? = null
    private data class Pending(val result: MethodChannel.Result, val dispatched: Boolean, val timeout: Runnable)
    private class Session(val id: String, val profile: String, val web: WebView, val fixture: Boolean) {
        var epoch = 1
        var mode = "user"
        var attached = false
        var loading = false
        var failure: String? = null
        var pending: Pending? = null
    }

    init {
        channel.setMethodCallHandler(::handle)
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                sink = eventSink; current?.let { emit(it) }
            }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        engine.platformViewsController.registry.registerViewFactory("nexus/browser-view",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: android.content.Context, id: Int, args: Any?): PlatformView {
                    val container = FrameLayout(context)
                    val session = current
                    if (session != null && (args as? Map<*, *>)?.get("sessionId") == session.id) {
                        (session.web.parent as? ViewGroup)?.removeView(session.web)
                        container.addView(session.web, FrameLayout.LayoutParams(-1, -1))
                        session.attached = true; emit(session)
                    }
                    return object : PlatformView {
                        override fun getView(): View = container
                        override fun dispose() {
                            container.removeAllViews()
                            if (current === session && session != null) {
                                session.attached = false; revoke(session)
                            }
                        }
                    }
                }
            })
    }

    private fun state(s: Session): Map<String, Any?> = mapOf(
        "sessionId" to s.id, "epoch" to s.epoch, "mode" to s.mode,
        "attached" to s.attached, "loading" to s.loading,
        "url" to s.web.url, "errorCode" to s.failure, "isolatedProfile" to true)
    private fun emit(s: Session) { if (current === s) sink?.success(state(s)) }
    private fun fail(result: MethodChannel.Result, code: String, dispatched: Boolean = false) {
        result.error(code, "Browser operation unavailable", mapOf("dispatched" to dispatched))
    }
    private fun pendingFailure(s: Session, code: String) {
        s.pending?.let {
            s.pending = null; handler.removeCallbacks(it.timeout)
            fail(it.result, code, it.dispatched)
        }
    }
    private fun revoke(s: Session) {
        s.mode = "user"; s.epoch++; s.web.stopLoading()
        pendingFailure(s, "CANCELLED"); emit(s)
    }
    fun pause() { foreground = false; current?.let { revoke(it); it.web.onPause() } }
    fun resume() { foreground = true; current?.web?.onResume() }

    private fun allowed(raw: String, s: Session? = null): Boolean {
        if (raw.length > 4096 || raw.any { it.code <= 32 || it == '\\' }) return false
        val uri = Uri.parse(raw)
        return uri.scheme in setOf("http", "https") && !uri.host.isNullOrBlank() &&
            uri.userInfo.isNullOrEmpty() && (s?.fixture != true ||
            (uri.scheme == "https" && uri.host == "nexus-browser-fixture.invalid"))
    }

    @SuppressLint("SetJavaScriptEnabled", "ClickableViewAccessibility")
    private fun open(fixture: Boolean): Session {
        check(current == null)
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            throw UnsupportedOperationException("MULTI_PROFILE")
        }
        // Reap only our abandoned profiles. Never delete the app's default profile.
        val store = ProfileStore.getInstance()
        for (name in store.allProfileNames.filter { it.startsWith("nexus_agent_") }) {
            try { store.deleteProfile(name) } catch (error: IllegalStateException) {
                android.util.Log.w("NexusBrowser", "Profile cleanup deferred: ${error.javaClass.simpleName}")
            }
        }
        val id = UUID.randomUUID().toString()
        val web = WebView(activity)
        val profile = "nexus_agent_" + id.replace("-", "")
        WebViewCompat.setProfile(web, profile)
        val s = Session(id, profile, web, fixture)
        current = s
        web.settings.apply {
            javaScriptEnabled = true; domStorageEnabled = true
            allowFileAccess = false; allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false); setGeolocationEnabled(false)
            mediaPlaybackRequiresUserGesture = true
            if (android.os.Build.VERSION.SDK_INT >= 26) safeBrowsingEnabled = true
        }
        web.setOnTouchListener { _, event ->
            if (event.actionMasked == MotionEvent.ACTION_DOWN && s.mode == "agent") revoke(s)
            false
        }
        web.setDownloadListener { _, _, _, _, _ -> s.failure = "DOWNLOAD_UNSUPPORTED"; revoke(s) }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
                callback.invoke(origin, false, false)
            }
            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                callback.onReceiveValue(null); return true
            }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val blocked = !allowed(request.url.toString(), s)
                if (blocked) { s.failure = "URL_BLOCKED"; emit(s) }
                return blocked
            }
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                if (s.fixture && request.url.host == "nexus-browser-fixture.invalid") {
                    return WebResourceResponse("text/html", "UTF-8", activity.assets.open("browser_fixture.html"))
                }
                if (!allowed(request.url.toString(), s)) return WebResourceResponse(
                    "text/plain", "UTF-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(byteArrayOf()))
                return null
            }
            override fun onPageStarted(view: WebView, url: String, icon: Bitmap?) {
                s.epoch++; s.loading = true; s.failure = null; emit(s)
            }
            override fun onPageFinished(view: WebView, url: String) {
                if (current !== s) return
                s.loading = false; s.epoch++; emit(s)
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) { s.failure = "NETWORK_UNAVAILABLE"; s.loading = false; emit(s) }
            }
            override fun onReceivedSslError(view: WebView, ssl: SslErrorHandler, error: SslError) {
                ssl.cancel(); s.failure = "TLS_ERROR"; emit(s)
            }
            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                s.failure = "RENDERER_GONE"; revoke(s); close(s); return true
            }
        }
        return s
    }

    private fun close(s: Session): Map<String, Any?> {
        if (current !== s) return mapOf("closed" to true)
        current = null
        pendingFailure(s, "SESSION_EXPIRED")
        s.web.stopLoading(); (s.web.parent as? ViewGroup)?.removeView(s.web)
        fixtureContainer?.let { (it.parent as? ViewGroup)?.removeView(it) }; fixtureContainer = null
        s.web.removeAllViews(); s.web.destroy()
        var deferred = false
        try { ProfileStore.getInstance().deleteProfile(s.profile) }
        catch (error: IllegalStateException) {
            deferred = true
            android.util.Log.w("NexusBrowser", "Profile cleanup deferred: ${error.javaClass.simpleName}")
        }
        return mapOf("closed" to true, "profileCleanupPending" to deferred)
    }

    private fun evaluate(s: Session, request: JSONObject, result: MethodChannel.Result) {
        if (s.pending != null) { fail(result, "RESULT_PENDING"); return }
        val epoch = s.epoch
        val dispatched = request.optString("action") != "observe"
        val timeout = Runnable {
            if (s.pending?.result === result) {
                s.pending = null; fail(result, "TIMEOUT", dispatched)
            }
        }
        s.pending = Pending(result, dispatched, timeout)
        handler.postDelayed(timeout, 8000)
        s.web.evaluateJavascript("JSON.stringify(($script)(${request}))") { raw ->
            if (s.pending?.result !== result) return@evaluateJavascript
            s.pending = null; handler.removeCallbacks(timeout)
            if (current !== s || !foreground || s.mode != "agent" || epoch != s.epoch) {
                fail(result, "REVISION_CONFLICT", dispatched); return@evaluateJavascript
            }
            try {
                val decoded = org.json.JSONTokener(raw).nextValue() as? String
                    ?: throw IllegalStateException("Invalid DOM response")
                val json = JSONObject(decoded)
                if (!json.optBoolean("ok")) { fail(result, json.optString("code", "MALFORMED_RESPONSE")); return@evaluateJavascript }
                if (dispatched) s.epoch++
                val map = jsonMap(json).toMutableMap()
                map["epoch"] = s.epoch; map["state"] = state(s)
                result.success(map); emit(s)
            } catch (_: Exception) { fail(result, "OUTCOME_UNKNOWN", dispatched) }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method in setOf("open", "debugFixture")) {
                if (!foreground) { fail(result, "PERMISSION_REQUIRED"); return }
                if (current != null) { fail(result, "ALREADY_EXISTS"); return }
                val fixture = call.method == "debugFixture"
                if (fixture && (activity.applicationInfo.flags and
                        android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
                    result.notImplemented(); return
                }
                val created = open(fixture)
                if (fixture) {
                    val container = FrameLayout(activity)
                    container.addView(created.web, FrameLayout.LayoutParams(-1, -1))
                    activity.addContentView(container, ViewGroup.LayoutParams(900, 1200))
                    fixtureContainer = container; created.attached = true
                }
                result.success(state(created)); return
            }
            val s = current
            if (s == null || call.argument<String>("sessionId") != s.id) { fail(result, "SESSION_EXPIRED"); return }
            when (call.method) {
                "visit" -> {
                    val url = call.argument<String>("url") ?: ""
                    if (!foreground || !s.attached || !allowed(url, s)) {
                        fail(result, "INVALID_ARGUMENTS"); return
                    }
                    revoke(s); s.loading = true; s.web.loadUrl(url)
                    result.success(mapOf("dispatched" to true, "state" to state(s))); emit(s)
                }
                "close" -> result.success(close(s))
                "status" -> result.success(mapOf("state" to state(s)))
                "control" -> {
                    if (call.argument<String>("mode") == "agent") {
                        if (!foreground || !s.attached) { fail(result, "PERMISSION_REQUIRED"); return }
                        s.mode = "agent"; s.epoch++; emit(s)
                    } else revoke(s)
                    result.success(state(s))
                }
                "navigate", "observe", "act" -> {
                    if (!foreground || !s.attached || s.mode != "agent") { fail(result, "PERMISSION_REQUIRED"); return }
                    if (call.method != "observe" && call.argument<Number>("epoch")?.toInt() != s.epoch) {
                        fail(result, "REVISION_CONFLICT"); return
                    }
                    if (call.method == "navigate") {
                        val url = call.argument<String>("url") ?: ""
                        if (!allowed(url, s)) { fail(result, "INVALID_ARGUMENTS"); return }
                        if (s.pending != null) { fail(result, "RESULT_PENDING"); return }
                        s.epoch++; s.loading = true
                        s.web.loadUrl(url); emit(s)
                        result.success(mapOf("dispatched" to true, "state" to state(s)))
                    } else {
                        if (s.loading || s.failure != null) { fail(result, "RESULT_PENDING"); return }
                        val request = if (call.method == "observe") JSONObject(mapOf(
                            "action" to "observe", "snapshotId" to UUID.randomUUID().toString()))
                        else JSONObject((call.arguments as? Map<*, *>)?.filterKeys {
                            it in setOf("action", "snapshotId", "nodeId", "text", "dy") } ?: emptyMap<String, Any>())
                        val action = request.optString("action")
                        if (action !in setOf("observe", "click", "type", "scroll") ||
                            request.optString("text").length > 2000 ||
                            (action == "scroll" && request.optInt("dy") !in -1200..1200)) {
                            fail(result, "INVALID_ARGUMENTS"); return
                        }
                        evaluate(s, request, result)
                    }
                }
                else -> result.notImplemented()
            }
        } catch (_: UnsupportedOperationException) { fail(result, "CAPABILITY_UNAVAILABLE") }
        catch (_: Exception) { fail(result, "OUTCOME_UNKNOWN", call.method in setOf("act", "navigate")) }
    }

    private fun jsonMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith {
        fun convert(value: Any?): Any? = when (value) {
            JSONObject.NULL -> null
            is JSONObject -> jsonMap(value)
            is org.json.JSONArray -> (0 until value.length()).map { i -> convert(value.get(i)) }
            else -> value
        }
        convert(json.get(it))
    }

    fun dispose() {
        current?.let { close(it) }
        channel.setMethodCallHandler(null); events.setStreamHandler(null); sink = null
    }
}
