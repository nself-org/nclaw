package com.nself.claw.data

import android.content.Context
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import com.nself.claw.NClaw
import java.util.UUID

class ClawClient(context: Context) {

    private val appContext = context.applicationContext

    private val prefs by lazy {
        appContext.getSharedPreferences("nclaw_settings", Context.MODE_PRIVATE)
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
    private val reconnectHandler = Handler(Looper.getMainLooper())
    private var reconnectDelay = RECONNECT_INITIAL_DELAY
    private var shouldReconnect = true

    // T-2178: Sensor streaming state
    private var sensorStreamingEnabled = false
    private val sensorHandler = Handler(Looper.getMainLooper())
    private var sensorRunnable: Runnable? = null

    private val userId: String
        get() {
            var id = prefs.getString(PREF_USER_ID, null)
            if (id == null) {
                id = UUID.randomUUID().toString()
                prefs.edit().putString(PREF_USER_ID, id).apply()
            }
            return id
        }

    private val deviceId: String
        get() {
            var id = prefs.getString(PREF_DEVICE_ID, null)
            if (id == null) {
                id = UUID.randomUUID().toString()
                prefs.edit().putString(PREF_DEVICE_ID, id).apply()
            }
            return id
        }

    private fun connectWebSocketIfNeeded() {
        val baseURL = serverURL.trimEnd('/')
        if (baseURL.isBlank()) return

        shouldReconnect = true
        reconnectDelay = RECONNECT_INITIAL_DELAY

        val wsUrl = "$baseURL/claw/ws?user_id=$userId&last_seq=0".replace("http", "ws")
        val request = Request.Builder()
            .url(wsUrl)
            .addHeader("Authorization", apiKey)
            .build()

        webSocket = httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                println("WebSocket connected")
                reconnectDelay = RECONNECT_INITIAL_DELAY
                registerCapabilities(webSocket)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                println("WebSocket received: $text")
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                println("WebSocket disconnected")
                reconnectWithBackoff()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                println("WebSocket error: ${t.message}")
                reconnectWithBackoff()
            }
        })
    }

    private fun reconnectWithBackoff() {
        if (!shouldReconnect) return
        println("WebSocket reconnecting in ${reconnectDelay}ms")
        reconnectHandler.postDelayed({
            connectWebSocketIfNeeded()
        }, reconnectDelay)
        reconnectDelay = (reconnectDelay * 2).coerceAtMost(RECONNECT_MAX_DELAY)
    }

    private fun registerCapabilities(webSocket: WebSocket) {
        val payload = JSONObject().apply {
            put("type", "capabilities")
            put("device_id", deviceId)
            put("platform", "android")
            put("version", "1.0")
            put("actions", JSONArray(listOf("clipboard_read", "clipboard_write", "location", "sensor_streaming")))
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

    // =========================================================================
    // T-2178: Sensor streaming scaffold
    // =========================================================================

    /**
     * Start streaming mobile sensor data to the server.
     * Reports battery level, GPS coordinates, and activity detection
     * at the configured interval. Data is sent as interactions with
     * channel="mobile_sensor" to np_claw_interactions.
     *
     * @param intervalMs reporting interval in milliseconds (default 60000 = 1 min)
     */
    fun startSensorStreaming(intervalMs: Long = SENSOR_DEFAULT_INTERVAL) {
        if (sensorStreamingEnabled) return
        sensorStreamingEnabled = true

        sensorRunnable = object : Runnable {
            override fun run() {
                if (!sensorStreamingEnabled) return
                sendSensorReport()
                sensorHandler.postDelayed(this, intervalMs)
            }
        }
        sensorHandler.post(sensorRunnable!!)
        println("Sensor streaming started (interval=${intervalMs}ms)")
    }

    /**
     * Stop sensor streaming.
     */
    fun stopSensorStreaming() {
        sensorStreamingEnabled = false
        sensorRunnable?.let { sensorHandler.removeCallbacks(it) }
        sensorRunnable = null
        println("Sensor streaming stopped")
    }

    /**
     * Collect current sensor data and send as a WebSocket message.
     * Uses channel="mobile_sensor" for server-side routing to
     * np_claw_interactions table.
     */
    private fun sendSensorReport() {
        val ws = webSocket ?: return

        val sensorData = JSONObject().apply {
            put("type", "sensor_report")
            put("channel", "mobile_sensor")
            put("device_id", deviceId)
            put("user_id", userId)
            put("timestamp", System.currentTimeMillis())

            // Battery level
            put("battery", collectBatteryData())

            // GPS location (last known)
            put("location", collectLocationData())

            // Activity detection (stationary, walking, driving, etc.)
            put("activity", collectActivityData())
        }

        ws.send(sensorData.toString())
    }

    /**
     * Collect battery level and charging state.
     * Requires no special permissions on Android.
     */
    private fun collectBatteryData(): JSONObject {
        val batteryManager = appContext.getSystemService(Context.BATTERY_SERVICE)
        return JSONObject().apply {
            // BatteryManager requires API 21+ (we target 24+)
            if (batteryManager is android.os.BatteryManager) {
                put("level", batteryManager.getIntProperty(
                    android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY
                ))
                put("charging", batteryManager.isCharging)
            } else {
                put("level", -1)
                put("charging", false)
            }
        }
    }

    /**
     * Collect last known GPS coordinates.
     * Returns empty coordinates if location permission is not granted.
     * The caller (Activity/Service) is responsible for requesting
     * ACCESS_FINE_LOCATION or ACCESS_COARSE_LOCATION permission.
     */
    private fun collectLocationData(): JSONObject {
        return JSONObject().apply {
            // Location requires runtime permission check.
            // Return placeholder if not available; the UI layer handles permission.
            try {
                val locationManager = appContext.getSystemService(Context.LOCATION_SERVICE)
                        as? android.location.LocationManager
                if (locationManager != null &&
                    appContext.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                ) {
                    val lastLocation = locationManager.getLastKnownLocation(
                        android.location.LocationManager.FUSED_PROVIDER
                    ) ?: locationManager.getLastKnownLocation(
                        android.location.LocationManager.GPS_PROVIDER
                    )
                    if (lastLocation != null) {
                        put("latitude", lastLocation.latitude)
                        put("longitude", lastLocation.longitude)
                        put("accuracy_m", lastLocation.accuracy)
                        put("timestamp", lastLocation.time)
                    } else {
                        put("available", false)
                    }
                } else {
                    put("available", false)
                    put("reason", "permission_not_granted")
                }
            } catch (e: SecurityException) {
                put("available", false)
                put("reason", "security_exception")
            }
        }
    }

    /**
     * Collect user activity detection state.
     * Scaffold: returns "unknown" until Google Activity Recognition
     * API is integrated (requires play-services-location dependency).
     */
    private fun collectActivityData(): JSONObject {
        // Activity Recognition API requires play-services-location.
        // This is a scaffold that returns the detected activity type
        // once the dependency and permission are added.
        return JSONObject().apply {
            put("type", "unknown")
            put("confidence", 0)
            put("note", "Activity Recognition API integration pending")
        }
    }

    fun disconnect() {
        stopSensorStreaming()
        shouldReconnect = false
        reconnectHandler.removeCallbacksAndMessages(null)
        webSocket?.close(1000, "Client disconnect")
        webSocket = null
        clawInstance?.disconnect()
        clawInstance = null
    }

    companion object {
        private const val PREF_USER_ID = "nclaw_user_id"
        private const val PREF_DEVICE_ID = "nclaw_device_id"
        private const val RECONNECT_INITIAL_DELAY = 1000L
        private const val RECONNECT_MAX_DELAY = 30000L
        private const val SENSOR_DEFAULT_INTERVAL = 60_000L
    }
}

class ClawException(message: String) : Exception(message)
