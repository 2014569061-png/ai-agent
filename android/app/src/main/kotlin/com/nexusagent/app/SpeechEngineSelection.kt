package com.nexusagent.app

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings

/** Never count our metadata adapter as an available external speech engine. */
object SpeechEngineSelection {
    fun selectedExternal(context: Context): ComponentName? {
        val selected = Settings.Secure.getString(context.contentResolver, "voice_recognition_service")
            ?.let { ComponentName.unflattenFromString(it) } ?: return null
        if (selected.packageName == context.packageName) return null
        return try {
            @Suppress("DEPRECATION")
            val info = context.packageManager.getServiceInfo(selected, 0)
            if (info.enabled && info.applicationInfo.enabled && info.exported &&
                info.permission == "android.permission.BIND_SPEECH_RECOGNITION_SERVICE") selected else null
        } catch (_: PackageManager.NameNotFoundException) { null }
    }
}
