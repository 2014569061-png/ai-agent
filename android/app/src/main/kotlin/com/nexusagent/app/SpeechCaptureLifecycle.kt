package com.nexusagent.app

import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Keep API26 audio-focus classes out of the legacy activity's field types. */
interface SpeechCaptureLifecycle {
    fun permissionResult(code: Int, grantResults: IntArray): Boolean
    fun resume()
    fun pause()
    fun dispose()
}
object SpeechCaptureBridgeFactory {
    fun create(activity: Activity, messenger: BinaryMessenger): SpeechCaptureLifecycle =
        if (Build.VERSION.SDK_INT >= 26) Api26SpeechCapture.create(activity, messenger)
        else UnsupportedSpeechCapture(activity, messenger)
}
@android.annotation.TargetApi(26)
private object Api26SpeechCapture {
    fun create(activity: Activity, messenger: BinaryMessenger): SpeechCaptureLifecycle = ForegroundSpeechBridge(activity, messenger)
}
/** Readiness and typed fallback only. Never constructs a recognizer or asks permission. */
private class UnsupportedSpeechCapture(private val activity: Activity, messenger: BinaryMessenger) : SpeechCaptureLifecycle, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "nexus/speech")
    private val events = EventChannel(messenger, "nexus/speech/events")
    private var foreground = false
    init {
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(mapOf("supportedSdk" to false, "minimumSdk" to 26,
                    "onDeviceAvailable" to false, "systemAvailable" to false,
                    "permissionGranted" to (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED),
                    "foreground" to foreground, "singleUtteranceOnly" to true))
                "requestPermission" -> result.success(mapOf("granted" to false, "reason" to "unsupported_sdk"))
                "start" -> result.error("UNSUPPORTED_SDK", "此语音入口需要Android 8或以上版本", null)
                "stop", "cancel" -> result.success(null)
                else -> result.notImplemented()
            }
        }
        events.setStreamHandler(this)
    }
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        val owner = ((arguments as? Map<*, *>)?.get("ownerId") as? String)?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{1,128}")) }
        if (owner != null) sink?.success(mapOf("ownerId" to owner, "type" to "connected"))
    }
    override fun onCancel(arguments: Any?) {}
    override fun permissionResult(code: Int, grantResults: IntArray) = false
    override fun resume() { foreground = true }
    override fun pause() { foreground = false }
    override fun dispose() { foreground = false; methods.setMethodCallHandler(null); events.setStreamHandler(null) }
}
