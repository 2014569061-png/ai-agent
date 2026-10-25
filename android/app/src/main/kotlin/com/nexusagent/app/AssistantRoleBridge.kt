package com.nexusagent.app

import android.app.Activity
import android.app.KeyguardManager
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.service.voice.VoiceInteractionService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Role selection, actual service readiness and opening settings are separate facts. */
class AssistantRoleBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "nexus/assistant_role")
    private val contextChannel = MethodChannel(messenger, "nexus/assistant_context")

    init {
        AssistantContextHandoff.listen(this, ::notifyContextChanged)
        contextChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "peek" -> result.success(AssistantContextHandoff.peek(activity))
                    "acknowledge" -> result.success(AssistantContextHandoff.acknowledge(call.argument<String>("id") ?: ""))
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("CONTEXT_UNAVAILABLE", "页面文字暂不可用，请重新读取", null)
            }
        }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status(activity))
                    "debugTextFilterCheck" -> {
                        if ((activity.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) result.notImplemented()
                        else result.success(mapOf(
                            "readable" to AssistTextExtractor.eligible(0, "android.widget.TextView", false, 0),
                            "inputExcluded" to !AssistTextExtractor.eligible(1, "android.widget.EditText", false, 0),
                            "customInputExcluded" to !AssistTextExtractor.eligible(129, "Custom", false, 0),
                            "blockedExcluded" to !AssistTextExtractor.eligible(0, "TextView", true, 0),
                            "hiddenExcluded" to !AssistTextExtractor.eligible(0, "TextView", false, 8)
                        ))
                    }
                    "requestRole" -> {
                        // AOSP marks ASSISTANT requestable=false. The generic
                        // role request dialog silently cancels for this role;
                        // the user must choose it in the system assistant UI.
                        activity.startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
                        // Never report role granted from launching a chooser.
                        result.success(mapOf("opened" to true))
                    }
                    "openSettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
                        result.success(mapOf("opened" to true))
                    }
                    "showSession" -> {
                        val state = status(activity)
                        val service = NexusVoiceInteractionService.readyService
                        if (state["connected"] != true || service == null || locked(activity)) {
                            result.success(mapOf("shown" to false, "reason" to "not_ready_or_locked"))
                        } else {
                            service.showSession(Bundle(), 0)
                            result.success(mapOf("requested" to true))
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("ASSISTANT_UNAVAILABLE", "系统助手操作未完成，请返回后刷新状态", null)
            }
        }
    }

    fun notifyContextChanged() { contextChannel.invokeMethod("pending", null) }
    fun dispose() {
        AssistantContextHandoff.detach(this)
        contextChannel.setMethodCallHandler(null)
        channel.setMethodCallHandler(null)
    }

    companion object {
        fun component(context: Context) = ComponentName(context, NexusVoiceInteractionService::class.java)
        fun locked(context: Context) =
            (context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked

        fun status(context: Context): Map<String, Any> {
            val manager = if (Build.VERSION.SDK_INT >= 29) context.getSystemService(RoleManager::class.java) else null
            val roleAvailable = manager?.isRoleAvailable(RoleManager.ROLE_ASSISTANT) ?: false
            val roleHeld = roleAvailable && manager?.isRoleHeld(RoleManager.ROLE_ASSISTANT) == true
            val selected = Settings.Secure.getString(context.contentResolver, "voice_interaction_service")
                ?.let { ComponentName.unflattenFromString(it) } == component(context)
            val active = VoiceInteractionService.isActiveService(context, component(context))
            val ready = NexusVoiceInteractionService.readyService != null
            val registered = listOf(
                NexusVoiceInteractionService::class.java,
                NexusVoiceInteractionSessionService::class.java,
                NexusRecognitionService::class.java
            ).all { clazz ->
                try {
                    @Suppress("DEPRECATION")
                    context.packageManager.getServiceInfo(ComponentName(context, clazz), PackageManager.GET_META_DATA).enabled
                } catch (_: Exception) { false }
            }
            val disabledContext = NexusVoiceInteractionService.readyService?.disabledShowContext ?: 3
            return mapOf(
                "supported" to registered, "roleRequired" to (Build.VERSION.SDK_INT >= 29), "roleAvailable" to roleAvailable,
                "roleHeld" to roleHeld, "selected" to selected, "active" to active,
                "ready" to ready, "connected" to (registered && selected && active && ready &&
                    (Build.VERSION.SDK_INT < 29 || roleHeld)),
                "locked" to locked(context), "contextCollection" to (disabledContext and 1 == 0),
                "contextDisabledFlags" to disabledContext, "contextReadOnRequest" to true,
                "backgroundMicrophone" to false, "hotword" to false,
                "recognitionAdapter" to "foreground_app_only"
            )
        }
    }
}
