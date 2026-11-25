package com.duoyi.duoyi

/** Private durable ownership; never projected into widget content or links. */
data class DuoyiWidgetWorkspaceBinding private constructor(val kind: String, val key: String) {
    fun toMap(): Map<String, Any> = linkedMapOf("kind" to kind, "key" to key)

    companion object {
        fun tryFromMap(raw: Any?): DuoyiWidgetWorkspaceBinding? {
            if (raw !is Map<*, *> || raw.keys != setOf("kind", "key")) return null
            val kind = raw["kind"] as? String ?: return null
            val key = raw["key"] as? String ?: return null
            if (kind !in setOf("account", "guest") || DuoyiWidgetPublicationDocument.wireBlank(key)) return null
            return DuoyiWidgetWorkspaceBinding(kind, key)
        }
    }
}

data class DuoyiWidgetDesiredPresentation private constructor(val revision: Long, val locale: String) {
    fun toMap(): Map<String, Any> = linkedMapOf("revision" to revision, "locale" to locale)

    companion object {
        fun tryFromMap(raw: Any?): DuoyiWidgetDesiredPresentation? {
            if (raw !is Map<*, *> || raw.keys != setOf("revision", "locale")) return null
            val revision = DuoyiWidgetPublicationDocument.nonnegativeExact(raw["revision"]) ?: return null
            val locale = raw["locale"] as? String ?: return null
            if (locale != "zh" && locale != "en") return null
            return DuoyiWidgetDesiredPresentation(revision, locale)
        }
    }
}

/** The last operation's facts, stored atomically with the complete replacement. */
class DuoyiWidgetPublicationReceipt private constructor(
    val operationId: String,
    val requestDigest: String,
    val committedStoreRevision: Long,
    val ownerEpoch: String,
    val publicationRevision: Long,
    val desiredPresentationRevision: Long,
    val appliedPresentationRevision: Long,
    val documentState: String,
    val writerLeaseId: String?,
) {
    fun resultMetadata(): Map<String, Any?> = linkedMapOf(
        "ownerEpoch" to ownerEpoch,
        "publicationRevision" to publicationRevision,
        "desiredPresentationRevision" to desiredPresentationRevision,
        "appliedPresentationRevision" to appliedPresentationRevision,
        "documentState" to documentState,
        "writerLeaseId" to writerLeaseId,
    )

    fun toMap(): Map<String, Any> = linkedMapOf(
        "operationId" to operationId,
        "requestDigest" to requestDigest,
        "committedStoreRevision" to committedStoreRevision,
        "resultMetadata" to resultMetadata(),
    )

    companion object {
        fun tryFromMap(raw: Any?): DuoyiWidgetPublicationReceipt? {
            if (raw !is Map<*, *> || raw.keys != setOf(
                    "operationId", "requestDigest", "committedStoreRevision", "resultMetadata",
                )) return null
            val id = raw["operationId"] as? String ?: return null
            val digest = raw["requestDigest"] as? String ?: return null
            if (DuoyiWidgetPublicationDocument.wireBlank(id) || !Regex("[0-9a-f]{64}").matches(digest)) return null
            val revision = DuoyiWidgetPublicationDocument.nonnegativeExact(raw["committedStoreRevision"])
                ?.takeIf { it > 0L } ?: return null
            val result = raw["resultMetadata"] as? Map<*, *> ?: return null
            if (result.keys != setOf(
                    "ownerEpoch", "publicationRevision", "desiredPresentationRevision",
                    "appliedPresentationRevision", "documentState", "writerLeaseId",
                )) return null
            val epoch = result["ownerEpoch"] as? String ?: return null
            if (DuoyiWidgetPublicationDocument.wireBlank(epoch)) return null
            val publication = DuoyiWidgetPublicationDocument.nonnegativeExact(result["publicationRevision"])
                ?: return null
            val desired = DuoyiWidgetPublicationDocument.nonnegativeExact(result["desiredPresentationRevision"])
                ?: return null
            val applied = DuoyiWidgetPublicationDocument.nonnegativeExact(result["appliedPresentationRevision"])
                ?: return null
            val state = result["documentState"] as? String ?: return null
            if (state !in setOf("published", "cleared", "blocked") || applied > desired) return null
            val lease = result["writerLeaseId"]
            if (lease != null && (lease !is String || DuoyiWidgetPublicationDocument.wireBlank(lease))) return null
            return DuoyiWidgetPublicationReceipt(
                id, digest, revision, epoch, publication, desired, applied, state, lease as String?,
            )
        }
    }
}

/** One native-owned envelope; a mirror/document cannot grant a lease or binding. */
class DuoyiWidgetPublicationEnvelope private constructor(
    val storeRevision: Long,
    val binding: DuoyiWidgetWorkspaceBinding?,
    val ownerEpoch: String,
    val writerLeaseId: String?,
    val leaseState: String,
    val desiredPresentation: DuoyiWidgetDesiredPresentation,
    val document: DuoyiWidgetPublicationDocument,
    val lastReceipt: DuoyiWidgetPublicationReceipt,
) {
    val active: Boolean get() = leaseState == "active"

    fun toMap(): Map<String, Any?> = linkedMapOf(
        "storeSchemaVersion" to STORE_SCHEMA_VERSION,
        "storeRevision" to storeRevision,
        "binding" to binding?.toMap(),
        "ownerEpoch" to ownerEpoch,
        "writerLeaseId" to writerLeaseId,
        "leaseState" to leaseState,
        "desiredPresentation" to desiredPresentation.toMap(),
        "document" to document.toMap(),
        "lastReceipt" to lastReceipt.toMap(),
    )

    /** Reads expose facts, but never the writer capability carried in the envelope/receipt. */
    fun readMetadata(): Map<String, Any?> = linkedMapOf(
        "storeRevision" to storeRevision,
        "binding" to binding?.toMap(),
        "ownerEpoch" to ownerEpoch,
        "leaseState" to leaseState,
        "desiredPresentation" to desiredPresentation.toMap(),
        "document" to document.toMap(),
        "lastOperationId" to lastReceipt.operationId,
        "lastRequestDigest" to lastReceipt.requestDigest,
    )

    companion object {
        const val STORE_SCHEMA_VERSION = 1
        private val keys = setOf(
            "storeSchemaVersion", "storeRevision", "binding", "ownerEpoch", "writerLeaseId",
            "leaseState", "desiredPresentation", "document", "lastReceipt",
        )

        fun tryFromMap(raw: Any?): DuoyiWidgetPublicationEnvelope? {
            if (raw !is Map<*, *> || raw.keys != keys) return null
            if (DuoyiWidgetPublicationDocument.exactInteger(raw["storeSchemaVersion"]) != 1L) return null
            val revision = DuoyiWidgetPublicationDocument.nonnegativeExact(raw["storeRevision"])
                ?.takeIf { it > 0L } ?: return null
            val epoch = raw["ownerEpoch"] as? String ?: return null
            if (DuoyiWidgetPublicationDocument.wireBlank(epoch)) return null
            val state = raw["leaseState"] as? String ?: return null
            if (state != "active" && state != "sealed") return null
            val binding = raw["binding"]?.let {
                DuoyiWidgetWorkspaceBinding.tryFromMap(it) ?: return null
            }
            val rawLease = raw["writerLeaseId"]
            if (rawLease != null && (rawLease !is String || DuoyiWidgetPublicationDocument.wireBlank(rawLease))) return null
            val lease = rawLease as String?
            if (state == "active") {
                if (binding == null || lease == null) return null
            } else if (binding != null || lease != null) return null
            val presentation = DuoyiWidgetDesiredPresentation.tryFromMap(raw["desiredPresentation"])
                ?: return null
            val document = DuoyiWidgetPublicationDocument.tryFromMap(
                raw["document"], allowLegacyWeekStart = true,
            ) ?: return null
            if (document.ownerEpoch != epoch || document.presentationRevision > presentation.revision) return null
            if (document.presentationRevision == presentation.revision && document.locale != presentation.locale) return null
            if (state == "sealed" && document.state == DuoyiWidgetPublicationDocument.State.PUBLISHED) return null
            if (state == "sealed" && document.presentationRevision != presentation.revision) return null
            val receipt = DuoyiWidgetPublicationReceipt.tryFromMap(raw["lastReceipt"]) ?: return null
            if (receipt.committedStoreRevision != revision || receipt.ownerEpoch != epoch ||
                receipt.writerLeaseId != lease || receipt.publicationRevision != document.publicationRevision ||
                receipt.desiredPresentationRevision != presentation.revision ||
                receipt.appliedPresentationRevision != document.presentationRevision ||
                receipt.documentState != document.state.wire) return null
            return DuoyiWidgetPublicationEnvelope(
                revision, binding, epoch, lease, state, presentation, document, receipt,
            )
        }
    }
}
