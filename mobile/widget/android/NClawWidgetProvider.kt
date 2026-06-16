/**
 * nclaw/mobile — Android App Widget Provider (Kotlin)
 *
 * Purpose: Broadcasts home screen widget updates and handles quick-capture button taps.
 *          Reads lastSummary + captureDeepLink from SharedPreferences (app-group equivalent).
 * Inputs:  ACTION_APPWIDGET_UPDATE broadcasts + button tap intents.
 * Outputs: RemoteViews layout with updated summary + deep link intent on button.
 * Constraints:
 *   - onUpdate() called on 30-min intervals (configurable in widget info XML).
 *   - App must write to SharedPreferences with key "org.nself.nclaw.widget" (JSON data).
 *   - Button tap → PendingIntent opens nclaw://capture deep link via Intent.ACTION_VIEW.
 *   - SharedPreferences accessed via Context.getSharedPreferences(); mutual access with app via same key.
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn android-widget)
 */

package org.nself.nclaw.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import org.json.JSONObject

class NClawWidgetProvider : AppWidgetProvider() {
  companion object {
    private const val WIDGET_DATA_KEY = "org.nself.nclaw.widget"
    private const val WIDGET_DATA_PREF_FILE = "org.nself.nclaw.widget.prefs"
    private const val ACTION_QUICK_CAPTURE = "org.nself.nclaw.action.QUICK_CAPTURE"
  }

  /**
   * Called when widget is first added to home screen or on refresh interval.
   * Inputs: context, AppWidgetManager, array of widget IDs.
   * Outputs: Updates RemoteViews for each widget with latest data.
   */
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray
  ) {
    for (appWidgetId in appWidgetIds) {
      updateAppWidget(context, appWidgetManager, appWidgetId)
    }
  }

  /**
   * Called when quick-capture button is tapped.
   * Inputs: Intent with ACTION_QUICK_CAPTURE or other custom actions.
   * Outputs: Starts main app activity with nclaw://capture deep link.
   */
  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)

    if (intent.action == ACTION_QUICK_CAPTURE) {
      // Open app to quick capture screen via deep link
      val deepLinkIntent = Intent(Intent.ACTION_VIEW).apply {
        data = Uri.parse("nclaw://capture")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      context.startActivity(deepLinkIntent)
    }
  }

  /**
   * Update a single widget instance with latest data from SharedPreferences.
   * Inputs: Widget ID and context.
   * Outputs: RemoteViews sent to AppWidgetManager.
   */
  private fun updateAppWidget(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int
  ) {
    // Read widget data from SharedPreferences
    val prefs = context.getSharedPreferences(WIDGET_DATA_PREF_FILE, Context.MODE_PRIVATE)
    val jsonStr = prefs.getString(WIDGET_DATA_KEY, null)

    var lastSummary = "Start a conversation to see summaries here."
    var captureDeepLink = "nclaw://capture"

    if (jsonStr != null) {
      try {
        val json = JSONObject(jsonStr)
        lastSummary = json.optString("lastSummary", lastSummary)
        captureDeepLink = json.optString("captureDeepLink", captureDeepLink)
      } catch (e: Exception) {
        // Malformed JSON; use fallback
      }
    }

    // Build RemoteViews layout
    val views = RemoteViews(context.packageName, R.layout.nclaw_widget)

    // Update summary text
    views.setTextViewText(R.id.widget_summary, lastSummary)

    // Set up quick-capture button intent
    val captureIntent = Intent(context, NClawWidgetProvider::class.java).apply {
      action = ACTION_QUICK_CAPTURE
    }
    val capturePendingIntent = PendingIntent.getBroadcast(
      context,
      0,
      captureIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    views.setOnClickPendingIntent(R.id.widget_quick_capture_btn, capturePendingIntent)

    // Push updated views to AppWidgetManager
    appWidgetManager.updateAppWidget(appWidgetId, views)
  }
}
