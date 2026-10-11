package com.duoyi.duoyi

import java.util.UUID

data class DuoyiWidgetLaunchDelivery(val id: String, val uri: String) {
    fun payload(): Map<String, String> = mapOf("id" to id, "uri" to uri)
}

/** Retains each received tap until the Dart launch stream acknowledges it. */
class DuoyiWidgetLaunchQueue(
    private val maxPending: Int = 256,
    private val newId: () -> String = { UUID.randomUUID().toString() },
) {
    private val pending = linkedMapOf<String, DuoyiWidgetLaunchDelivery>()

    fun receive(buildUri: (String) -> String): DuoyiWidgetLaunchDelivery? {
        // Reject the newest overflow, retaining every already accepted tap.
        if (pending.size >= maxPending) return null
        val id = newId()
        return DuoyiWidgetLaunchDelivery(id, buildUri(id)).also { pending[id] = it }
    }

    fun snapshot(): List<DuoyiWidgetLaunchDelivery> = pending.values.toList()

    fun acknowledge(id: String) {
        pending.remove(id)
    }
}
