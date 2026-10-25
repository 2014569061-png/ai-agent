package com.nexusagent.app

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Foreground single-utterance capture only. Never a wake-word/continuous service. */
class ForegroundSpeechBridge(private val activity: Activity, messenger: BinaryMessenger) : EventChannel.StreamHandler, SpeechCaptureLifecycle {
    companion object { const val PERMISSION_REQUEST = 31303 }
    private val methods = MethodChannel(messenger, "nexus/speech")
    private val events = EventChannel(messenger, "nexus/speech/events")
    private val handler = Handler(Looper.getMainLooper())
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var focus: AudioFocusRequest? = null
    private var sink: EventChannel.EventSink? = null
    private var owner: String? = null
    private var session: String? = null
    private var recognizer: SpeechRecognizer? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var permissionSession: String? = null
    private var foreground = false
    private var disposed = false
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { cancel("audio_route_changed") }
    }
    init {
        methods.setMethodCallHandler(::handle)
        events.setStreamHandler(this)
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= 33) activity.registerReceiver(noisy, filter, Context.RECEIVER_NOT_EXPORTED)
        else { @Suppress("DEPRECATION") activity.registerReceiver(noisy, filter) }
    }
    private fun onDeviceAvailable(): Boolean = Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)
    private fun permitted() = activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    private fun status() = mapOf("supportedSdk" to true, "minimumSdk" to 26, "onDeviceAvailable" to onDeviceAvailable(),
        "systemAvailable" to (SpeechEngineSelection.selectedExternal(activity) != null), "permissionGranted" to permitted(),
        "foreground" to foreground, "singleUtteranceOnly" to true)
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> result.success(status())
                "requestPermission" -> {
                    if (!foreground || disposed || owner == null || call.argument<String>("ownerId") != owner) {
                        result.success(mapOf("granted" to false, "reason" to "inactive")); return
                    }
                    if (permitted()) { result.success(mapOf("granted" to true)); return }
                    if (pendingPermission != null) { result.error("BUSY", "已有麦克风授权请求", null); return }
                    permissionSession = call.argument<String>("sessionId")
                    if (permissionSession?.matches(Regex("[A-Za-z0-9_-]{1,128}")) != true) { result.error("INVALID_SESSION", "语音会话已失效", null); return }
                    pendingPermission = result
                    activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
                }
                "start" -> start(call, result)
                "stop" -> {
                    val id = call.argument<String>("sessionId")
                    if (id != null && id == session && call.argument<String>("ownerId") == owner) {
                        emit(id, "processing"); recognizer?.stopListening()
                        handler.postDelayed({ if (session == id) cancel("final_result_timeout") }, 2500)
                    }
                    result.success(null)
                }
                "cancel" -> {
                    if (call.argument<String>("ownerId") == owner) {
                        if (call.argument<String>("sessionId") == permissionSession) {
                            pendingPermission?.success(mapOf("granted" to false, "reason" to "cancelled"))
                            pendingPermission = null; permissionSession = null
                        }
                        if (call.argument<String>("sessionId") == session) cancel("cancelled")
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: SecurityException) { if (pendingPermission === result) { pendingPermission = null; permissionSession = null }; cancel("permission_revoked"); result.error("PERMISSION_DENIED", "麦克风权限不可用", null) }
        catch (_: Exception) { if (pendingPermission === result) { pendingPermission = null; permissionSession = null }; cancel("recognizer_error"); result.error("SPEECH_UNAVAILABLE", "语音服务暂不可用", null) }
    }
    override fun permissionResult(code: Int, grantResults: IntArray): Boolean {
        if (code != PERMISSION_REQUEST) return false
        val result = pendingPermission; pendingPermission = null; permissionSession = null
        result?.success(mapOf("granted" to (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)))
        // Granting permission never starts recording by itself.
        return true
    }
    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("sessionId") ?: ""
        if (owner == null || !id.matches(Regex("[A-Za-z0-9_-]{1,128}")) || call.argument<String>("ownerId") != owner || sink == null) {
            result.error("INVALID_SESSION", "语音会话已失效", null); return
        }
        if (!foreground || disposed) { result.error("INACTIVE", "只能在前台录音", null); return }
        if (!permitted()) { result.error("PERMISSION_DENIED", "需要麦克风授权", null); return }
        if (Build.VERSION.SDK_INT < 26) { result.error("UNSUPPORTED_SDK", "此语音入口需要Android 8或以上版本", null); return }
        val allowSystem = call.argument<Boolean>("allowSystemService") == true
        val external = if (allowSystem) SpeechEngineSelection.selectedExternal(activity) else null
        val local = !allowSystem && onDeviceAvailable()
        if (!local && external == null) {
            result.error("NO_RECOGNIZER", "没有可用的所选语音识别服务，请使用文字输入", null); return
        }
        cancel("replaced")
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setOnAudioFocusChangeListener { change -> if (change < 0 && session == id) cancel("audio_interrupted") }.build()
        if (audio.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            result.error("AUDIO_BUSY", "音频正在被其他应用使用", null); return
        }
        focus = request; session = id
        val engine = if (local && Build.VERSION.SDK_INT >= 31) SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
            else SpeechRecognizer.createSpeechRecognizer(activity, external!!)
        recognizer = engine
        engine.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) { emit(id, "recording") }
            override fun onBeginningOfSpeech() { emit(id, "recording") }
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {} // Never forward/store raw audio.
            override fun onEndOfSpeech() { emit(id, "processing") }
            override fun onError(error: Int) {
                if (session != id) return
                val code = when (error) {
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission_revoked"
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "no_speech"
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network_error"
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "recognizer_busy"
                    else -> "recognizer_error"
                }
                emit(id, "error", code = code); release()
            }
            override fun onResults(results: Bundle?) {
                if (session != id) return
                emit(id, "result", results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.take(16000) ?: "")
                release()
            }
            override fun onPartialResults(partialResults: Bundle?) {
                emit(id, "partial", partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.take(16000) ?: "")
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val language = call.argument<String>("language")?.takeIf { it.matches(Regex("[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}")) } ?: Locale.getDefault().toLanguageTag()
        engine.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, language).putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1))
        handler.postDelayed({ if (session == id) cancel("utterance_limit") }, 60000)
        result.success(mapOf("accepted" to true, "onDevice" to local))
    }
    private fun emit(id: String, type: String, text: String? = null, code: String? = null) {
        if (session != id || disposed) return
        try { sink?.success(mapOf("ownerId" to owner, "sessionId" to id, "type" to type, "text" to text, "code" to code)) }
        catch (_: Exception) { release() }
    }
    private fun release() {
        session = null // Invalidate before cancel/destroy can trigger callbacks.
        handler.removeCallbacksAndMessages(null)
        val engine = recognizer; recognizer = null
        try { engine?.cancel(); engine?.destroy() } catch (_: Exception) {}
        val oldFocus = focus; focus = null
        try { oldFocus?.let { audio.abandonAudioFocusRequest(it) } } catch (_: Exception) {}
    }
    private fun cancel(reason: String) { session?.let { emit(it, "stopped", code = reason) }; release() }
    override fun resume() { if (!disposed) foreground = true }
    override fun pause() { foreground = false; cancel("background") }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) {
        cancel("listener_replaced")
        pendingPermission?.success(mapOf("granted" to false, "reason" to "replaced")); pendingPermission = null; permissionSession = null
        owner = ((arguments as? Map<*, *>)?.get("ownerId") as? String)?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{1,128}")) }
        sink = if (owner != null) eventSink else null
        if (owner != null) sink?.success(mapOf("ownerId" to owner, "type" to "connected"))
    }
    override fun onCancel(arguments: Any?) {
        if ((arguments as? Map<*, *>)?.get("ownerId") != owner) return
        cancel("listener_closed"); sink = null; owner = null
        pendingPermission?.success(mapOf("granted" to false, "reason" to "cancelled")); pendingPermission = null; permissionSession = null
    }
    override fun dispose() {
        pause(); disposed = true
        pendingPermission?.success(mapOf("granted" to false, "reason" to "disposed")); pendingPermission = null; permissionSession = null
        sink = null; owner = null; methods.setMethodCallHandler(null); events.setStreamHandler(null)
        try { activity.unregisterReceiver(noisy) } catch (_: Exception) {}
    }
}
