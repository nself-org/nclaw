package org.nself.nclaw.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import org.nself.nclaw.NClaw
import java.util.UUID

class ClawClient(private val context: Context) {

    private val prefs by lazy {
        context.getSharedPreferences("nclaw_settings", Context.MODE_PRIVATE)
    }

    var serverURL: String
        get() = prefs.getString("server_url", "") ?: ""
        set(value) = prefs.edit().putString("server_url", value).apply()

    var apiKey: String
        get() = prefs.getString("api_key", "") ?: ""
        set(value) = prefs.edit().putString("api_key", value).apply()

    private var clawInstance: NClaw? = null
    private var lastURL: String = ""
    private var lastKey: String = ""

    private var webSocket: WebSocket? = null
    private val httpClient = OkHttpClient()
    private val deviceId = UUID.randomUUID().toString()

    private fun connectWebSocketIfNeeded() {
        val baseURL = serverURL.trimEnd('/')
        if (baseURL.isBlank()) return

        val wsUrl = "$baseURL/claw/ws?user_id=android_user&last_seq=0".replace("http", "ws")
        val request = Request.Builder()
            .url(wsUrl)
            .addHeader("Authorization", apiKey)
            .build()

        webSocket = httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                println("WebSocket connected")
                registerCapabilities(webSocket)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                println("WebSocket received: $text")
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                println("WebSocket disconnected")
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                println("WebSocket error: ${t.message}")
            }
        })
    }

    private fun registerCapabilities(webSocket: WebSocket) {
        val payload = JSONObject().apply {
            put("type", "capabilities")
            put("device_id", deviceId)
            put("platform", "android")
            put("version", "1.0")
            put("actions", JSONArray(listOf("clipboard_read", "clipboard_write", "location")))
        }
        webSocket.send(payload.toString())
    }

    suspend fun sendMessage(text: String): String = withContext(Dispatchers.IO) {
        val currentURL = serverURL
        val currentKey = apiKey
        
        val baseURL = currentURL.trimEnd('/')
        if (baseURL.isBlank()) {
            throw ClawException("Server URL not configured. Check settings.")
        }

        if (clawInstance == null || lastURL != baseURL || lastKey != currentKey) {
            clawInstance?.disconnect()
            try {
                clawInstance = NClaw(baseURL, currentKey)
            } catch (e: Exception) {
                throw ClawException("Failed to connect to NClaw: ${e.message}")
            }
            lastURL = baseURL
            lastKey = currentKey
            connectWebSocketIfNeeded()
        }

        val claw = clawInstance ?: throw ClawException("NClaw instance is null")

        try {
            claw.sendMessage(text)
        } catch (e: Exception) {
            throw ClawException("Server error: ${e.message}")
        }
    }
}

class ClawException(message: String) : Exception(message)
