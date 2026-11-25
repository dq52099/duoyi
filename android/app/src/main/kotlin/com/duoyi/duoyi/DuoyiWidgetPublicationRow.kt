package com.duoyi.duoyi

import org.json.JSONObject

/** Explicit read state. A failed decoder is never permission to initialize. */
class DuoyiWidgetPublicationRead(val status: String, val envelope: DuoyiWidgetPublicationEnvelope? = null) {
    fun metadata(): Map<String, Any?> = linkedMapOf<String, Any?>("status" to status).apply {
        envelope?.let { putAll(it.readMetadata()) }
    }
}

/** Validates the stored wire representation before projecting legacy defaults. */
object DuoyiWidgetPublicationRow {
    fun decode(encoded: String): DuoyiWidgetPublicationRead {
        val raw = DuoyiWidgetPublicationJson.decode(encoded)
            ?: return DuoyiWidgetPublicationRead("corrupt")
        val schema = DuoyiWidgetPublicationDocument.exactInteger(raw["storeSchemaVersion"])
        if (schema != null && schema != 1L) return DuoyiWidgetPublicationRead("unsupported")
        val envelope = DuoyiWidgetPublicationEnvelope.tryFromMap(raw)
            ?: return DuoyiWidgetPublicationRead("corrupt")
        // Validate the bytes actually stored. Envelope parsing may supply the
        // Monday default for an exact legacy 89-value document; comparing its
        // normalized map would incorrectly reject an otherwise canonical row.
        // Re-encoding raw still rejects duplicates, trailing data, lossy numbers
        // and alternate encodings. New writes always emit the full current map.
        if (encoded != DuoyiWidgetPublicationJson.encode(raw)) {
            return DuoyiWidgetPublicationRead("corrupt")
        }
        return DuoyiWidgetPublicationRead(if (envelope.active) "ready" else "sealed", envelope)
    }
}

/** ASCII canonical JSON preserves every String UTF-16 code unit and exact integer. */
object DuoyiWidgetPublicationJson {
    fun encode(value: Any?): String = when (value) {
        null -> "null"
        is Boolean -> value.toString()
        is Int, is Long -> value.toString()
        is String -> buildString {
            append('"')
            value.forEach { c ->
                when {
                    c == '"' -> append("\\\"")
                    c == '\\' -> append("\\\\")
                    c.code < 32 || c.code > 126 -> append("\\u%04x".format(c.code))
                    else -> append(c)
                }
            }
            append('"')
        }
        is Map<*, *> -> value.keys.map { it as String }.sorted().joinToString(",", "{", "}") { key -> encode(key) + ":" + encode(value[key]) }
        else -> error("Unexpected store primitive")
    }

    fun decode(value: String): Map<String, Any?>? = try {
        fun convert(value: Any?): Any? = when (value) {
            JSONObject.NULL, null -> null
            is JSONObject -> value.keys().asSequence().associateWith { convert(value.get(it)) }
            is String, is Boolean, is Int, is Long -> value
            else -> throw IllegalArgumentException("Invalid store primitive")
        }
        @Suppress("UNCHECKED_CAST")
        (convert(JSONObject(value)) as Map<String, Any?>)
    } catch (_: Exception) { null }
}
