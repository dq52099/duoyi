# Widget publication channel

Android and iOS host channel: `duoyi/widget-publication`. The application-scoped store
runs operations on a bounded background queue. This adapter is registered per
Flutter engine; a detached engine does not receive a late response. A committed
operation survives messenger disposal and can be recovered by its receipt.

## Current integration status

The Android and iOS native stores, bridges, Dart wire adapter and authority controller are
connected to the Flutter publisher and account cleanup flows in `lib/main.dart`.
The controller starts blocked, serializes requests, fences stale account and
presentation captures, and requires a confirmed native clear before a revoked
workspace can reopen. The host supplies validated account/guest context and
checks hydration and generations before publishing a complete document.
Android renderers read business and presentation values from the canonical
document; only validated device-owned layout preferences accompany it. The
store lock spans a readable envelope's final `updateAppWidget` acceptance.

iOS WidgetKit entries, timelines, placeholder locale and gallery locale now read
the canonical App Group SQLite document. Each snapshot/timeline capture reads one
complete envelope; future timeline entries reuse that immutable projection.
The extension reads only the whitelisted device display mode from UserDefaults.
No account, theme, language or snapshot identity falls back to old preference keys.
Unavailable storage produces an account-free system-locale placeholder.
The capture retains both status and values in one immutable DTO. A busy read has
at most two immediate retries, each after 25 ms; display mode is read once after
the final store read. Persistent busy keeps the account-free placeholder and
requests a timeline reload no later than 30 seconds from capture. Ordinary
15-minute and running-focus one-minute requests remain, with an earlier
scheduled transition taking precedence. These are requested dates, subject to
WidgetKit's scheduling budget and process lifetime.
The [current capture acceptance](../evidence/priority-content-20261024/main-ios-capture-postguard-v235.json)
binds 57 current-main Flutter/resource checks, full analysis, seven executable
Foundation probe groups and Swift syntax parsing to the three integrated files.
It does not establish Apple SDK typechecking, extension linking, rendering or
actual WidgetKit timing. The probes call the production refresh helper; they do
not copy its scheduling formula.

Flutter data changes now pass through `HomeWidgetPushQueue`. Foreground changes
retain a 2.2-second debounce and an eight-second minimum interval. The root
`inactive`/`paused` callback cancels that timer and attempts an immediate drain
without loading unhydrated storage. Repeated background hints are idempotent;
new changes still mark the queue dirty. An in-flight publication finishes before
one immediate followup captures the latest queued values. Each background drain
is limited to two passes; failure or additional pending work is retained for
resume, with no background retry timer. The existing account-generation admission
and acceptance checks remain in the publication host, and the resumed forced
refresh remains active. Completion of the drain does not prove OS refresh.
The [current queue acceptance](../evidence/priority-content-20261024/main-lifecycle-postguard-v206.json)
binds 95 related Flutter checks, full analysis and the scoped independent review;
the [current debug package](../evidence/priority-content-20261024/android-debug-postguard-v208.json)
binds that source snapshot. Neither establishes Launcher/WidgetKit execution.

The iOS shared protocol and SQLite store implementation now reside in
`ios/WidgetPublicationShared/` and belong to both Runner and DuoyiWidgets.
Both targets explicitly link system SQLite; all six target configurations
include the shared C module path. The coordinator holds a process gate and
fixed `flock` through COMMIT, connection close, fresh-connection readback and
complete-envelope comparison. A failed commit or uncertain postcommit result
quarantines that path within the current process; ordinary reads, retries and
new coordinator instances cannot clear it. The shared Swift core now provides
host-only recovery inspection and a seal-only recovery transaction, with strict
current-intent parsing, exact CAS, a new epoch/receipt and full commit/readback
proof. It rejects a fixed lock whose device/inode differs from this process's
previous observation. A repeated recovery receipt alone remains unknown and
requires fresh inspection and a new immutable operation ID. The native result
grants no writer lease; a later separately validated open is required.
Both host bridges now expose `inspectWidgetStoreRecovery` and `recoverWidgetStore`
on the same bounded FIFO as ordinary mutations. Dart strictly decodes facts and
freezes workspace/cleanup intent. The controller revokes captures and leases,
checks current account/cleanup/presentation generations after every await and
requires exact sealed confirmation. Success grants no lease; a separate validated
open and newly hydrated capture are required. The main host discards pre-recovery
payloads and starts a separate publication pass, while cleanup requires a still-current
session/account/cleanup intent before proceeding. These are source and synthetic
transport results; actual startup/auth/cleanup/engine execution remains a platform gate.
See the [channel recovery integration report](../evidence/widget-recovery-controller-20261020/summary.md)
for current command/source bindings and remaining acceptance.
The main host now delegates publication and its pre-deletion widget barrier to
`WidgetPublicationHost`, so its ordering is exercised through the same production
service used by the application. The service freezes complete scalar values before
its first await, rechecks host context after presentation advancement and after
refresh, and schedules a separate fresh pass without waiting inside the payload
FIFO. Cleanup invokes legacy cache work only after current sealed confirmation,
and returns no model-clear permission if that intent changes while cache work
waits. The [host orchestration report](../evidence/widget-recovery-host-20261020/summary.md)
records clean reproduced boundary failures, real `HomeWidgetService.push` FIFO
checks and the production-host-to-Swift/SQLite exchange. Synthetic host auth
predicates and platform APIs still do not establish full app startup/auth, real
engine/OS lifecycle, launcher/WidgetKit display or device acceptance.
The subsequent [auth/native lifecycle composition](../evidence/widget-auth-native-lifecycle-20261021/summary.md)
executes real `AuthProvider`, Todo, locale and theme providers with exact current
main writer, presentation/action callbacks and the widget-cleanup barrier prefix,
connected to current production Swift/SQLite. It distinguishes blocked cleanup,
postcommit seal recovery, stale publication responses, account handover and
locale/theme round trips. HTTP, preferences, OS refresh responses, cloud preflight
and cleanup after the widget barrier remain explicit test substitutions. Its
report determines bounded acceptance; this is not complete `main()` or actual
Flutter-engine, Android/iOS storage, Launcher or WidgetKit execution.
The [actual main startup composition](../evidence/widget-main-startup-20261021/summary.md)
calls the production entry directly and exercises its critical-storage gate,
retry and registered dashboard publisher in both priority themes. HTTP,
preferences, filesystem locations, notification/plugin and OS channel responses
are explicit test ports; the Swift/SQLite peer is the prior accepted Linux
binary, bound to current production sources. Delayed tasks are cancelled during
test cleanup. This does not establish complete idle startup, mobile engine/OS
lifecycle, real account cleanup, Launcher/WidgetKit display or device acceptance.
The [actual main logout cleanup composition](../evidence/widget-main-cleanup-20261021/summary.md)
follows the unchanged main-registered cleanup callbacks through native sealing,
simulated notification cancellation, actual Todo/preference reset, synthetic
avatar-directory detachment and simulated server logout. It separately checks
denied sealing with retention/retry and actual SQLite postcommit recovery. Clean
cloud preflight and synthetic platform/HTTP ports do not establish real uploads,
server revocation, OS cancellation, all model/error branches or device acceptance.
The Android core now implements matching inspection/seal-only primitives and
observed-lock identity checks; both production planners agree on all 292 original
and recovery intents, including complete replacements and receipts. Android opens
the fixed lock with `O_NOFOLLOW` and no `O_CREAT` for an existing store, then retains
the existing shared/exclusive FileChannel protocol through final validation.
Its SDK compilation and explicit host POSIX/SQLite test transports are documented
in the [Android recovery report](../evidence/widget-android-recovery-20261020/summary.md);
they do not establish Android SQLite/Os/libcore or device behavior.
See also the [Swift native recovery report](../evidence/widget-native-recovery-20261020/summary.md)
and its [contract](../evidence/widget-native-recovery-20261020/recovery-contract.md).

Android initialization also rejects a missing database accompanied by an
existing journal directory entry (including a file, directory or dangling
symbolic link), before opening SQLite and while holding the fixed operation
lock. It preserves the journal instead of treating that
partial store as a new workspace. The admission-only JVM evidence and the
separate recovery design review are recorded in
[the recovery follow-up](../evidence/widget-recovery-contract-20261020/summary.md).
That follow-up does not establish Android SQLite runtime or explicit recovery
acceptance.

Android's singleton-row reader checks the Cursor storage types before decoding:
the ID must be INTEGER with its full 64-bit value equal to 1, and the envelope
must be TEXT. Converted getter values and IDs truncated to 32 bits cannot
authorize a readable publication. The
[row-type follow-up](../evidence/widget-row-types-20261020/summary.md) records
synthetic Cursor boundary verification separately from Android SQLite runtime.

The shared iOS channel is connected in source to Flutter publication, native
account-clear barriers and widget action validation. Missing mobile native
writer/validator callbacks fail closed. Theme-only preference publication is
suppressed; complete documents carry presentation and business values together.
Action validation checks the current host-validated account/guest binding and
account/session generation around the native read, then requires an active
published document and matching epoch, day and offset.

This source integration still requires Apple platform acceptance.
The production sources pass Linux native synthetic transport, lock and
coordinator checks. The default App Group/protection implementation, Apple
CryptoKit, Darwin durability and Apple SDK/device execution remain unverified;
Linux tests inject a synthetic protection policy explicitly. The Runner bridge
is registered per implicit Flutter engine and publishes its plugin instance for
engine teardown notification. Its bounded serial queue and detached callback
suppression pass synthetic API/store-stand-in checks; real Flutter engine and
Apple SDK execution remain unverified. A Linux integration check exercises the
actual Dart client/controller against production Swift SQLite/capture using an
explicit synthetic protection policy and independent external SHA256 provider.
It covers publication, lost-response exact receipt retry, presentation changes,
sealed cleanup and account rotation; it does not exercise Apple CryptoKit or a
real engine. See the
[store integration evidence](../evidence/ios-publication-store-20261020/summary.md)
and [canonical wiring evidence](../evidence/ios-publication-wiring-20261020/summary.md)
for exact commands, preserved failures and review status.

An `applied` response confirms canonical storage, not launcher display. The
bridges return `refreshRequested: false`; the Flutter host requests
widget refresh after confirming the publication and current context. SQLite
durability, bridge lifecycle, launcher repaint and WidgetKit/App Group runtime
acceptance remain separate from source contracts, core tests and compilation.

## Dart adapter

`lib/services/widget_publication_client.dart` provides typed reads and immutable
open/invalidate/advance/publish and seal-only recovery requests. Read facts carry no writer lease;
only a validated open acknowledgement returns that capability. The adapter
checks exact response shapes, operation identity, the next store revision and
the expected document/presentation result before exposing a committed response.

Keep the original `WidgetStoreRequest` when a response is uncertain. The default
15-second response deadline bounds the Flutter wait and does not cancel a
native transaction. A mutation channel error or deadline returns
`responseUnknown`; malformed responses return `invalidResponse`. Neither is
permission to advance an accepted cache, retry with new expectations or fall
back to preference data. The adapter performs no automatic retries, workspace
bootstrap, account-generation checks or launcher refresh.
`WidgetPublicationController` provides bootstrap, generation and exact-retry
guards within the mobile host flow; auth validation and refresh requests remain
host responsibilities. It can retain one exact request for retry; an ordered
healthy native read can drain an uncertain call before a new clear operation.
Neither route treats a read as a source of writer capability.

## Read

`readWidgetStore` takes no arguments (an empty map is also accepted).
It returns `status` and, for a healthy store, revision, binding, epoch,
lease state, desired presentation, full document and last operation identity.
It never returns the writer lease. Absence, corruption, unsupported versions,
busy/unavailable storage and unknown durability are distinct outcomes.

## Recovery inspection and seal

`inspectWidgetStoreRecovery` accepts no arguments or an empty map. An `inspected`
response contains exactly `facts` with `storeRevision`, `ownerEpoch`, `binding`,
`desiredPresentation`, `appliedPresentationRevision`, `lastOperationId` and
`lastRequestDigest`. It returns no document, readiness or writer capability and
cannot clear quarantine. The Dart adapter rejects extra keys, malformed bindings,
non-exact integer types/ranges, invalid locale/digest and applied revision above
the desired floor.

`recoverWidgetStore` uses exact inspected revision/epoch, a new operation ID,
a complete cleared presentation and `recoveryContext` with exactly `kind`,
`scopeToken`, `binding`. `workspace` carries a current host-validated binding;
`cleanup` carries null binding. The token identifies current intent and is not
account authentication. The controller chooses a version above the inspected and
locally observed floor; integer exhaustion blocks recovery. It rechecks its scope,
selection, account generation and host workspace/cleanup predicate after every await.

An applied recovery rotates epoch and produces a clean sealed document, no binding
and no writer lease. The controller confirms the exact sealed result before releasing
its local quarantine/barrier; stale acknowledgements cannot authorize a refresh or
cleanup. Uncertain recovery never uses `retryPending`: inspect again and construct
a new immutable operation. A visible old receipt, an ordinary healthy read or a
process restart is not proof of successful synchronized recovery.

## Common mutation arguments

Every request includes exactly `protocolVersion: 1`, `operationId`,
`expectedStoreRevision` and `expectedOwnerEpoch`, plus the fields below.
Only initialize against absence permits both expectations to be null.
Existing-store operations use exact expectations from verified context.
Request digests are computed natively; caller-supplied digests are not accepted.

| Method | Additional fields |
| --- | --- |
| `openWidgetWorkspace` | `mode` (`initialize` or `resume`), `binding` (`kind`: `account`/`guest`, opaque `key`), `presentation` |
| `invalidateWidgetWorkspace` | `presentation` |
| `recoverWidgetStore` | `presentation`, exact current `recoveryContext` |
| `advanceDesiredWidgetPresentation` | `writerLeaseId`, `desiredPresentation` (`revision`, `locale`) |
| `publishWidgetPublication` | `writerLeaseId`, `expectedPublicationRevision`, complete `document` map |

`presentation` has exactly `revision`, `locale` and `values`. The values are the
complete 90-value manifest: all 67 business fields empty/zero/false, all 23
presentation fields captured coherently. Locale is `zh` or `en`; integer values
use the document's explicit Int32/exact-Long ranges. Opaque strings stay literal.
`widget_first_day_of_week` is an ISO weekday integer in `1..7`. New mutations
require all 90 values. Stored-document reads accept only the exact prior
89-value manifest missing this one field and default it to Monday (`1`); unknown
or otherwise incomplete manifests remain invalid. Canonical JSON validation
uses the original stored shape before exposing the normalized document.

The caller supplies a presentation version at least as high as the native floor;
same-version locale or applied brand/theme changes are rejected. A new advance
requires a higher version. A published capture must belong to the current local
day and offset, with no future capture time. Historical document decoding is
independent of this new-publication admission check.

## Acknowledgement and retries

Successful responses include operation identity, committed store revision,
epoch, document publication version, desired/applied presentation versions and
document state. Open additionally returns a new writer lease. An exact ordinary last
receipt replay returns `alreadyApplied`, with no new mutation or effects. Recovery
never replays an applied acknowledgement from a receipt: the same ID/digest stays
`durabilityUnknown` without mutation, and a different digest is invalid. Dart rejects
`alreadyApplied`, lease leakage and refresh requests for recovery.

Retry an uncertain response using its original operation ID and identical
request. Never update expectations on stale content to force it through CAS.
Revalidate account generation, writer lease and presentation before consuming
an asynchronous result. Host-auth validation and the clear-before-model-reset
barrier belong to the Flutter controller, not this codec or channel adapter.

See [store evidence](../evidence/widget-store-core-20261009/summary.md) and the
[approved storage plan](../evidence/widget-publication-descriptor-20261009/native-store-implementation-plan.md)
for durability and remaining runtime acceptance requirements.
