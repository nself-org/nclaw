/**
 * Android Share Target Module — Native bridge for share intent handling.
 *
 * Purpose: Extract SEND/SEND_MULTIPLE intent extras from MainActivity,
 * serialize to JSON, and write to AsyncStorage for React JS consumption.
 *
 * Constraints: MainActivity calls this on launch; must handle null intents.
 */

package org.nself.nclaw

import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.module.annotations.ReactModule
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileOutputStream

@ReactModule(name = "ShareTargetModule")
class ShareTargetModule(reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {
    override fun getName() = "ShareTargetModule"

    /**
     * Extract share intent data from MainActivity.
     * Called by React Native on app startup.
     */
    @ReactMethod
    fun getSharedData(promise: Promise) {
        try {
            val activity = currentActivity as? AppCompatActivity
            val intent = activity?.intent ?: run {
                promise.resolve(null)
                return
            }

            val action = intent.action
            if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
                promise.resolve(null)
                return
            }

            val type = intent.type ?: ""
            val extras = intent.extras ?: run {
                promise.resolve(null)
                return
            }

            // Extract shared content
            var sharedText = ""
            var sharedUrl: String? = null
            var sharedTitle: String? = null
            var sharedImage: String? = null
            var sharedMimeType = type

            when {
                // Text share
                type.startsWith("text/") -> {
                    sharedText = extras.getString(Intent.EXTRA_TEXT) ?: ""
                    sharedTitle = extras.getString(Intent.EXTRA_SUBJECT)
                    // Check if text is actually a URL
                    if (sharedText.startsWith("http://") || sharedText.startsWith("https://")) {
                        sharedUrl = sharedText
                        sharedMimeType = "text/x-uri"
                    }
                }
                // Image share
                type.startsWith("image/") -> {
                    val imageUri = if (action == Intent.ACTION_SEND) {
                        extras.getParcelable<Uri>(Intent.EXTRA_STREAM)
                    } else {
                        val uriList = extras.getParcelableArrayList<Uri>(Intent.EXTRA_STREAM)
                        uriList?.firstOrNull()
                    }
                    if (imageUri != null) {
                        sharedImage = imageUri.toString()
                        sharedMimeType = "image/jpeg"
                    }
                }
            }

            // Build response
            val payload = mapOf(
                "type" to (if (sharedImage != null) "image" else if (sharedUrl != null) "url" else "text"),
                "text" to sharedText,
                "url" to (sharedUrl ?: ""),
                "title" to (sharedTitle ?: ""),
                "imageUri" to (sharedImage ?: ""),
                "mimeType" to sharedMimeType
            )

            // Serialize and store
            val jsonString = Json.encodeToString(payload)
            val prefs = reactApplicationContext.getSharedPreferences("NCLAW_SHARED", android.content.Context.MODE_PRIVATE)
            prefs.edit().putString("SHARED_CONTENT", jsonString).apply()

            promise.resolve(Arguments.makeNativeMap(payload))
        } catch (e: Exception) {
            Log.e("ShareTargetModule", "Error extracting shared data", e)
            promise.reject("SHARE_ERROR", e.message)
        }
    }

    /**
     * Clear shared data after consuming.
     */
    @ReactMethod
    fun clearSharedData(promise: Promise) {
        try {
            val prefs = reactApplicationContext.getSharedPreferences("NCLAW_SHARED", android.content.Context.MODE_PRIVATE)
            prefs.edit().remove("SHARED_CONTENT").apply()
            promise.resolve(true)
        } catch (e: Exception) {
            promise.reject("CLEAR_ERROR", e.message)
        }
    }
}
