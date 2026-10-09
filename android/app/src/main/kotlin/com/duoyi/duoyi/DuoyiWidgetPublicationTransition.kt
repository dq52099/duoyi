package com.duoyi.duoyi

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import java.util.Collections
import java.util.UUID

/** A parsed immutable request. The digest is native-computed, never caller authority. */
class DuoyiWidgetPublicationRequest private constructor(
    val method: String,
    private val fields: Map<String, Any?>,
    val presentation: DuoyiWidgetDesiredPresentation?,
    val presentationValues: Map<String, Any>?,
    val document: DuoyiWidgetPublicationDocument?,
    val binding: DuoyiWidgetWorkspaceBinding?,
) {
    val operationId: String get() = fields["operationId"] as String
    val expectedStoreRevision: Long? get() = fields["expectedStoreRevision"] as Long?
    val expectedOwnerEpoch: String? get() = fields["expectedOwnerEpoch"] as String?
    val writerLeaseId: String? get() = fields["writerLeaseId"] as String?
    val expectedPublicationRevision: Long? get() = fields["expectedPublicationRevision"] as Long?
    val mode: String? get() = fields["mode"] as String?
    val digest: String = digestOf(method, fields)

    companion object {
        private val common = setOf("protocolVersion", "operationId", "expectedStoreRevision", "expectedOwnerEpoch")
        const val OPEN = "openWidgetWorkspace"
        const val INVALIDATE = "invalidateWidgetWorkspace"
        const val ADVANCE = "advanceDesiredWidgetPresentation"
        const val PUBLISH = "publishWidgetPublication"

        fun tryFromMap(method: String, raw: Any?): DuoyiWidgetPublicationRequest? {
            val extra = when (method) {
                OPEN -> setOf("mode", "binding", "presentation")
                INVALIDATE -> setOf("presentation")
                ADVANCE -> setOf("writerLeaseId", "desiredPresentation")
                PUBLISH -> setOf("writerLeaseId", "expectedPublicationRevision", "document")
                else -> return null
            }
            if (raw !is Map<*, *> || raw.keys != common + extra) return null
            if (DuoyiWidgetPublicationDocument.exactInteger(raw["protocolVersion"]) != 1L) return null
            val id = opaque(raw["operationId"]) ?: return null
            val revision = raw["expectedStoreRevision"]?.let {
                DuoyiWidgetPublicationDocument.nonnegativeExact(it)?.takeIf { n -> n > 0L } ?: return null
            }
            val epoch = raw["expectedOwnerEpoch"]?.let { opaque(it) ?: return null }
            if ((revision == null) != (epoch == null)) return null
            val mode = if (method == OPEN) raw["mode"] as? String ?: return null else null
            if (mode != null && mode !in setOf("initialize", "resume")) return null
            if (revision == null && (method != OPEN || mode != "initialize")) return null
            val lease = if (method == ADVANCE || method == PUBLISH) opaque(raw["writerLeaseId"]) ?: return null else null
            val binding = if (method == OPEN) DuoyiWidgetWorkspaceBinding.tryFromMap(raw["binding"]) ?: return null else null
            var presentation: DuoyiWidgetDesiredPresentation? = null
            var values: Map<String, Any>? = null
            if (method == OPEN || method == INVALIDATE) {
                val p = raw["presentation"] as? Map<*, *> ?: return null
                if (p.keys != setOf("revision", "locale", "values")) return null
                presentation = DuoyiWidgetDesiredPresentation.tryFromMap(mapOf("revision" to p["revision"], "locale" to p["locale"])) ?: return null
                val v = p["values"] as? Map<*, *> ?: return null
                if (v.keys != DuoyiWidgetPublicationDocument.valueKeys) return null
                // Validate cleared business values while normalizing Int/Long
                // channel representations, including a small JSON millis zero.
                values = DuoyiWidgetPublicationDocument.tryFromMap(linkedMapOf(
                    "schemaVersion" to 1, "ownerEpoch" to "presentation-input",
                    "publicationRevision" to 0L, "localeRevision" to presentation.revision,
                    "state" to "cleared", "locale" to presentation.locale,
                    "snapshotDay" to "", "snapshotUtcOffsetMinutes" to 0,
                    "capturedAtMillis" to 0L, "values" to v,
                ))?.values ?: return null
            } else if (method == ADVANCE) {
                presentation = DuoyiWidgetDesiredPresentation.tryFromMap(raw["desiredPresentation"]) ?: return null
            }
            val document = if (method == PUBLISH) DuoyiWidgetPublicationDocument.tryFromMap(raw["document"]) ?: return null else null
            val publication = if (method == PUBLISH) DuoyiWidgetPublicationDocument.nonnegativeExact(raw["expectedPublicationRevision"]) ?: return null else null
            val fields = linkedMapOf<String, Any?>("protocolVersion" to 1L, "operationId" to id,
                "expectedStoreRevision" to revision, "expectedOwnerEpoch" to epoch)
            when (method) {
                OPEN -> { fields["mode"] = mode; fields["binding"] = binding!!.toMap() }
                ADVANCE -> fields["desiredPresentation"] = presentation!!.toMap()
                PUBLISH -> { fields["expectedPublicationRevision"] = publication; fields["document"] = document!!.toMap() }
            }
            if (values != null) fields["presentation"] = linkedMapOf("revision" to presentation!!.revision,
                "locale" to presentation.locale, "values" to values)
            if (lease != null) fields["writerLeaseId"] = lease
            return DuoyiWidgetPublicationRequest(method, Collections.unmodifiableMap(fields), presentation, values, document, binding)
        }

        private fun opaque(value: Any?): String? = (value as? String)?.takeUnless { DuoyiWidgetPublicationDocument.wireBlank(it) }

        /** Versioned tagged encoding: sorted map keys, exact ints and UTF-16 code units. */
        private fun digestOf(method: String, fields: Map<String, Any?>): String {
            val bytes = ByteArrayOutputStream()
            DataOutputStream(bytes).use { out ->
                fun write(value: Any?) {
                    when (value) {
                        null -> out.writeByte(0)
                        is String -> { out.writeByte(1); out.writeInt(value.length); value.forEach { out.writeChar(it.code) } }
                        is Boolean -> { out.writeByte(2); out.writeBoolean(value) }
                        is Int -> { out.writeByte(3); out.writeLong(value.toLong()) }
                        is Long -> { out.writeByte(3); out.writeLong(value) }
                        is Map<*, *> -> {
                            out.writeByte(4); out.writeInt(value.size)
                            value.keys.map { it as String }.sorted().forEach { key -> write(key); write(value[key]) }
                        }
                        else -> error("Unexpected canonical request primitive")
                    }
                }
                write("duoyi-widget-request-v1"); write(method); write(fields)
            }
            return MessageDigest.getInstance("SHA-256").digest(bytes.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 255) }
        }
    }
}

/** A plan is not a durability acknowledgement. Only the store may confirm it. */
class DuoyiWidgetPublicationPlan(
    val status: String,
    val replacement: DuoyiWidgetPublicationEnvelope? = null,
    val replay: DuoyiWidgetPublicationReceipt? = null,
)

/** Pure CAS and ownership policy; it never initializes files, reads mirrors, or runs effects. */
object DuoyiWidgetPublicationTransition {
    fun plan(
        current: DuoyiWidgetPublicationEnvelope?,
        request: DuoyiWidgetPublicationRequest,
        nowMillis: Long,
        zone: ZoneId,
        newToken: () -> String = { UUID.randomUUID().toString() },
    ): DuoyiWidgetPublicationPlan {
        fun reject(status: String) = DuoyiWidgetPublicationPlan(status)
        if (current != null && current.lastReceipt.operationId == request.operationId) {
            return if (current.lastReceipt.requestDigest == request.digest)
                DuoyiWidgetPublicationPlan("alreadyApplied", replay = current.lastReceipt) else reject("invalid")
        }
        if (nowMillis !in 0L..DuoyiWidgetPublicationDocument.MAX_EXACT_INTEGER) return reject("invalid")
        if (current == null) {
            if (request.method != DuoyiWidgetPublicationRequest.OPEN || request.mode != "initialize" ||
                request.expectedStoreRevision != null || request.expectedOwnerEpoch != null) return reject("revisionConflict")
        } else {
            if (request.expectedOwnerEpoch != current.ownerEpoch) return reject("ownerMismatch")
            if (request.expectedStoreRevision != current.storeRevision) return reject("revisionConflict")
            if (current.storeRevision == DuoyiWidgetPublicationDocument.MAX_EXACT_INTEGER) return reject("revisionConflict")
        }
        val storeRevision = (current?.storeRevision ?: 0L) + 1L
        var epoch = current?.ownerEpoch
        var lease = current?.writerLeaseId
        var binding = current?.binding
        var state = current?.leaseState
        var desired = current?.desiredPresentation
        var document = current?.document

        fun acceptsPresentation(p: DuoyiWidgetDesiredPresentation): Boolean {
            val floor = current?.desiredPresentation ?: return true
            if (p.revision < floor.revision || (p.revision == floor.revision && p.locale != floor.locale)) return false
            // Reusing an applied revision cannot quietly change its theme/brand.
            val old = current.document
            val incoming = request.presentationValues
            if (incoming != null && p.revision == old.presentationRevision) {
                if (incoming != DuoyiWidgetPublicationDocument.clearedValuesFrom(old.values)) return false
            }
            return true
        }
        when (request.method) {
            DuoyiWidgetPublicationRequest.OPEN -> {
                val p = request.presentation!!
                if (!acceptsPresentation(p)) return reject("supersededPresentation")
                if (request.mode == "resume") {
                    if (current == null || !current.active) return reject("sealed")
                    if (request.binding != current.binding) return reject("ownerMismatch")
                    // Keep the applied document verbatim; a newer floor is still pending.
                    binding = current.binding; desired = p
                } else {
                    if (current?.active == true) return reject(if (current.binding != request.binding) "ownerMismatch" else "revisionConflict")
                    epoch = issued(newToken, current?.ownerEpoch) ?: return reject("invalid")
                    binding = request.binding; desired = p
                    document = tombstone(epoch, p, request.presentationValues!!, nowMillis) ?: return reject("invalid")
                }
                lease = issued(newToken, current?.writerLeaseId) ?: return reject("invalid")
                if (lease == epoch) return reject("invalid")
                state = "active"
            }
            DuoyiWidgetPublicationRequest.INVALIDATE -> {
                val p = request.presentation!!
                if (!acceptsPresentation(p)) return reject("supersededPresentation")
                epoch = issued(newToken, current!!.ownerEpoch) ?: return reject("invalid")
                binding = null; lease = null; state = "sealed"; desired = p
                document = tombstone(epoch, p, request.presentationValues!!, nowMillis) ?: return reject("invalid")
            }
            DuoyiWidgetPublicationRequest.ADVANCE, DuoyiWidgetPublicationRequest.PUBLISH -> {
                if (current == null || !current.active) return reject("sealed")
                if (request.writerLeaseId != current.writerLeaseId) return reject("ownerMismatch")
                if (request.method == DuoyiWidgetPublicationRequest.ADVANCE) {
                    val p = request.presentation!!
                    if (!acceptsPresentation(p) || p.revision == current.desiredPresentation.revision) return reject("supersededPresentation")
                    desired = p
                } else {
                    val next = request.document!!
                    val oldRevision = current.document.publicationRevision
                    if (next.ownerEpoch != current.ownerEpoch) return reject("ownerMismatch")
                    if (request.expectedPublicationRevision != oldRevision || oldRevision == DuoyiWidgetPublicationDocument.MAX_EXACT_INTEGER ||
                        next.publicationRevision != oldRevision + 1L) return reject("revisionConflict")
                    if (next.presentationRevision != current.desiredPresentation.revision || next.locale != current.desiredPresentation.locale) return reject("supersededPresentation")
                    if (next.presentationRevision == current.document.presentationRevision &&
                        DuoyiWidgetPublicationDocument.clearedValuesFrom(next.values) !=
                        DuoyiWidgetPublicationDocument.clearedValuesFrom(current.document.values)) return reject("supersededPresentation")
                    if (next.state == DuoyiWidgetPublicationDocument.State.PUBLISHED && !eligibleCapture(next, nowMillis, zone)) return reject("invalid")
                    document = next
                }
            }
            else -> return reject("invalid")
        }
        val doc = document ?: return reject("invalid")
        val receipt = linkedMapOf("operationId" to request.operationId, "requestDigest" to request.digest,
            "committedStoreRevision" to storeRevision, "resultMetadata" to linkedMapOf(
                "ownerEpoch" to epoch, "publicationRevision" to doc.publicationRevision,
                "desiredPresentationRevision" to desired!!.revision, "appliedPresentationRevision" to doc.presentationRevision,
                "documentState" to doc.state.wire, "writerLeaseId" to lease))
        val envelope = DuoyiWidgetPublicationEnvelope.tryFromMap(linkedMapOf(
            "storeSchemaVersion" to 1, "storeRevision" to storeRevision, "binding" to binding?.toMap(),
            "ownerEpoch" to epoch, "writerLeaseId" to lease, "leaseState" to state,
            "desiredPresentation" to desired.toMap(), "document" to doc.toMap(), "lastReceipt" to receipt)) ?: return reject("invalid")
        return DuoyiWidgetPublicationPlan("prepared", replacement = envelope)
    }

    private fun issued(generator: () -> String, previous: String?): String? = generator().takeUnless {
        DuoyiWidgetPublicationDocument.wireBlank(it) || it == previous
    }

    private fun tombstone(epoch: String, p: DuoyiWidgetDesiredPresentation, values: Map<String, Any>, now: Long): DuoyiWidgetPublicationDocument? =
        DuoyiWidgetPublicationDocument.tryFromMap(linkedMapOf("schemaVersion" to 1, "ownerEpoch" to epoch,
            "publicationRevision" to 0L, "localeRevision" to p.revision, "state" to "cleared", "locale" to p.locale,
            "snapshotDay" to "", "snapshotUtcOffsetMinutes" to 0, "capturedAtMillis" to now, "values" to values))

    /** Strict same-day capture in the current zone/offset; future captures never publish. */
    private fun eligibleCapture(doc: DuoyiWidgetPublicationDocument, now: Long, zone: ZoneId): Boolean {
        if (doc.capturedAtMillis > now) return false
        val accepted = Instant.ofEpochMilli(now).atZone(zone)
        val captured = Instant.ofEpochMilli(doc.capturedAtMillis).atZone(zone)
        return doc.snapshotDay == accepted.toLocalDate().toString() &&
            doc.snapshotDay == captured.toLocalDate().toString() &&
            doc.snapshotUtcOffsetMinutes == accepted.offset.totalSeconds / 60 &&
            doc.snapshotUtcOffsetMinutes == captured.offset.totalSeconds / 60
    }
}
