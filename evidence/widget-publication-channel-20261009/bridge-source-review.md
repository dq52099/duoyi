# Widget publication bridge source review

2026-10-09. Bounded review of the new Android bridge and its three-line engine registration. Core files were unchanged from the previous repair review and were not reread. No source edits, tests, SDK commands, Git operations, or network requests.

No actionable defect was found in the reviewed bridge paths.

- The process-wide single-worker executor serializes accepted work and caps pending work at 128 requests. Parsing, digest calculation, reads, and mutations execute on the worker. Queue rejection returns busy without running the operation.
- Each engine attachment has a fresh identity token. A request captures that token, store, and original MethodChannel result. The result is posted to the main looper only if the original token remains current. Detach clears the token/handler/context reference; reattach creates a different token, so an old result cannot reach the new attachment. Queued work can still commit after detach, and its durable receipt remains authoritative even when the channel acknowledgement is dropped.
- The bridge obtains the store from the plugin binding's applicationContext. It retains neither MainActivity nor an Activity context. The MainActivity registration checks the engine plugin registry before adding the bridge, preventing duplicate registration for an already configured engine.
- The dedicated `duoyi/widget-publication` channel exposes exactly read plus the four approved mutations. Unknown methods return notImplemented. Read accepts null or an empty argument map; mutation arguments pass through the previously reviewed strict native request parser and native digest policy. Codec argument maps are independently decoded messages owned by this invocation, rather than live provider maps.
- Read returns `read().metadata()`, which uses the unchanged core's lease-redacted metadata. It exposes no writer lease from either the envelope or receipt. Successful open remains the capability-granting operation, as approved.
- Mutation responses come from the unchanged store's durable commit/readback path, rather than an optimistic bridge acknowledgement. Detach does not reverse a commit. The added `refreshRequested=false` states that no refresh was requested; it does not turn persistence success into a display claim. The bridge runs no alarm or widget refresh effect.

This is a bounded source result. Dart producers/controllers, Android canonical renderers and accepted-effect wiring remain unswitched. The bridge/store/transition have no end-to-end, lifecycle, multiprocess, or runtime durability proof from this review. Their remaining integration is not counted as a defect in this isolated adapter.

Inspected sources:

- `/home/ubuntu/duoyi-worktrees/widget-store-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPublicationBridge.kt`, lines 1–74.
- `/home/ubuntu/duoyi-worktrees/widget-store-20261009/android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt`, registration lines 119–123.
