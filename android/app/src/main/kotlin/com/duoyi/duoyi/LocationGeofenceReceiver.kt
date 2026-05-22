package com.duoyi.duoyi

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import kotlin.math.abs

class LocationGeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return
        val transition = event.geofenceTransition
        if (
            transition != Geofence.GEOFENCE_TRANSITION_ENTER &&
            transition != Geofence.GEOFENCE_TRANSITION_EXIT
        ) {
            return
        }

        createChannel(context)
        event.triggeringGeofences.orEmpty().forEach { geofence ->
            val reminder = LocationGeofenceScheduler.metadataFor(
                context,
                geofence.requestId,
            ) ?: return@forEach
            showNotification(context, reminder, transition)
            if (reminder.oneShot) {
                LocationGeofenceScheduler.removeOneShot(context, reminder.id)
            }
        }
    }

    private fun showNotification(
        context: Context,
        reminder: LocationGeofenceReminder,
        transition: Int,
    ) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val title = "位置提醒：${reminder.title}"
        val direction = if (transition == Geofence.GEOFENCE_TRANSITION_EXIT) {
            "已离开提醒范围"
        } else {
            "已到达提醒范围"
        }
        val body = listOf(direction, reminder.note.orEmpty())
            .filter { it.isNotBlank() }
            .joinToString(" · ")
        val contentIntent = PendingIntent.getActivity(
            context,
            abs(reminder.id.hashCode()),
            Intent(Intent.ACTION_VIEW, payloadUri(reminder))
                .setPackage(context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
        NotificationManagerCompat.from(context).notify(
            abs("location_${reminder.id}".hashCode()),
            notification,
        )
    }

    private fun payloadUri(reminder: LocationGeofenceReminder): Uri {
        val linkedType = reminder.linkedType
        val linkedId = reminder.linkedId
        if (!linkedType.isNullOrBlank() && !linkedId.isNullOrBlank()) {
            if (linkedType == "todo") return Uri.parse("duoyi://todo/$linkedId")
            if (linkedType == "goal") return Uri.parse("duoyi://goal/$linkedId")
        }
        return Uri.parse("duoyi://location/${reminder.id}")
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            channelId,
            "多仪位置提醒",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "到达或离开指定地点时发出提醒"
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val channelId = "duoyi_location_geofence_v1"
    }
}
