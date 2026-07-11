package com.example.fintrack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Builds and posts the rich "categorize this transaction" heads-up
 * notification (custom RemoteViews + DecoratedCustomViewStyle).
 *
 * Called from two places:
 *  - MainActivity's MethodChannel handler ("showCategorizeNotification"),
 *    invoked by Dart right after TransactionCaptureService saves an
 *    uncategorized transaction.
 *  - RemindCategorizeWorker, which re-posts the same notification after the
 *    user taps "Remind Me Later".
 *
 * Every button routes through a PendingIntent:
 *  - category pills + Skip  -> CategorizeActionReceiver (BroadcastReceiver)
 *  - Remind Me Later        -> CategorizeActionReceiver -> WorkManager delay
 *  - Other                  -> opens MainActivity into the in-app categorize
 *                              flow (free-text entry doesn't fit RemoteViews)
 */
object CategorizeNotification {

    const val CHANNEL_ID = "fintrack_categorize"

    // Intent actions / extras shared with CategorizeActionReceiver + MainActivity.
    const val ACTION_SET_CATEGORY = "com.example.fintrack.ACTION_SET_CATEGORY"
    const val ACTION_SKIP = "com.example.fintrack.ACTION_SKIP"
    const val ACTION_REMIND = "com.example.fintrack.ACTION_REMIND"

    const val EXTRA_TX_KEY = "tx_key"
    const val EXTRA_CATEGORY = "category"
    const val EXTRA_NOTIF_ID = "notif_id"
    const val EXTRA_AMOUNT = "amount"
    const val EXTRA_PAYEE = "payee"
    const val EXTRA_SOURCE_LABEL = "source_label"
    const val EXTRA_TIME_LABEL = "time_label"
    const val EXTRA_QUICK_PICKS = "quick_picks"
    const val EXTRA_CATEGORIES = "categories"
    const val EXTRA_OPEN_CATEGORIZE_TX = "open_categorize_tx"

    // 4 slots per row — hard RemoteViews cap, no dynamic wrapping.
    private val QUICK_PICK_IDS = intArrayOf(
        R.id.quick_pick_1, R.id.quick_pick_2, R.id.quick_pick_3, R.id.quick_pick_4
    )
    private val CATEGORY_IDS = intArrayOf(
        R.id.category_1, R.id.category_2, R.id.category_3, R.id.category_4
    )

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Categorize Transactions",
                NotificationManager.IMPORTANCE_HIGH // heads-up banner
            ).apply {
                description = "Quick-categorize captured transactions"
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    fun show(
        context: Context,
        txKey: Int,
        amount: Double,
        payee: String,
        sourceLabel: String,
        timeLabel: String,
        quickPicks: List<String>,
        categories: List<String>
    ) {
        ensureChannel(context)

        val notifId = txKey // one notification per transaction; stable for cancel/re-post

        val amountLabel =
            if (amount == amount.toLong().toDouble()) amount.toLong().toString()
            else String.format("%.2f", amount)
        val title = "₹$amountLabel to $payee"
        val subtitle = "$sourceLabel • just now"

        val collapsed = RemoteViews(context.packageName, R.layout.notification_categorize_collapsed)
        collapsed.setTextViewText(R.id.notif_title, title)
        collapsed.setTextViewText(R.id.notif_subtitle, subtitle)

        val expanded = RemoteViews(context.packageName, R.layout.notification_categorize_expanded)
        expanded.setTextViewText(R.id.notif_title, title)
        expanded.setTextViewText(R.id.notif_subtitle, subtitle)
        expanded.setTextViewText(R.id.notif_time, timeLabel)

        bindPillRow(context, expanded, QUICK_PICK_IDS, quickPicks, txKey, notifId, requestCodeBase = 10)
        bindPillRow(context, expanded, CATEGORY_IDS, categories, txKey, notifId, requestCodeBase = 20)

        // Skip
        expanded.setOnClickPendingIntent(
            R.id.action_skip,
            broadcastIntent(context, ACTION_SKIP, txKey, notifId, requestCode(txKey, 30))
        )

        // Remind Me Later — receiver schedules a WorkManager one-off re-post,
        // so the intent must carry everything needed to rebuild this notification.
        val remindIntent = Intent(context, CategorizeActionReceiver::class.java).apply {
            action = ACTION_REMIND
            putExtra(EXTRA_TX_KEY, txKey)
            putExtra(EXTRA_NOTIF_ID, notifId)
            putExtra(EXTRA_AMOUNT, amount)
            putExtra(EXTRA_PAYEE, payee)
            putExtra(EXTRA_SOURCE_LABEL, sourceLabel)
            putExtra(EXTRA_TIME_LABEL, timeLabel)
            putExtra(EXTRA_QUICK_PICKS, quickPicks.toTypedArray())
            putExtra(EXTRA_CATEGORIES, categories.toTypedArray())
        }
        expanded.setOnClickPendingIntent(
            R.id.action_remind,
            PendingIntent.getBroadcast(
                context, requestCode(txKey, 31), remindIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )

        // Other — free-text entry can't live in a RemoteViews, so open the app
        // straight into the existing in-app categorize flow for this tx.
        val otherIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_OPEN_CATEGORIZE_TX, txKey)
            putExtra(EXTRA_NOTIF_ID, notifId)
        }
        expanded.setOnClickPendingIntent(
            R.id.action_other,
            PendingIntent.getActivity(
                context, requestCode(txKey, 32), otherIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )

        // Tapping the notification body (outside a pill) also opens the app.
        val contentIntent = PendingIntent.getActivity(
            context, requestCode(txKey, 33),
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_OPEN_CATEGORIZE_TX, txKey)
                putExtra(EXTRA_NOTIF_ID, notifId)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setCustomHeadsUpContentView(expanded) // show the pills in the banner itself
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH) // heads-up pre-O
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false) // buttons decide when it goes away
            .build()

        try {
            NotificationManagerCompat.from(context).notify(notifId, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted — the in-app categorize bar is
            // the fallback path, so never crash here.
        }
    }

    private fun bindPillRow(
        context: Context,
        views: RemoteViews,
        slotIds: IntArray,
        labels: List<String>,
        txKey: Int,
        notifId: Int,
        requestCodeBase: Int
    ) {
        for (i in slotIds.indices) {
            val id = slotIds[i]
            val label = labels.getOrNull(i)
            if (label.isNullOrBlank()) {
                views.setViewVisibility(id, android.view.View.GONE)
                continue
            }
            views.setViewVisibility(id, android.view.View.VISIBLE)
            views.setTextViewText(id, label)
            val intent = Intent(context, CategorizeActionReceiver::class.java).apply {
                action = ACTION_SET_CATEGORY
                putExtra(EXTRA_TX_KEY, txKey)
                putExtra(EXTRA_NOTIF_ID, notifId)
                putExtra(EXTRA_CATEGORY, label)
            }
            views.setOnClickPendingIntent(
                id,
                PendingIntent.getBroadcast(
                    context, requestCode(txKey, requestCodeBase + i), intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        }
    }

    private fun broadcastIntent(
        context: Context,
        action: String,
        txKey: Int,
        notifId: Int,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(context, CategorizeActionReceiver::class.java).apply {
            this.action = action
            putExtra(EXTRA_TX_KEY, txKey)
            putExtra(EXTRA_NOTIF_ID, notifId)
        }
        return PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    /** Unique-per-(tx, button) request codes so PendingIntents don't collide. */
    private fun requestCode(txKey: Int, slot: Int): Int = txKey * 100 + slot
}
