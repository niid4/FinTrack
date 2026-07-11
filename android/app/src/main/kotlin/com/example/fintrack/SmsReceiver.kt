package com.example.fintrack

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Manifest-registered receiver — fires even when the app is closed.
 * Events go through CaptureBus: streamed live if Flutter is listening,
 * otherwise buffered and drained on next app launch.
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) return
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return

        // Multipart SMS arrive as several PDUs from the same sender — join them
        // so amount/merchant parsing sees the full message.
        val bySender = LinkedHashMap<String, StringBuilder>()
        for (sms in messages) {
            val sender = sms.displayOriginatingAddress ?: ""
            val body = sms.displayMessageBody ?: continue
            bySender.getOrPut(sender) { StringBuilder() }.append(body)
        }

        for ((sender, bodyBuilder) in bySender) {
            val body = bodyBuilder.toString()
            if (CaptureBus.looksLikeTransaction(body)) {
                CaptureBus.dispatch(
                    context,
                    mapOf(
                        "source" to "sms",
                        "sender" to sender,
                        "text" to body
                    )
                )
            }
        }
    }
}
