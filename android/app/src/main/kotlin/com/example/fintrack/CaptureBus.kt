package com.example.fintrack

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Single funnel for captured transaction events (SMS + notifications).
 *
 * - If the Flutter engine is alive and listening, the event is streamed
 *   live over the EventChannel.
 * - If the app is closed / engine not listening, the event is persisted to
 *   SharedPreferences and drained by Dart on next launch via MethodChannel.
 *
 * This replaces the old design where MainActivity dynamically registered a
 * second SmsReceiver (which crashed on Android 14 due to the missing
 * RECEIVER_EXPORTED flag, and double-captured every SMS while the app was
 * open, and lost every event while the app was closed).
 */
object CaptureBus {
    private const val PREFS = "fintrack_capture"
    private const val KEY_PENDING = "pending_events"
    private const val MAX_PENDING = 200

    @Volatile
    var sink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun dispatch(context: Context, event: Map<String, String>) {
        val currentSink = sink
        if (currentSink != null) {
            // EventSink must be called on the platform main thread.
            mainHandler.post {
                try {
                    sink?.success(event)
                } catch (_: Exception) {
                    persist(context, event)
                }
            }
        } else {
            persist(context, event)
        }
    }

    @Synchronized
    private fun persist(context: Context, event: Map<String, String>) {
        try {
            val prefs = context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString(KEY_PENDING, "[]") ?: "[]")
            val obj = JSONObject()
            for ((k, v) in event) obj.put(k, v)
            obj.put("capturedAt", System.currentTimeMillis())
            arr.put(obj)

            // Trim oldest if the buffer grows unreasonably.
            val trimmed = if (arr.length() > MAX_PENDING) {
                val t = JSONArray()
                for (i in (arr.length() - MAX_PENDING) until arr.length()) {
                    t.put(arr.get(i))
                }
                t
            } else arr

            prefs.edit().putString(KEY_PENDING, trimmed.toString()).apply()
        } catch (_: Exception) {
            // Never crash the receiver/service over buffering.
        }
    }

    /** Returns all buffered events as a List<Map> and clears the buffer. */
    @Synchronized
    fun drainPending(context: Context): List<Map<String, Any>> {
        val prefs = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING, "[]") ?: "[]"
        prefs.edit().putString(KEY_PENDING, "[]").apply()

        val out = mutableListOf<Map<String, Any>>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val map = mutableMapOf<String, Any>()
                for (key in obj.keys()) map[key] = obj.get(key)
                out.add(map)
            }
        } catch (_: Exception) {
        }
        return out
    }

    /**
     * Broad pre-filter for "does this look like a money message".
     * Precise parsing happens in Dart — this just keeps obvious noise out.
     */
    fun looksLikeTransaction(text: String): Boolean {
        val t = text.lowercase()
        val hasCurrency = t.contains("rs.") || t.contains("rs ") ||
            t.contains("inr") || t.contains("₹")
        val hasAction = t.contains("debited") || t.contains("credited") ||
            t.contains("paid") || t.contains("sent") || t.contains("spent") ||
            t.contains("received") || t.contains("withdrawn") ||
            t.contains("transferred") || t.contains("payment")
        return hasCurrency && hasAction
    }
}
