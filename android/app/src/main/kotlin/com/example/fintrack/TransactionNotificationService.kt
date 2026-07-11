package com.example.fintrack

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class TransactionNotificationService : NotificationListenerService() {

    // Notifications from SMS apps mirror messages the SmsReceiver already
    // captures — skip them here so transactions aren't recorded twice.
    // (Dart also de-duplicates by amount + time as a safety net.)
    private val smsAppPackages = setOf(
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging",
        "com.android.mms",
        "com.oneplus.mms",
        "com.miui.smsextra"
    )

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        val pkg = n.packageName ?: return

        if (pkg == packageName) return          // ignore our own notifications
        if (pkg in smsAppPackages) return       // SmsReceiver handles these
        if (n.isOngoing) return                 // media/persistent notifications

        val extras = n.notification?.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString() ?: ""
        val text = extras.getCharSequence("android.text")?.toString()
            ?: extras.getCharSequence("android.bigText")?.toString()
            ?: ""
        if (text.isBlank()) return

        val combined = "$title $text"
        if (CaptureBus.looksLikeTransaction(combined)) {
            CaptureBus.dispatch(
                applicationContext,
                mapOf(
                    "source" to "notification",
                    "package" to pkg,
                    "title" to title,
                    "text" to text
                )
            )
        }
    }
}
