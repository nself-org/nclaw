/// F-28-06: Android AppWidgetProvider for nClaw.
///
/// Three widget sizes via resizeMode. Reads widget_topics JSON from
/// SharedPreferences (written by Flutter home_widget package).
/// Taps deep-link via claw://topic/{id}.
package io.nself.claw

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

class ClawWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.claw_widget)

            // Read widget data from shared preferences (written by Flutter).
            val jsonString = widgetData.getString("widget_topics", null)

            if (jsonString != null) {
                try {
                    val data = JSONObject(jsonString)
                    val conversations = data.optJSONArray("recent_conversations")
                    val pendingCount = data.optInt("pending_count", 0)

                    // Populate first topic (always visible).
                    if (conversations != null && conversations.length() > 0) {
                        val first = conversations.getJSONObject(0)
                        views.setTextViewText(R.id.topic_title_1, first.optString("title", ""))
                        views.setTextViewText(R.id.topic_message_1, first.optString("last_message", ""))

                        // Second topic.
                        if (conversations.length() > 1) {
                            val second = conversations.getJSONObject(1)
                            views.setTextViewText(R.id.topic_title_2, second.optString("title", ""))
                            views.setTextViewText(R.id.topic_message_2, second.optString("last_message", ""))
                        }

                        // Third topic.
                        if (conversations.length() > 2) {
                            val third = conversations.getJSONObject(2)
                            views.setTextViewText(R.id.topic_title_3, third.optString("title", ""))
                            views.setTextViewText(R.id.topic_message_3, third.optString("last_message", ""))
                        }

                        // Pending count badge.
                        if (pendingCount > 0) {
                            views.setTextViewText(R.id.pending_badge, "$pendingCount")
                            views.setViewVisibility(R.id.pending_badge, android.view.View.VISIBLE)
                        } else {
                            views.setViewVisibility(R.id.pending_badge, android.view.View.GONE)
                        }
                    }
                } catch (e: Exception) {
                    views.setTextViewText(R.id.topic_title_1, "Open nClaw")
                    views.setTextViewText(R.id.topic_message_1, "Tap to start")
                }
            } else {
                views.setTextViewText(R.id.topic_title_1, "Open nClaw")
                views.setTextViewText(R.id.topic_message_1, "Tap to start a conversation")
            }

            // Set click intent to open app via deep link.
            val intent = homeWidgetLaunchIntent(context)
            intent.data = Uri.parse("claw://topic/latest")
            val pendingIntent = android.app.PendingIntent.getActivity(
                context, 0, intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun homeWidgetLaunchIntent(context: Context): android.content.Intent {
        return android.content.Intent(context, MainActivity::class.java).apply {
            action = android.content.Intent.ACTION_VIEW
            flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                    android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
    }
}
