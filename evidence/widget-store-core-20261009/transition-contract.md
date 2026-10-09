# Native widget store transition contract

2026-10-09. Bounded review of the two approved audit documents and the existing Kotlin Document/Envelope draft. Production remained read-only. No tests, SDK, Git operations, or network requests were run.

## Common transition rules

Use the four approved mutation methods and the existing read method. A pure transition engine can receive a verified current envelope (or an explicit absent observation), an immutable parsed request, native token generation, and internal clock/context facts. Its result is a rejected operation, a durable-receipt replay, or a complete replacement envelope awaiting the coordinator's commit confirmation. Planning a replacement is not an `applied` acknowledgement.

Every mutation has `protocolVersion=1`, nonblank `operationId`, `expectedStoreRevision`, and `expectedOwnerEpoch`. Null expectations are permitted only for initialize against confirmed absence. Every existing-store transition requires exact revision and epoch equality. Never equate absent with corrupt, unsupported, unavailable, or durabilityUnknown. The internal request digest must identify the complete immutable request, including method and expectations. The draft receipt requires a lowercase 64-character hexadecimal digest.

After structural decoding and strict envelope validation, check the last receipt before CAS, lease validation, clock freshness, or token generation. Same operation ID and digest returns its original metadata as `alreadyApplied`, without replacement or effects. Same ID with a different digest is `invalid`. If another operation has replaced the receipt, the original stale expectations conflict; do not refresh expectations and replay old content.

Successful fresh mutations increase global `storeRevision` exactly once and replace envelope/receipt atomically. Initial creation can use revision 1, matching the draft's positive-revision requirement. All revisions are exact Long values within 0..9007199254740991; reject required increments at the maximum. Comparison of binding, epoch, lease, and literals is exact, without normalization.

## Operations

| Operation | Required additional request facts and admission | Complete replacement |
| --- | --- | --- |
| `openWidgetWorkspace`, initialize absent | mode, validated private binding, complete coherent cleared presentation, device presentation revision/locale; both expectations null and absence reconfirmed under mutation lock | Native new epoch and lease; active binding; clean cleared document at publication revision 0; document epoch/presentation match the new envelope; desired presentation supplied/reconciled from device context; store revision 1. Ignore old mirrors. |
| `openWidgetWorkspace`, initialize sealed | Same open facts; exact existing revision/epoch and sealed envelope. Active foreign binding is ownerMismatch; active matching binding must use resume rather than initialize. | New native epoch and lease, requested binding, active state, fresh cleared document revision 0; store revision +1; preserve or increase device presentation floor. Never relabel old business data. |
| `openWidgetWorkspace`, resume | Exact revision/epoch, matching active binding, healthy complete document and coherent device presentation context | Preserve epoch and complete document; issue a new lease distinct from the previous lease; store revision +1; retain/reconcile desired presentation without marking the old document newly applied. |
| `invalidateWidgetWorkspace` | Exact existing revision/epoch; coherent cleared presentation and latest device revision/locale. The wire section does not require the caller's writer lease or a replacement binding. | Native new epoch; null binding and lease; sealed state; clean tombstone with all 67 business values empty/zero/false and all 22 presentation values coherent; publication revision 0 is valid for the new epoch; desired/applied presentation match; store revision +1. |
| `advanceDesiredWidgetPresentation` | Exact revision/epoch, active state, exact current writer lease, desired revision/locale | Reject lower revisions and same-revision locale changes. For a higher revision, replace desired floor only, preserve the complete document, epoch, binding, and lease; store revision +1. Applied revision remains the document's presentation revision. |
| `publishWidgetPublication` | Exact revision/epoch, active state, exact writer lease; `expectedPublicationRevision` equals current document revision; strict complete document | Incoming epoch equals current epoch; incoming publication revision equals current +1; document presentation revision and locale equal desired floor; preserve binding/epoch/lease/floor; replace document and receipt, store revision +1. Published capture must still be eligible at acceptance. Cleared/blocked documents remain subject to complete sanitation. |

Open/invalidate issue capabilities natively; their approved wire descriptions do not justify adding an old-lease requirement. Advance/publish do require the current lease. Read returns verified facts without either the envelope or receipt's writer capability. Matching stable identity cannot bypass a reset: the caller must invalidate first. Auth/generation validation belongs to the existing host context and is not inferred from a string binding by this engine.

## Receipt and draft invariants

Each replacement records operation ID, digest, committed store revision, resulting epoch, document publication revision, desired revision, applied document presentation revision, document state, and resulting lease. These are the replacement's facts, not the request's expected facts. Open acknowledgements include the newly issued lease; read does not expose it. The draft currently records the current lease for every active-state receipt, which enables internal envelope correlation; non-open public acknowledgements need not disclose it.

The draft already enforces: active implies binding+lease; sealed implies neither; document epoch equals envelope epoch; applied revision cannot exceed desired; equal presentation revisions require matching locale; sealed cannot contain published data and must have applied=desired; receipt fields must exactly match the resulting envelope. The strict Document validates the ten fields, all 89 values, Int/Long projections, legal dates, matching todo counts, and all 67 non-published business fields. Generate tombstones through its complete-value sanitation and strict decoder, never a partial patch.

`applied` requires the coordinator to commit and then verify a new-connection read while holding the operation lock. Commit/readback uncertainty yields durabilityUnknown and quarantines current-process writes. The pure engine must not clear that state by planning the same values. Failed validation and receipt replay cause no mutation effects. Fresh effects begin only after confirmed canonical commit; they are not part of SQLite atomicity.

## Actual underspecification and bounded choices

1. **Presentation reconciliation on open:** the source requires a version above the existing floor when device context differs, while resume preserves the document. It does not specify whether native allocates the reconciled version or the caller supplies an already reconciled version. Both can preserve the approved API. Document the chosen rule; never lower the floor, and leave a resumed old document at its actual applied version. Returning the resulting desired revision is already required by ack metadata.
2. **Fresh advance with identical revision and locale:** lowering and same-revision locale changes are explicitly forbidden, but a fresh operation with identical desired facts is unspecified. A conservative choice is to reject it without mutation; exact receipt replay remains alreadyApplied. If instead accepted, store revision and receipt must still advance consistently, and it must not claim a newer applied document.
3. **Published time acceptance:** sources require valid capture/day/offset and a still-current date boundary, but define no numeric age/future tolerance or authoritative offset comparison. Minimum date consistency is that capture and acceptance fall on the declared day under the accepted offset; concrete skew/freshness policy needs an explicit local implementation decision. History decoding must remain independent of this acceptance check. No new public method is required.
4. **Digest canonicalization:** receipt shape is fixed, but request hashing serialization is not. Compute/validate it internally from the complete parsed request using a deterministic representation that preserves literal strings and numbers. No new caller-supplied authority field is needed.

These are bounded implementation choices, not grounds to add recovery/bootstrap methods or expand architecture. Recovery remains outside the four ordinary mutation transitions.

## Sources

- `/home/ubuntu/duoyi/evidence/widget-publication-descriptor-20261009/wire-schema-audit.md`: sections 2–7, especially lines 149–208.
- `/home/ubuntu/duoyi/evidence/widget-publication-descriptor-20261009/native-store-implementation-plan.md`: section 3, lines 60–85; effect ordering line 116.
- `/home/ubuntu/duoyi-worktrees/widget-store-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPublicationDocument.kt`.
- `/home/ubuntu/duoyi-worktrees/widget-store-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPublicationEnvelope.kt`: receipt lines 32–90 and envelope correlation lines 138–171.
- Workspace instructions read: `/home/ubuntu/AGENTS.md`, `/home/ubuntu/duoyi/AGENTS.md`.
