package com.example.fintrack

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Handles every button on the categorize notification.
 *
 * Category pills / Skip: the chosen action is dispatched through CaptureBus —
 * the same live-or-buffered funnel the SMS/notification capture path uses.
 * If the Flutter engine is alive (app foreground OR backgrounded), the event
 * streams over the existing EventChannel and Dart writes the category via
 * HiveService.saveTransaction() — the exact save path TransactionCaptureService
 * uses — without the app ever coming to the foreground. If the process is dead,
 * the action is persisted and drained over the MethodChannel on next launch
 * (identical to how captured transactions already survive the app being closed;
 * spinning up a second Hive-writing engine from a receiver would risk
 * corrupting the boxes the main isolate owns).
 *
 * Remind Me Later: cancels the notification and schedules a one-off
 * WorkManager task (RemindCategorizeWorker) to re-post it after a delay.
 */
class CategorizeActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        val txKey = intent.getIntExtra(CategorizeNotification.EXTRA_TX_KEY, -1)
        val notifId = intent.getIntExtra(CategorizeNotification.EXTRA_NOTIF_ID, -1)
        if (txKey < 0) return

        when (intent.action) {
            CategorizeNotification.ACTION_SET_CATEGORY -> {
                val category =
                    intent.getStringExtra(CategorizeNotification.EXTRA_CATEGORY) ?: return
                CaptureBus.dispatch(
                    context,
                    mapOf(
                        "type" to "categorizeAction",
                        "action" to "setCategory",
                        "txKey" to txKey.toString(),
                        "category" to category
                    )
                )
                cancel(context, notifId)
            }

            CategorizeNotification.ACTION_SKIP -> {
                CaptureBus.dispatch(
                    context,
                    mapOf(
                        "type" to "categorizeAction",
                        "action" to "skip",
                        "txKey" to txKey.toString()
                    )
                )
                cancel(context, notifId)
            }

            CategorizeNotification.ACTION_REMIND -> {
                cancel(context, notifId)

                val data = Data.Builder()
                    .putInt(CategorizeNotification.EXTRA_TX_KEY, txKey)
                    .putDouble(
                        CategorizeNotification.EXTRA_AMOUNT,
                        intent.getDoubleExtra(CategorizeNotification.EXTRA_AMOUNT, 0.0)
                    )
                    .putString(
                        CategorizeNotification.EXTRA_PAYEE,
                        intent.getStringExtra(CategorizeNotification.EXTRA_PAYEE) ?: ""
                    )
                    .putString(
                        CategorizeNotification.EXTRA_SOURCE_LABEL,
                        intent.getStringExtra(CategorizeNotification.EXTRA_SOURCE_LABEL) ?: ""
                    )
                    .putString(
                        CategorizeNotification.EXTRA_TIME_LABEL,
                        intent.getStringExtra(CategorizeNotification.EXTRA_TIME_LABEL) ?: ""
                    )
                    .putStringArray(
                        CategorizeNotification.EXTRA_QUICK_PICKS,
                        intent.getStringArrayExtra(CategorizeNotification.EXTRA_QUICK_PICKS)
                            ?: emptyArray()
                    )
                    .putStringArray(
                        CategorizeNotification.EXTRA_CATEGORIES,
                        intent.getStringArrayExtra(CategorizeNotification.EXTRA_CATEGORIES)
                            ?: emptyArray()
                    )
                    .build()

                val request = OneTimeWorkRequestBuilder<RemindCategorizeWorker>()
                    .setInitialDelay(REMIND_DELAY_MINUTES, TimeUnit.MINUTES)
                    .setInputData(data)
                    .build()

                WorkManager.getInstance(context.applicationContext)
                    .enqueue(request)
            }
        }
    }

    private fun cancel(context: Context, notifId: Int) {
        if (notifId >= 0) {
            NotificationManagerCompat.from(context).cancel(notifId)
        }
    }

    companion object {
        const val REMIND_DELAY_MINUTES = 15L
    }
}
