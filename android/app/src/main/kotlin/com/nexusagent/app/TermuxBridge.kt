package com.nexusagent.app

import android.app.Activity
import android.content.Intent

/**
 * G1 Termux 桥：把命令交给 Termux 沙箱执行（那里有完整的 Go/Node 工具链），
 * 绕开 Android 10+ 对 app 私有目录的 W^X 执行限制。
 *
 * 回传采用文件交换协议：Dart 侧把命令包装为"输出重定向到 /sdcard/pocketforge-bridge/
 * 下的临时文件"，本类只负责发出 RUN_COMMAND Intent；ColorOS 上 PendingIntent
 * 广播回传不可靠，故不再使用。结果由 Dart 轮询桥目录获得。
 */
object TermuxBridge {
    fun launch(activity: Activity, command: String) {
        val service = Intent().apply {
            setClassName("com.termux", "com.termux.app.RunCommandService")
            action = "com.termux.RUN_COMMAND"
            putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-lc", command))
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
        }
        activity.startService(service)
    }
}
