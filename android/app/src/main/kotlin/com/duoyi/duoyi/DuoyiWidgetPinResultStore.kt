package com.duoyi.duoyi

import android.content.SharedPreferences

/** Active consumers retain their receipts; unattended storage has a bounded budget. */
class DuoyiWidgetPinResultStore(
    private val preferences: SharedPreferences,
    private val retention: DuoyiWidgetPinResultRetention = DuoyiWidgetPinResultRetention(),
) {
    fun record(result: DuoyiWidgetPinResultCore.Record) {
        if (result.requestId.isBlank()) return
        synchronized(lock) {
            val keys = DuoyiWidgetPinResultCore.keysFor(result.requestId)
            val projected = mutableMapOf<String, Any?>().apply { putAll(preferences.all) }
            result.toPayload().forEach { (field, value) -> projected[keys.getValue(field)] = value }
            val evicted = retention.evictions(projected, incoming = result.requestId)
            val editor = preferences.edit()
                .putString(keys.getValue("requestId"), result.requestId)
                .putString(keys.getValue("kind"), result.kind)
                .putString(keys.getValue("style"), result.style)
                .putInt(keys.getValue("widgetId"), result.widgetId)
                .putString(keys.getValue("status"), result.status)
                .putLong(keys.getValue("confirmedAt"), result.confirmedAt)
            removeReceipts(editor, evicted)
            editor.apply()
            retention.forgetReceipts(evicted)
        }
    }

    fun read(requestId: String): Map<String, Any>? {
        if (requestId.isBlank()) return null
        return synchronized(lock) {
            pruneLocked()
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
            retention.forgetReceipts(listOf(requestId))
            retention.releaseHandoff(requestId)
            pruneLocked()
        }
    }

    fun reserveHandoff(requestId: String, durationMillis: Long = 120_000L) {
        if (requestId.isBlank()) return
        synchronized(lock) {
            retention.reserveHandoff(requestId, durationMillis)
            pruneLocked()
        }
    }

    fun releaseHandoff(requestId: String) {
        synchronized(lock) {
            retention.releaseHandoff(requestId)
            pruneLocked()
        }
    }

    fun beginWait(requestId: String, owner: String, timeoutMillis: Long): String? {
        if (requestId.isBlank() || owner.isBlank() || timeoutMillis <= 0L) return null
        return synchronized(lock) {
            retention.beginWait(requestId, owner).also { pruneLocked() }
        }
    }

    fun endWait(requestId: String, owner: String, token: String) {
        synchronized(lock) {
            retention.endWait(requestId, owner, token)
            pruneLocked()
        }
    }

    fun releaseOwner(owner: String) {
        synchronized(lock) {
            retention.releaseOwner(owner)
            pruneLocked()
        }
    }

    fun prune() = synchronized(lock) { pruneLocked() }

    fun nextCleanupDelayMillis(): Long? = synchronized(lock) { retention.nextCleanupDelayMillis() }

    private fun pruneLocked() {
        val evicted = retention.evictions(preferences.all)
        if (evicted.isEmpty()) return
        val editor = preferences.edit()
        removeReceipts(editor, evicted)
        editor.apply()
        retention.forgetReceipts(evicted)
    }

    private fun removeReceipts(editor: SharedPreferences.Editor, requestIds: Collection<String>) {
        requestIds.forEach { id ->
            DuoyiWidgetPinResultCore.keysFor(id).values.forEach { editor.remove(it) }
        }
    }

    companion object {
        private val lock = Any()
    }
}
