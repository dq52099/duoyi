package com.duoyi.duoyi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class ReminderRingtoneReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val title = intent.getStringExtra("title") ?: "多仪提醒"
        val body = intent.getStringExtra("body") ?: "提醒时间到了"
        val payload = intent.getStringExtra("payload")

        val serviceIntent = ReminderRingtoneService.intent(context, id, title, body, payload)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        if (intent.getBooleanExtra("repeat", false)) {
            ReminderRingtoneScheduler.rescheduleFromReceiver(context, intent)
        }
    }
}
