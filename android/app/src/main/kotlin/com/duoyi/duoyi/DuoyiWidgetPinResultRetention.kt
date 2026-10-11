package com.duoyi.duoyi

import java.util.UUID

/** Process-local consumers are protected; only unattended receipts use the cache budget. */
class DuoyiWidgetPinResultRetention(
    private val orphanLimit: Int = 64,
    private val nowMillis: () -> Long = { System.nanoTime() / 1_000_000L },
) {
    private data class Wait(val requestId: String, val owner: String)

    private val handoffs = mutableMapOf<String, Long>()
    private val waits = mutableMapOf<String, Wait>()
    private val arrivalOrder = linkedSetOf<String>()
    private var lastNow: Long? = null

    init {
        require(orphanLimit > 0)
    }

    internal fun reserveHandoff(requestId: String, durationMillis: Long) {
        val now = now()
        val duration = durationMillis.coerceAtLeast(0L)
        handoffs[requestId] = if (now > Long.MAX_VALUE - duration) Long.MAX_VALUE else now + duration
    }

    internal fun releaseHandoff(requestId: String) {
        handoffs.remove(requestId)
    }

    internal fun beginWait(requestId: String, owner: String): String {
        handoffs.remove(requestId)
        return UUID.randomUUID().toString().also { waits[it] = Wait(requestId, owner) }
    }

    internal fun endWait(requestId: String, owner: String, token: String) {
        if (waits[token] == Wait(requestId, owner)) waits.remove(token)
    }

    internal fun releaseOwner(owner: String) {
        waits.entries.removeAll { it.value.owner == owner }
    }

    internal fun evictions(values: Map<String, *>, incoming: String? = null): List<String> {
        expireHandoffs()
        val existing = DuoyiWidgetPinResultCore.namespaceIds(values)
        arrivalOrder.retainAll(existing)
        // A new process has no surviving Dart waiter. Seed persisted receipts in a
        // deterministic order; timestamps decide ordering here, never expiration.
        (existing - arrivalOrder).sortedWith(
            compareBy<String> {
                values[DuoyiWidgetPinResultCore.keysFor(it).getValue("confirmedAt")] as? Long
                    ?: Long.MIN_VALUE
            }.thenBy { it },
        ).forEach { arrivalOrder.add(it) }
        if (incoming != null && incoming in existing) {
            arrivalOrder.remove(incoming)
            arrivalOrder.add(incoming)
        }
        val protected = handoffs.keys + waits.values.map { it.requestId }
        val unattended = arrivalOrder.filter { it !in protected }
        return unattended.filter { it != incoming }.take((unattended.size - orphanLimit).coerceAtLeast(0))
    }

    internal fun forgetReceipts(requestIds: Collection<String>) {
        arrivalOrder.removeAll(requestIds.toSet())
    }

    internal fun nextCleanupDelayMillis(): Long? {
        val now = now()
        val next = handoffs.values.minOrNull() ?: return null
        return try {
            Math.subtractExact(next, now).coerceAtLeast(0L)
        } catch (_: ArithmeticException) {
            Long.MAX_VALUE
        }
    }

    private fun expireHandoffs(): Long {
        val now = now()
        handoffs.entries.removeAll { it.value <= now }
        return now
    }

    private fun now(): Long = nowMillis().let { measured ->
        val result = lastNow?.let { maxOf(it, measured) } ?: measured
        lastNow = result
        result
    }
}
