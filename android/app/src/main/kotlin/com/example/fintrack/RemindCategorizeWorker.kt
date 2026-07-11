package com.example.fintrack

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * One-off delayed task scheduled by CategorizeActionReceiver when the user
 * taps "Remind Me Later" — re-posts the exact same categorize notification.
 */
class RemindCategorizeWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {

    override fun doWork(): Result {
        val txKey = inputData.getInt(CategorizeNotification.EXTRA_TX_KEY, -1)
        if (txKey < 0) return Result.failure()

        CategorizeNotification.show(
            context = applicationContext,
            txKey = txKey,
            amount = inputData.getDouble(CategorizeNotification.EXTRA_AMOUNT, 0.0),
            payee = inputData.getString(CategorizeNotification.EXTRA_PAYEE) ?: "Unknown",
            sourceLabel = inputData.getString(CategorizeNotification.EXTRA_SOURCE_LABEL) ?: "",
            timeLabel = inputData.getString(CategorizeNotification.EXTRA_TIME_LABEL) ?: "",
            quickPicks = inputData.getStringArray(CategorizeNotification.EXTRA_QUICK_PICKS)
                ?.toList() ?: emptyList(),
            categories = inputData.getStringArray(CategorizeNotification.EXTRA_CATEGORIES)
                ?.toList() ?: emptyList()
        )
        return Result.success()
    }
}
