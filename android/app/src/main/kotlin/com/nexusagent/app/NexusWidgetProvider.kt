package com.nexusagent.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 主屏幕 Widget Provider（E2）。
 * 展示最近会话/记忆摘要，点击唤起 App（携带 nexus:// URI）。
 */
class NexusWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.nexus_widget_layout).apply {
                val items = widgetData.getString("items", null)
                setTextViewText(R.id.widget_text, items ?: "NEXUS Agent")
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("nexus://new-chat")
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
