package com.example.fintrack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val eventChannelName = "com.example.fintrack/transactions"
    private val methodChannelName = "com.example.fintrack/methods"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleCategorizeIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleCategorizeIntent(intent)
    }

    /**
     * "Other" on the categorize notification (and taps on the notification
     * body) land here. The request travels through CaptureBus like every
     * other event: live over the EventChannel if Dart is listening, otherwise
     * buffered and drained on startup — so it works whether the tap launched
     * the app cold or just brought it forward. Dart routes it to the existing
     * in-app categorize bottom sheet (free-text entry).
     */
    private fun handleCategorizeIntent(intent: Intent?) {
        val txKey = intent?.getIntExtra(
            CategorizeNotification.EXTRA_OPEN_CATEGORIZE_TX, -1
        ) ?: -1
        if (txKey < 0) return
        // Consume so a config change doesn't re-fire it.
        intent?.removeExtra(CategorizeNotification.EXTRA_OPEN_CATEGORIZE_TX)

        val notifId = intent?.getIntExtra(CategorizeNotification.EXTRA_NOTIF_ID, -1) ?: -1
        if (notifId >= 0) {
            androidx.core.app.NotificationManagerCompat.from(this).cancel(notifId)
        }

        CaptureBus.dispatch(
            applicationContext,
            mapOf(
                "type" to "categorizeAction",
                "action" to "open",
                "txKey" to txKey.toString()
            )
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Live event stream. Note: NO dynamic registerReceiver() here anymore.
        // The manifest-declared SmsReceiver + NotificationListenerService feed
        // CaptureBus, which streams live when this sink is attached and
        // buffers to disk when it isn't. (The old dynamic registration crashed
        // on Android 14 — targetSdk 34 requires RECEIVER_EXPORTED flags — and
        // duplicated every SMS while the app was open.)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    CaptureBus.sink = events
                }

                override fun onCancel(arguments: Any?) {
                    CaptureBus.sink = null
                }
            })

        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "drainPendingTransactions" -> {
                        result.success(CaptureBus.drainPending(applicationContext))
                    }
                    "isNotificationAccessGranted" -> {
                        result.success(isNotificationAccessGranted())
                    }
                    "openNotificationAccessSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "showNotification" -> {
                        val title = call.argument<String>("title") ?: ""
                        val body = call.argument<String>("body") ?: ""
                        showLocalNotification(title, body)
                        result.success(true)
                    }
                    "cancelCategorizeNotification" -> {
                        // The user categorized in-app while the notification
                        // was still showing — remove the stale notification.
                        val txKey = call.argument<Int>("txKey")
                        if (txKey != null) {
                            androidx.core.app.NotificationManagerCompat
                                .from(this).cancel(txKey)
                        }
                        result.success(true)
                    }
                    "showCategorizeNotification" -> {
                        // Posted by Dart right after an uncategorized transaction
                        // is saved to Hive. txKey is the Hive auto-increment key,
                        // which the notification buttons echo back so the action
                        // can be applied to the exact same record.
                        val txKey = call.argument<Int>("txKey")
                        if (txKey == null) {
                            result.success(false)
                        } else {
                            CategorizeNotification.show(
                                context = applicationContext,
                                txKey = txKey,
                                amount = call.argument<Double>("amount") ?: 0.0,
                                payee = call.argument<String>("payee") ?: "Unknown",
                                sourceLabel = call.argument<String>("sourceLabel") ?: "",
                                timeLabel = call.argument<String>("timeLabel") ?: "",
                                quickPicks = call.argument<List<String>>("quickPicks")
                                    ?: emptyList(),
                                categories = call.argument<List<String>>("categories")
                                    ?: emptyList()
                            )
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Transaction Alerts"
            val descriptionText = "Notifications for captured transactions"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel("fintrack_alerts", name, importance).apply {
                description = descriptionText
            }
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
        // High-importance channel for the rich categorize notification.
        CategorizeNotification.ensureChannel(this)
    }

    private fun showLocalNotification(title: String, body: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent: PendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, "fintrack_alerts")
            .setSmallIcon(applicationContext.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText(body)
                .setBigContentTitle(title))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setTimeoutAfter(5000)  // Stay visible for 5 seconds
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(System.currentTimeMillis().toInt(), builder.build())
    }

    private fun isNotificationAccessGranted(): Boolean {
        val cn = ComponentName(this, TransactionNotificationService::class.java)
        val flat = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return flat.split(":").any {
            ComponentName.unflattenFromString(it) == cn ||
                it.contains(packageName)
        }
    }
}
