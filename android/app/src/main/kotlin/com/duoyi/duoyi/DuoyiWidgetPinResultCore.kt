package com.duoyi.duoyi

/** Request-scoped pin receipts, with read compatibility for the former single slot. */
object DuoyiWidgetPinResultCore {
    data class Record(
        val requestId: String,
        val kind: String,
        val style: String,
        val widgetId: Int,
        val status: String,
        val confirmedAt: Long,
    ) {
        fun toPayload(): Map<String, Any> = mapOf(
            "requestId" to requestId,
            "kind" to kind,
            "style" to style,
            "widgetId" to widgetId,
            "status" to status,
            "confirmedAt" to confirmedAt,
        )
    }

    internal val legacyKeys = mapOf(
        "requestId" to "request_id",
        "kind" to "kind",
        "style" to "style",
        "widgetId" to "widget_id",
        "status" to "status",
        "confirmedAt" to "confirmed_at",
    )

    fun keysFor(requestId: String): Map<String, String> {
        if (requestId.isBlank()) return emptyMap()
        // Length-delimit the complete ID so even IDs containing separators stay distinct.
        val prefix = "receipt:${requestId.length}:$requestId:"
        return legacyKeys.mapValues { (_, field) -> prefix + field }
    }

    fun read(values: Map<String, *>, requestId: String): Record? {
        if (requestId.isBlank()) return null
        val keys = keysFor(requestId)
        completeRecord(values, keys, requestId)?.let { return it }
        if (values[legacyKeys.getValue("requestId")] != requestId) return null
        return Record(
            requestId = requestId,
            kind = values[legacyKeys.getValue("kind")] as? String ?: "",
            style = values[legacyKeys.getValue("style")] as? String ?: "",
            widgetId = values[legacyKeys.getValue("widgetId")] as? Int ?: 0,
            status = values[legacyKeys.getValue("status")] as? String ?: "",
            confirmedAt = values[legacyKeys.getValue("confirmedAt")] as? Long ?: 0L,
        )
    }

    private fun completeRecord(
        values: Map<String, *>,
        keys: Map<String, String>,
        requestId: String,
    ): Record? {
        if (values[keys.getValue("requestId")] != requestId) return null
        return Record(
            requestId = requestId,
            kind = values[keys.getValue("kind")] as? String ?: return null,
            style = values[keys.getValue("style")] as? String ?: return null,
            widgetId = values[keys.getValue("widgetId")] as? Int ?: return null,
            status = values[keys.getValue("status")] as? String ?: return null,
            confirmedAt = values[keys.getValue("confirmedAt")] as? Long ?: return null,
        )
    }
}
