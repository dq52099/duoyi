package com.duoyi.duoyi

import android.content.SharedPreferences

/** Receipts remain readable until their requesting UI explicitly clears them. */
class DuoyiWidgetPinResultStore(private val preferences: SharedPreferences) {
    fun record(result: DuoyiWidgetPinResultCore.Record) {
        if (result.requestId.isBlank()) return
        synchronized(lock) {
            val keys = DuoyiWidgetPinResultCore.keysFor(result.requestId)
            preferences.edit()
                .putString(keys.getValue("requestId"), result.requestId)
                .putString(keys.getValue("kind"), result.kind)
                .putString(keys.getValue("style"), result.style)
                .putInt(keys.getValue("widgetId"), result.widgetId)
                .putString(keys.getValue("status"), result.status)
                .putLong(keys.getValue("confirmedAt"), result.confirmedAt)
                .apply()
        }
    }

    fun read(requestId: String): Map<String, Any>? {
        if (requestId.isBlank()) return null
        return synchronized(lock) {
            DuoyiWidgetPinResultCore.read(preferences.all, requestId)?.toPayload()
        }
    }

    fun clear(requestId: String) {
        if (requestId.isBlank()) return
        synchronized(lock) {
            val editor = preferences.edit()
            DuoyiWidgetPinResultCore.keysFor(requestId).values.forEach { editor.remove(it) }
            val legacyKeys = DuoyiWidgetPinResultCore.legacyKeys
            if (preferences.all[legacyKeys.getValue("requestId")] == requestId) {
                legacyKeys.values.forEach { editor.remove(it) }
            }
            editor.apply()
        }
    }

    companion object {
        private val lock = Any()
    }
}
