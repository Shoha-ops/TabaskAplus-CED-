package com.example.e_class

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class ScheduleWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        // Enter relevant functionality for when the first widget is created
    }

    override fun onDisabled(context: Context) {
        // Enter relevant functionality for when the last widget is disabled
    }
}

internal fun updateAppWidget(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int
) {
    val widgetData = HomeWidgetPlugin.getData(context)
    val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
        val subject = widgetData.getString("widget_subject", "No Class")
        val time = widgetData.getString("widget_time", "")
        val room = widgetData.getString("widget_room", "")

        setTextViewText(R.id.widget_title, "NEXT CLASS")
        setTextViewText(R.id.widget_subject, subject)
        setTextViewText(R.id.widget_time, time)
        setTextViewText(R.id.widget_room, room)
    }

    appWidgetManager.updateAppWidget(appWidgetId, views)
}