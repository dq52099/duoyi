# Widget publication channel

Android host channel: `duoyi/widget-publication`. The application-scoped store
runs operations on a bounded background queue. This adapter is registered per
Flutter engine; a detached engine does not receive a late response. A committed
operation survives messenger disposal and can be recovered by its receipt.

## Current integration status

The native store, Android bridge and Dart wire adapter are implemented. Flutter bootstrap, publisher and
cleanup paths, Android renderer reads and the equivalent iOS store are not yet
switched to this protocol. Existing widgets still use the existing path.
An `applied` response confirms canonical storage, not launcher display.
The adapter currently returns `refreshRequested: false` for mutation results.

## Dart adapter

`lib/services/widget_publication_client.dart` provides typed reads and immutable
open/invalidate/advance/publish requests. Read facts carry no writer lease;
only a validated open acknowledgement returns that capability. The adapter
checks exact response shapes, operation identity, the next store revision and
the expected document/presentation result before exposing a committed response.

Keep the original `WidgetStoreRequest` when a response is uncertain. The default
15-second response deadline bounds the Flutter wait and does not cancel a
native transaction. A mutation channel error or deadline returns
`responseUnknown`; malformed responses return `invalidResponse`. Neither is
permission to advance an accepted cache, retry with new expectations or fall
back to preference data. The adapter performs no automatic retries, workspace
bootstrap, account-generation checks or launcher refresh. Those responsibilities
remain with the forthcoming publication controller and renderer integration.

## Read

`readWidgetStore` takes no arguments (an empty map is also accepted).
It returns `status` and, for a healthy store, revision, binding, epoch,
lease state, desired presentation, full document and last operation identity.
It never returns the writer lease. Absence, corruption, unsupported versions,
busy/unavailable storage and unknown durability are distinct outcomes.

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
| `advanceDesiredWidgetPresentation` | `writerLeaseId`, `desiredPresentation` (`revision`, `locale`) |
| `publishWidgetPublication` | `writerLeaseId`, `expectedPublicationRevision`, complete `document` map |

`presentation` has exactly `revision`, `locale` and `values`. The values are the
complete 89-value manifest: all 67 business fields empty/zero/false, all 22
presentation fields captured coherently. Locale is `zh` or `en`; integer values
use the document's explicit Int32/exact-Long ranges. Opaque strings stay literal.

The caller supplies a presentation version at least as high as the native floor;
same-version locale or applied brand/theme changes are rejected. A new advance
requires a higher version. A published capture must belong to the current local
day and offset, with no future capture time. Historical document decoding is
independent of this new-publication admission check.

## Acknowledgement and retries

Successful responses include operation identity, committed store revision,
epoch, document publication version, desired/applied presentation versions and
document state. Open additionally returns a new writer lease. An exact last
receipt replay returns `alreadyApplied`, with no new mutation or effects.

Retry an uncertain response using its original operation ID and identical
request. Never update expectations on stale content to force it through CAS.
Revalidate account generation, writer lease and presentation before consuming
an asynchronous result. Host-auth validation and the clear-before-model-reset
barrier belong to the Flutter controller, not this codec or channel adapter.

See [store evidence](../evidence/widget-store-core-20261009/summary.md) and the
[approved storage plan](../evidence/widget-publication-descriptor-20261009/native-store-implementation-plan.md)
for durability and remaining runtime acceptance requirements.
