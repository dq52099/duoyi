package com.duoyi.duoyi

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max

data class LocationGeofenceReminder(
    val id: String,
    val title: String,
    val note: String?,
    val latitude: Double,
    val longitude: Double,
    val radiusMeters: Float,
    val trigger: String,
    val oneShot: Boolean,
    val linkedType: String?,
    val linkedId: String?,
)

object LocationGeofenceScheduler {
    private const val tag = "DuoyiGeofence"
    private const val prefsName = "duoyi_location_geofences"
    private const val metadataKey = "metadata_json"
    private const val requestCode = 57219

    fun parseReminder(raw: Map<*, *>): LocationGeofenceReminder? {
        val id = raw["id"]?.toString()?.trim().orEmpty()
        if (id.isEmpty()) return null
        val latitude = (raw["latitude"] as? Number)?.toDouble() ?: return null
        val longitude = (raw["longitude"] as? Number)?.toDouble() ?: return null
        val radius = (raw["radiusMeters"] as? Number)?.toFloat() ?: 100f
        return LocationGeofenceReminder(
            id = id,
            title = raw["title"]?.toString()?.ifBlank { "位置提醒" } ?: "位置提醒",
            note = raw["note"]?.toString()?.takeIf { it.isNotBlank() },
            latitude = latitude,
            longitude = longitude,
            radiusMeters = max(50f, radius),
            trigger = raw["trigger"]?.toString()?.ifBlank { "enter" } ?: "enter",
            oneShot = raw["oneShot"] == true,
            linkedType = raw["linkedType"]?.toString()?.takeIf { it.isNotBlank() },
            linkedId = raw["linkedId"]?.toString()?.takeIf { it.isNotBlank() },
        )
    }

    fun syncReminders(
        context: Context,
        reminders: List<LocationGeofenceReminder>,
        onResult: (Map<String, Any?>) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        val previous = allMetadata(context)
        if (!hasRequiredPermission(context)) {
            clearRegisteredGeofences(context) {
                onResult(
                    mapOf(
                        "available" to false,
                        "scheduledCount" to 0,
                        "status" to "permission_missing",
                        "message" to "需要精确位置和后台位置权限后才能注册系统 geofence",
                    ),
                )
            }
            return
        }

        clearRegisteredGeofences(context) {
            if (reminders.isEmpty()) {
                remember(context, emptyList())
                onResult(
                    mapOf(
                        "available" to true,
                        "scheduledCount" to 0,
                        "status" to "empty",
                    ),
                )
                return@clearRegisteredGeofences
            }
            addGeofences(
                context,
                reminders,
                onSuccess = {
                    remember(context, reminders)
                    onResult(
                        mapOf(
                            "available" to true,
                            "scheduledCount" to reminders.size,
                            "status" to "scheduled",
                        ),
                    )
                },
                onFailure = { code, message ->
                    remember(context, previous)
                    if (previous.isNotEmpty()) {
                        addGeofences(
                            context,
                            previous,
                            onSuccess = {
                                Log.w(tag, "restored previous geofences after sync failure")
                            },
                            onFailure = { restoreCode, restoreMessage ->
                                Log.w(
                                    tag,
                                    "failed to restore previous geofences: $restoreCode $restoreMessage",
                                )
                            },
                        )
                    }
                    onError(code, message)
                },
            )
        }
    }

    fun clearReminders(context: Context, onResult: (Map<String, Any?>) -> Unit) {
        remember(context, emptyList())
        clearRegisteredGeofences(context) {
            onResult(
                mapOf(
                    "available" to hasRequiredPermission(context),
                    "scheduledCount" to 0,
                    "status" to "cleared",
                ),
            )
        }
    }

    fun metadataFor(context: Context, id: String): LocationGeofenceReminder? {
        return allMetadata(context).firstOrNull { it.id == id }
    }

    fun removeOneShot(context: Context, id: String) {
        val next = allMetadata(context).filterNot { it.id == id }
        remember(context, next)
        geofencingClient(context).removeGeofences(listOf(id))
    }

    fun restoreRemembered(context: Context) {
        val remembered = allMetadata(context)
        if (remembered.isEmpty()) return
        if (!hasRequiredPermission(context)) {
            Log.w(tag, "skip geofence restore because location permission is missing")
            return
        }
        clearRegisteredGeofences(context) {
            addGeofences(
                context,
                remembered,
                onSuccess = {
                    Log.i(tag, "restored ${remembered.size} remembered geofences")
                },
                onFailure = { code, message ->
                    Log.w(tag, "remembered geofence restore failed: $code $message")
                },
            )
        }
    }

    private fun allMetadata(context: Context): List<LocationGeofenceReminder> {
        val raw = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString(metadataKey, "[]")
            ?: "[]"
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { i ->
                val item = array.getJSONObject(i)
                LocationGeofenceReminder(
                    id = item.getString("id"),
                    title = item.optString("title", "位置提醒"),
                    note = item.optString("note").takeIf { it.isNotBlank() },
                    latitude = item.getDouble("latitude"),
                    longitude = item.getDouble("longitude"),
                    radiusMeters = item.optDouble("radiusMeters", 100.0).toFloat(),
                    trigger = item.optString("trigger", "enter"),
                    oneShot = item.optBoolean("oneShot", false),
                    linkedType = item.optString("linkedType").takeIf { it.isNotBlank() },
                    linkedId = item.optString("linkedId").takeIf { it.isNotBlank() },
                )
            }
        }.getOrElse { emptyList() }
    }

    private fun remember(context: Context, reminders: List<LocationGeofenceReminder>) {
        val array = JSONArray()
        reminders.forEach { r ->
            array.put(
                JSONObject()
                    .put("id", r.id)
                    .put("title", r.title)
                    .put("note", r.note)
                    .put("latitude", r.latitude)
                    .put("longitude", r.longitude)
                    .put("radiusMeters", r.radiusMeters.toDouble())
                    .put("trigger", r.trigger)
                    .put("oneShot", r.oneShot)
                    .put("linkedType", r.linkedType)
                    .put("linkedId", r.linkedId),
            )
        }
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(metadataKey, array.toString())
            .apply()
    }

    @SuppressLint("MissingPermission")
    private fun addGeofences(
        context: Context,
        reminders: List<LocationGeofenceReminder>,
        onSuccess: () -> Unit,
        onFailure: (String, String) -> Unit,
    ) {
        val request = GeofencingRequest.Builder()
            .setInitialTrigger(0)
            .addGeofences(reminders.map { it.toGeofence() })
            .build()
        geofencingClient(context).addGeofences(request, pendingIntent(context))
            .addOnSuccessListener { onSuccess() }
            .addOnFailureListener { e ->
                onFailure("geofence_add_failed", e.message ?: "注册 geofence 失败")
            }
    }

    private fun LocationGeofenceReminder.toGeofence(): Geofence {
        val transition = if (trigger == "leave") {
            Geofence.GEOFENCE_TRANSITION_EXIT
        } else {
            Geofence.GEOFENCE_TRANSITION_ENTER
        }
        return Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(latitude, longitude, radiusMeters)
            .setTransitionTypes(transition)
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .build()
    }

    private fun clearRegisteredGeofences(context: Context, onDone: () -> Unit) {
        geofencingClient(context).removeGeofences(pendingIntent(context))
            .addOnCompleteListener { onDone() }
    }

    private fun hasRequiredPermission(context: Context): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val background = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
        return (fine || coarse) && background
    }

    private fun geofencingClient(context: Context): GeofencingClient {
        return LocationServices.getGeofencingClient(context.applicationContext)
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, LocationGeofenceReceiver::class.java)
        val mutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag,
        )
    }
}
