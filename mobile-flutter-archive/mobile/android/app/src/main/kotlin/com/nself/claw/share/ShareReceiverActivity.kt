/// E-26-05b: Android Share Activity.
///
/// Receives shared content via Intent and bridges to Flutter
/// via MethodChannel. Opens the ShareComposerScreen.
package com.nself.claw.share

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class ShareReceiverActivity : FlutterActivity() {

    private val channelName = "com.nself.claw/share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSharedData" -> {
                        val sharedData = handleIntent(intent)
                        result.success(sharedData)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent): Map<String, String?>? {
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("text/") == true) {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    val title = intent.getStringExtra(Intent.EXTRA_SUBJECT)
                    mapOf(
                        "content" to text,
                        "title" to title,
                        "mime_type" to intent.type
                    )
                } else {
                    null
                }
            }
            else -> null
        }
    }
}
