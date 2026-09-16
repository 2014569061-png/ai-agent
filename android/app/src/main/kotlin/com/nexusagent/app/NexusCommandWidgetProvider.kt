package com.nexusagent.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/**
 * 「NEXUS 指挥台」桌面小组件：把三个最常用的入口放到桌面，不需要先找到并打开 App。
 *
 * 三个按钮都复用与应用快捷方式相同的 `nexus://` 深链，由 Dart 侧 DeepLinkService 解析：
 * · nexus://new-agent → 进入 Agent 页并直接弹出「描述目标」输入框
 * · nexus://new-chat  → 新建对话
 * · nexus://memory    → 打开长期记忆页
 *
 * 刻意保持无状态（不展示任务进度）：读取 Dart 侧的任务状态需要跨进程传数据（文件或
 * ContentProvider），会引入一套新的共享协议；当前版本先用「入口」价值换实现复杂度，
 * 后续要做进度展示时再补数据通道。
 */
class NexusCommandWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.nexus_command_widget)
            views.setOnClickPendingIntent(
                R.id.widget_describe_agent,
                deepLink(context, "nexus://new-agent", REQUEST_DESCRIBE_AGENT),
            )
            views.setOnClickPendingIntent(
                R.id.widget_new_chat,
                deepLink(context, "nexus://new-chat", REQUEST_NEW_CHAT),
            )
            views.setOnClickPendingIntent(
                R.id.widget_memory,
                deepLink(context, "nexus://memory", REQUEST_MEMORY),
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun deepLink(context: Context, uri: String, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri), context, MainActivity::class.java).apply {
            // NEW_TASK：从桌面启动必须自带任务栈；SINGLE_TOP 保证热启动复用同一个
            // Activity，从而走 onNewIntent 把深链交给 Dart 侧，而不是重开一个界面。
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            // IMMUTABLE：Android 12+ 强制要求显式声明可变性；这些 Intent 不需要被外部改写。
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private companion object {
        // 三个 requestCode 必须互不相同，否则 PendingIntent 会互相覆盖（系统按
        // requestCode + Intent 的 filterEquals 判断是否复用）。
        const val REQUEST_DESCRIBE_AGENT = 101
        const val REQUEST_NEW_CHAT = 102
        const val REQUEST_MEMORY = 103
    }
}
