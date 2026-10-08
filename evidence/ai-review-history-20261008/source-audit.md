# AI review history account boundary — final core contract and source audit

Date: 2026-10-08. Integration source: `/tmp/duoyi-update-deploy-20261005-isvisjkp/source`.

Read the private `ai-review-boundary-decision-oct8.md` and `ai-weekly-review-account-contract-oct8.md`, actual AiService, main startup/cleanup/client binding, AccountLocalDataCleaner, AuthProvider's hydration/login/logout/ownership callbacks, and ApiClient's mutable client identity fields. Root owns production and fixtures. This auditor performed only source/text reads and wrote this private report; no tests, analyzer, builds, Git, network, process intervention, production edits or fixture edits. The user-supplied HEAD label was not checked through Git. Unfinished fixtures and root verification are not evidence for this source verdict.

## Decision: use the existing auth availability state

An account epoch listener alone cannot close the entry window. Cleanup increments the epoch before it finishes and before AuthProvider replaces the departing client. A request starting in that interval can capture the new epoch with the old client and, without an availability gate, treat departing-account data as current. Clearing old cache synchronously solves the cached result variant but does not stop a new network request using the old client or new hydration reading departing preferences before removal.

The smallest robust integration gate is the existing AuthProvider state:

```dart
!authProvider.isAccountTransitionInProgress &&
!authProvider.isLocalAccountDataBlocked
```

Bind it to an optional `AiService.historyAccessAllowed` callback when constructing the service, before startup/auth hydration can launch. With no callback, default to allowed for standalone service use. No new global cleaner flag or auth dependency inside AiService is needed for this actual application lifecycle.

The gate is about account-scoped history access, not AI configuration or whether a user is signed in. Do not add `isLoggedIn` to it: the actual AuthProvider deliberately preserves an unowned guest workspace and adopts it on first login. Local history hydration/cache reads must remain possible for that accepted guest workspace and standalone callers. Network functionality still obeys the existing AI-enabled/server/API authentication contract.

### Actual lifecycle evidence

| Path | Source evidence | Ownership/availability consequence |
| --- | --- | --- |
| service construction | main:623 creates AuthProvider; :641–644 creates AiService and assigns the availability closure | closure is installed before critical startup/auth loading and before app pages exist |
| startup auth hydration | auth_provider:241–258 sets both blocked and transition before its awaited queue/load; main calls it at :1005 | history access is closed while stored owner validation/cleanup is pending; hydration failure/timeout keeps the local blocked state closed until successful recovery |
| hydrated state | auth_provider:262–290 validates stored ownership, applies state/client and persists owner before unblocking | restored data cannot be treated as available before ownership validation |
| initial AI binding/loading | main:1953 attaches the auth client; :1960–1963 installs auth listener that reattaches; :1099 is the deferred AI load closure | the deferred declaration is not an early AI read; normal deferred startup occurs after binding, including post-frame startup. Auth recovery resets deferred hydration and reloads through the same guarded path |
| login/account application | auth_provider:407–438 marks transition before queued ownership cleanup; applies next state/client only after cleanup callback | old client remains attached during cleanup, but the availability gate is false. Final auth notification reattaches the new client synchronously before a normal later caller runs |
| logout/session cleanup | auth_provider:635–670 / :712–726 mark transition before cleanup callbacks and client replacement | new history requests cannot start while the departing session is being cleared |
| application cleanup | main:733 invalidates account writes; :772 first preferences pass; :824–829 reset/drain; :851 final preferences pass | service epoch listener immediately clears/tag-invalidates cache, and the auth gate stays closed throughout the asynchronous cleanup |
| hard auth preferences pass | auth_provider:1727–1769 awaits the application cleanup callback, then calls cleaner again before account application completes | the final extra epoch bump is also seen synchronously by AiService; there is no reopen between app-level and auth-level passes |
| guest adoption | auth_provider:1773–1801 accepts unowned guest data on first login without necessarily bumping the account epoch | captured client/token/baseUrl ownership supplements the two numeric epochs for pending work spanning that login; existing guest cache import is preserved |

Auth startup can continue after `_startupGuard`'s timeout without canceling the underlying hydration Future. This is why the gate needs the local-blocked property as well as the transition property; successful later recovery can reopen/reload safely, while an unfinished/failed owner validation does not become available merely because main moved on.

## Core operation contract

1. Preserve `Future<String>` for all review-producing APIs. Use `AiReviewDiscardedException extends AiException` with stable code `review_discarded` for terminal/stale work rather than returning old content, an empty string or a generic network failure. It retains API/source compatibility and gives a later page owner a distinct cancellation case.
2. Each history operation captures the account invalidation epoch and service storage epoch before accessing cache, starting network work or obtaining preferences. It also captures ApiClient identity and the client's token/baseUrl, because those public fields are mutable and a first guest login need not change the account epoch. Capture the request model for entry metadata; a later config refresh must not relabel an earlier result.
3. One current predicate includes service lifetime, availability gate, both epochs, cache's account tag and client identity/fields. Require it before network, after network success and error, before append/write, when a queued write starts, after preferences acquisition, after persistence, after notifications and immediately before producing the successful string. Stale errors become the typed discard; current real errors retain their original behavior.
4. The epoch listener synchronously clears history, updates ownership, invalidates storage/load work and notifies. Detach on disposal. Public history getters and weekly cache lookup hide rows while unavailable or owned by another epoch. Producer/delete/clear entries reject unavailable history; startup load skips neutrally rather than treating a blocked account as a startup error.
5. Serialize physical history writes through one service queue. Capture an immutable serialized snapshot before enqueue and retain its operation identity; never serialize a later mutable history list from an older queued closure. Live appends/deletes/clears update memory synchronously, so their snapshot order is established before queued asynchronous writing. Private queue recovery can observe prior errors without preventing later cleanup/retry.
6. Hydration must also avoid replacing newer live mutations. Capture a history revision, await the existing write barrier, and recheck operation/revision before and after preferences acquisition. Increment revision on invalidation/reset/append/delete/clear. An old load spanning account cleanup, client replacement, disposal or a new history mutation then cannot install rows.
7. Do not put pending network calls inside the physical write drain. Once access/epochs are invalidated, late network completion cannot enqueue a new write; only already-issued or queued persistence needs draining before the final preferences removal.

## Drain and failure behavior

The account gate must be closed and storage/account identities invalidated **before** draining. A drain loops over the physical write tail until the tail is unchanged after awaiting it. This observes an already-issued `setStringList` and also any earlier queued closures. Queued stale entries fail their identity check before issuing storage work; these ordinary discards are not a cleanup failure. No successful drain is claimed while a physical write can still settle later.

A write already inside `setStringList` cannot be revoked by an epoch change. Wait for it to settle, then perform the final preferences clear. That final clear is essential even when the write's consumer receives a discard after the platform call: discarding a returned result does not cancel an issued storage operation.

Keep actual platform failures separate from queue sequencing recovery. A thrown setter error or a `false` setter result is recorded with its stack; drain reports the recorded failure after the queue settles, even if the operation's consumer sees discard because its account became stale. A false result is a typed live history-save error (`AiReviewHistoryWriteException`, code `review_history_write_failed`), not successful persistence. The application awaits drain as a critical cleanup task. Cleanup does not approve logout/account application after a drain error; the existing critical failure path throws AccountLocalDataCleanupBlockedException and leaves the valid departing session available to retry.

The current drain has no timeout shortcut and does not launch an unobserved background wait. Its failure latch is consumed when reported; a later cleanup retry can drain the now-settled queue and perform a new final clear rather than permanently failing on a historical error. A failure before a platform write was issued may still reach the operation caller/log, but there is no pending write to outlive the clear. The required persistence failure guarantee concerns issued setter failures and false results.

On a blocked cleanup failure, AuthProvider's transition finally may reopen access to the still-active old account after unwinding; that is compatible with the existing retry contract. No new account has been applied, and the physical history writes were already settled before drain raised its recorded failure. Startup ownership-validation failures remain blocked via `isLocalAccountDataBlocked`. Do not introduce a permanent AI-only suspension without a recovery owner; it would strand normal login/startup retry flows.

## Actual corrected source audit

Root supplied a formatted AiService/main handoff, then added load revision checks and the typed bilingual false-write error before verification. Reread the newest actual files and all history producers/mutators/getters, queue/load/drain/epoch/disposal helpers, early binding and cleanup placement. No fixture or runtime result was used.

| Actual boundary | Final source | Result |
| --- | --- | --- |
| early auth gate | main:641–644 | availability closure is bound at creation, before main's initial auth hydration |
| immediate cache ownership/lifetime | ai_service:39–55, :140–147, :153–158 | constructor subscribes, epoch synchronously clears/tags/revisions; disposed flag and listener removal suppress future history work; getter hides unavailable/foreign history |
| complete operation identity | :58–83; _AiHistoryOperation near :1268 | account/storage/lifetime/access/client/token/baseUrl all represented; model captured for metadata |
| network completion/error | _reviewChat:87–108 | current checked before chat and after both success/error; existing response-only _chat flows remain outside history scope |
| shared append and successful return | _appendReview:110–124; producers :361/:427/:453/:492 | all four persisted producers use the helper and recheck again after awaiting it; post-notify identity check prevents a synchronous listener invalidation from returning stale content |
| cache return | weeklyReview:369–375; weeklyReviewForDay:478–490 | entry/current guard plus account/access-owned lookup; cache cannot be newly served during cleanup |
| ordered immutable persistence | _saveHistory:212–245 | snapshot is serialized/frozen before enqueue; checks at dequeue, after obtaining prefs, after setter and after write Future; stale notifications suppressed |
| physical failure preservation | :221–237; drain :127–138; exception :1255–1266 | setter throw/false archived before queue recovery, drain waits stable tail then throws recorded original error/stack; live false-write error is typed and bilingual |
| hydration versus mutation | loadFromStorage:175–201 | captures operation+revision, awaits write barrier, checks both after awaits; no stale account/new-row restoration; old per-row parsing behavior retained |
| local history mutations | deleteReview:247–253; clearReviewHistory:255–261 | capture full token before mutation; revision advances, notification and save remain current-gated; mutation snapshots serialize with producer snapshots |
| cleanup ordering | main:823–829, :849–855 | reset/invalidation precedes awaited critical drain; final account preferences pass occurs after drain settlement; critical error blocks account handoff |
| compatibility/errors | discard :1244–1253; original review signatures intact | typed cancellation preserves Future<String>, current AI errors/normalization/history cap and legacy weekly-summary cache matching preserved |

Final reviewed hashes:

| File | SHA-256 |
| --- | --- |
| `lib/services/ai_service.dart` | `1c6c116ffdb231507f6b0aa2cf79dfcff77e794531f42f3d4c804c8651328f44` |
| `lib/main.dart` | `f206c1324df231dabb55c79811f2c512632375eed895473f0e1e6630bf40c6fd` |
| `lib/services/account_local_data_cleaner.dart` (lifecycle reference) | `5ed7b9831db9cd4b64839c2dba1f1d6fc33fe6a834bd88572091f96f474edc57` |
| `lib/providers/auth_provider.dart` (lifecycle reference) | `d695f7e8bf227a2167bc8ffce4a00f741175ff1e117cc0ee431e14f71055083a` |

**Final bounded core source verdict: no remaining concrete blocker found.** The current auth gate closes the new-epoch/old-client entry window. Epoch/client checks suppress old load/cache/network/history work; revision checks prevent older hydration replacing newer mutations; the stable physical write drain plus final clear prevents an issued departing-account write from restoring history after the completed account boundary. This is source review, not verification or deployment.

## Required remaining page ownership

This core result does not clear Mine/Statistics/Diary page-local strings, a previously opened review dialog, or an AI History screen's already-retained list copy. Existing catches of AiException may currently display the localized harmless discard message; page owners should catch AiReviewDiscardedException first and exit quietly. Each page still needs its account/lifetime check after the service Future returns and before applying text or opening a dialog. A service cannot revoke a string that completed successfully just before the later account change; that post-return race belongs to the caller. Response-only schedule/task-breakdown/connection flows and presentation redesign remain outside this history correction.

## Frozen 15-case fixture scope review

Read the actual new `test/services/ai_review_account_boundary_test.dart` during root's frozen regression. Did not execute it, modify it, inspect the running process, or treat fixture assertions as passing runtime evidence. Production remained AiService `1c6c116f…` / main `f206c132…` during this read.

Fixture SHA-256: `53e359eaa0607e72f8ff83f464b1ca2614b52fe518fa1a34be676e7aabed2b5a`

| Cases read | Count | What the source assertions actually exercise |
| --- | --- | --- |
| all four producers × stale success/error | 8 | held network result/error after ApiClient replacement; typed discard, no history or prefs row |
| standalone epoch cache | 1 | same-day cache hit before invalidation, immediate cache clearing before reset, fresh standalone request invalidated by another epoch bump |
| reset/disposal | 1 | held preference hydration invalidated by storage reset; held review invalidated by reset and another by service disposal |
| live four-producer loop | 1 | live result string and four in-memory/persisted rows remain supported |
| access gate/client fields | 1 | an initially unavailable fresh service rejects weekly network work; held result discarded after simultaneous token/baseUrl mutation |
| immutable snapshots/delete/clear | 1 | physical first write held; delete/clear enqueue empty snapshots; drain waits; exact snapshots/ordering and real cleaner removal checked |
| active old write drain | 1 | setter already issued, epoch/reset while held, drain remains pending, stale caller/notification suppression, then real physical cleanup after settlement; main text asserts early gate placement and drain ordering |
| live false write | 1 | personalized review receives typed save failure; drain reports same failure once; physical store lacks the row |

These are substantial targeted fixtures. They do not execute the actual main/AuthProvider transition or prove any page-local state behavior. The active-write test's held gate is the **platform write gate**, not the auth availability callback. The standalone epoch test deliberately permits a fresh request after invalidation; production's auth gate remains a separate requirement.

Material contract combinations not directly exercised, with minimal root-owned follow-ups after the frozen run stops:

1. **New epoch while auth access remains closed and old client/preferences still exist.** Seed/load a cache, close an `allowed` callback, bump account epoch without replacing client or physically clearing prefs, then invoke producer/cache/load/delete/clear paths. Producers/mutators must throw discard without transport/writes; getters hide data; load completes neutrally without a hydration notification. Then drain/real cleanup and reopen using the new client, confirming live work is still possible. One composed fixture exercises the critical new-epoch/old-client entry gap; the existing fresh initially-false weekly call alone does not.
2. **Hydration revision without reset/epoch change.** Hold preference acquisition for a load containing old stored rows; call clearReviewHistory while the load is suspended; release preferences and settle load/write/drain. History and physical store stay empty and the loader does not notify/install old rows. This specifically exercises the revision check; the existing delayed load is invalidated by storage generation instead.
3. **A real setter failure after stale invalidation.** Hold a physical write, invalidate/reset, then make its store result false or throw. The producer sees discard, but drain still throws the recorded actual persistence failure after physical settlement, then a subsequent drain can complete. This is the important combination behind the separate failure latch; the existing live false-write and stale-success cases cover its halves separately.

No additional full-application audit or page fixtures are implied by this list. Separate baseUrl-only/token-only tests would isolate each mutable client field, but the current combined rotation case already exercises the bounded client-change behavior; they are secondary to the combinations above.

## Newly confirmed failed-save cache issue — correction pending

During this fixture review root raised a concrete persistence/cache consequence of the new false-write failure semantics. Source confirms it: `_appendReview` inserts into memory before persistence; a live false `setStringList` produces AiReviewHistoryWriteException but leaves that entry in memory; `weeklyReviewForDay` has no persisted-status filter and a subsequent weeklyReview returns it as a successful cache hit without retrying persistence. A second weekly call while the first write is still pending can also return that unconfirmed row immediately. The existing false-write fixture uses personalizedReportReview and never performs a subsequent weekly cache read/load, so it cannot reveal this issue.

This does not reopen the already-reviewed old-account token/gate/drain findings; it is a newly identified live failed-save-to-successful-cache gap. The earlier source verdict was bounded to account privacy/lifetime, and an overall confirmed-persistence/cache verdict must now wait for this correction.

Simply restoring a pre-append list after error is unsafe because it can undo a concurrent delete/clear/new append. A rollback restricted to the same append revision can remove the failed object in the uncontended case, but does not prevent cache hits on an unconfirmed row when another mutation changed the revision. It also does not prevent the early cache success while the setter is pending.

Recommended smallest robust ownership rule: track confirmed persistence by **AiReviewEntry object identity**, not its millisecond ID. Newly appended rows are unconfirmed; only a true setter result from a current operation confirms the objects in that exact immutable snapshot. Weekly cache lookup must skip pending/failed objects. A later successful snapshot that includes an earlier failed row can validly confirm it then. Load may confirm genuinely stored rows; account/reset invalidation clears confirmation state. This retains later live mutations and avoids rewriting the entire list on an old error. Same-revision removal of a failed object can be a separate presentation cleanup if needed.

One additional source fact matters for load: the dependency's legacy SharedPreferences setter changes `_preferenceCache` synchronously **before** awaiting its platform store, and a false result does not revert it (`shared_preferences-2.5.5/lib/src/shared_preferences_legacy.dart:177–186`, read locally). A later direct `getStringList` can therefore return an uncommitted row even when the physical store is empty. Confirming rows from that cached value would recreate the same gap. Root's correction must read genuine storage when cache contents may be unconfirmed (reload with ownership/revision checks or another explicit trust rule), rather than silently marking the failed preferences cache as durable. The dependency reload reads the host map and replaces its process cache at :223–228; its extra await and shared-cache side effects must be considered in the chosen correction.

Minimal failure/cache fixtures: generate a weekly row with a held/false write; attempt a same-day cache read while pending and again after failure; neither may report that unconfirmed row as a successful confirmed cache. Add a subsequent load after the failure with physical storage empty, and a concurrent mutation variant so a blanket list rollback cannot pass by undoing later work. A later successful snapshot may confirm its included rows and restore legitimate cache hits. Root will make any implementation/fixture changes only after the current frozen run stops; this auditor has not modified source or tests.

## Dirty/revision alternative — actual first implementation review

Root chose a whole-history dirty flag instead of per-entry durability identities. Actual AiService read at SHA `024f4b62bea9664f1f81347f9b768a24d7293e6925a6349f017645b44598655d` sets dirty on append/delete/clear; `_saveHistory` captures snapshot revision and clears dirty only after a true current platform write and unchanged revision. Epoch/reset clear dirty with the memory they invalidate. Weekly Future cache calls retry persistence of the existing row while dirty, avoiding another AI request/duplicate entry. Load waits the write barrier, skips when dirty, otherwise reloads real preferences and rechecks operation/revision/dirty after each wait; successful hydration increments revision so a later concurrent load cannot override it.

This is a valid, more conservative alternative for the requested contract. Any dirty history can require a full-snapshot write even if the particular weekly row was previously durable; it avoids entry-status bookkeeping and preserves all later mutations. An older successful snapshot cannot falsely clear a later mutation's dirty flag. A failed setter's cached value is not hydrated while dirty; a subsequent clean hydration uses a real host reload and still requires current operation/revision after that await. No blanket rollback restores an old list. Existing account access/token/drain behavior remains intact in this first implementation.

**One concrete public-cache bypass prevents a clean verdict for this hash.** `weeklyReviewForDay` still returns a dirty row. Actual Mine calls that public method in didChangeDependencies (:2109) and `_run` (:2119–2128); those paths set `_generatedToday = true` and return without ever entering weeklyReview's new persistence retry. Thus a failed/pending write can still become a confirmed UI cache hit through the service's public synchronous cache API. This is a bounded service API correction, not a request to take ownership of the page.

Minimal completion: public weeklyReviewForDay must return null while `_historyNeedsPersistence` is true. Extract its traversal into a private `_findWeeklyReviewForDay`; weeklyReview's already-guarded operation uses that private finder to locate a dirty existing row, retry its snapshot and return without regenerating AI. The public method retains existing availability/account checks and only publishes clean cache entries. Add fixture assertions for public lookup during held/false persistence and after a successful retry. Final corrected-source hash/verdict remains pending this fix.

## Final dirty-cache correction audit

Root implemented the public/private lookup separation and formatted the actual AiService. Reread production plus main's unchanged early gate/critical drain. The source observations below close the pending failed-cache item; fixtures were still being extended separately, and no runtime result is attached to this new hash by this auditor.

**Latest audited AiService SHA-256:** `9be2268481ed1154d453fac5ae1d6c25e0248ff4077444b3ff2583606c01a77c`

**Main SHA-256 (unchanged):** `f206c1324df231dabb55c79811f2c512632375eed895473f0e1e6630bf40c6fd`

| Final source property | Actual source evidence | Closure |
| --- | --- | --- |
| public synchronous cache eligibility | weeklyReviewForDay:497–505 | returns null for unavailable, foreign-account or dirty history; Mine's two direct lookup paths cannot treat a failed/pending row as confirmed |
| existing-row retry without another AI request | weeklyReview:387–394; private finder:507–514 | internal guarded lookup finds the retained row, dirty cache hit awaits its snapshot save, current identity is checked before returning; false/throw propagates rather than becoming cache success |
| physical success versus later mutation | _saveHistory:226–261, revision/dirty changes :118–119/:266–267/:275–276 | only a true current platform result with unchanged captured revision clears dirty; an earlier snapshot cannot clear a later append/delete/clear's dirty state; no old list rollback overwrites live mutations |
| failed setter preferences cache | loadFromStorage:178–213 | after the queue, dirty load returns without adopting preferences cache; clean load reloads the host map and rechecks operation/revision/dirty after reload before assignment |
| concurrent/stale hydration | load :181–200/:212 | checks after write barrier, preferences acquisition and host reload; successful load advances revision, invalidating another concurrent load that captured the old revision |
| reset/epoch dirty ownership | epoch :50–58; reset :215–224 | clear dirty only with cleared owned memory and invalidated storage identity; clean subsequent load reads genuine host state, so a failed setter's retained process cache cannot resurrect a row |
| unchanged account boundary | full operation predicate :70–80; drain :130–141; main :641–644/:824–854 | access gate remains bound before auth startup, identity includes epochs/client fields, issued writes settle before final preference removal, and archived setter failure remains a critical drain error |

The whole-history dirty scheme is intentionally more conservative than per-entry durability: an unrelated dirty mutation can hide otherwise saved weekly cache rows and require rewriting the current history snapshot. It is a valid chosen contract and does not create duplicate AI entries on cache retry. A successful retry's immutable snapshot includes the cached row being returned; later simultaneous mutations keep their own dirty status until their snapshots succeed. Public lookup stays hidden while such current history is still dirty. No claim is made that a successful earlier row return commits all later unrelated mutations.

**Latest bounded core source verdict: no remaining concrete blocker found for the account/history/persistence-cache contract.** The failed-save/pending-write public cache success path is closed in this actual hash, as are old-account application, stale hydration and queued-write restoration paths documented earlier. This supersedes the initial clean hash and the intermediate dirty-cache blocker. The 15-case fixture source review remains valid for that original matrix only; added dirty/cache/combined cases and fresh frozen regression/analyzer results are still root-owned and pending here. No tests, analyzer, Git or production edits were performed by this auditor.

## Final expanded fixture source review — actual 24-case file

Root handed off a claimed frozen 23-case fixture at `ff4a9881…`; the actual file read by this auditor was different. Root subsequently confirmed another agent changed it after the run began and will not accept that running result as verification of the changed file. This auditor did not intervene in that process. The scope review below is bound only to the actual fixture hash read:

`7390a8c6a2ed47d494b3f3cdb161b776233668352d821e43c2b355852437129f`

Actual expansion is **24** runtime cases: eight producer matrix instances, fourteen individual tests, and two clear/append hydration loop instances. Reset and disposal are now separate tests. AiService/main hashes still match `9be22684…` / `f206c132…`. No test, analyzer or Git command was run by this auditor, and no repository file was edited.

Material additions actually present:

| Fixture | Source assertions | Contract supported |
| --- | --- | --- |
| false weekly write → load → true retry (:426) | typed initial error, public cache null, physical store absent, dirty load retains the exact same object, retry same content/id with only one AI request, physical row and public cache restored, snapshots [1,1] | failed-save state is not a successful public cache; dirty retry saves retained data rather than generating another row |
| two false weekly writes (:488) | second call still throws, no successful string, one AI request, same single memory row, public cache null, two one-row setter snapshots | retry cannot bypass a second physical failure |
| held pending weekly write (:542) | public lookup null, cached Future remains pending before gate release, one AI request, same row/result after release | pending memory does not become an early confirmed cache hit |
| old true snapshot with newer append/delete failures (:595) | result sequence [true,false,false,true], memory preserves delete, cache remains null after first old success and later failures, dirty load preserves current memory, retry's last snapshot/store contains only the surviving weekly row | old snapshot cannot clear later dirty revisions or roll back newer mutation; successful retry persists the current list |
| closed history gate after epoch bump (:735) | old client and old physical preference row retained, service getters hidden, neutral load, weekly/delete/clear discard, zero AI requests/snapshots | production's new-epoch/old-client gate interval has a direct composed service fixture |
| active false write after invalidation (:1040) | setter held before epoch bump, caller sees discard, drain raises real save error once then completes, real cleaner removal leaves physical store empty | queue recovery cannot erase the actual failed issued-write outcome from cleanup |

The old four-producer stale success/error and live loops, physical drain ordering, immutable delete/clear snapshots and false-write once-only drain fixtures remain present. The expanded cases directly close the important failed-cache/public-getter, gate and stale-physical-failure assertion gaps identified above. They remain fixture source evidence, not proof that these assertions passed.

### Two remaining material fixture weaknesses

1. **Late old hydration snapshot is not actually supplied by the clear/append cases (:807–871).** `_TestPreferencesStore.getAllWithParameters` (:144–155) waits for its gate **before** reading `super`'s map. While reload is held, each tested mutation updates physical storage; releasing the gate therefore gives the loader the new data, not a stale old snapshot. The asserted result can remain correct even if the post-reload revision fence is removed. The cases exercise a held reload and live mutation, but do not independently prove the claimed stale-hydration fence. Minimal correction: for these cases only, capture the host map before signaling/awaiting the gate and return that captured old map after release. Then the old snapshot must not replace current cleared/newly appended memory. Use an optional store behavior so other hydration/setup cases retain their existing semantics.
2. **Clean reload after a failed setter is not yet exercised.** The false→load→retry case exercises the dirty early return; it never enters the new host reload because dirty stays true. Add one direct case: false write, assert legacy prefs cache contains the attempted row while physical store does not, resetLocalState to clear owned memory/dirty, then loadFromStorage and assert history/public cache remain empty after host reload. This isolates the dependency-cache consequence and proves clean reload does not confirm an uncommitted cached row.

Reported these minimal fixture changes to root for after the current running process terminates. They do not require a production correction; the existing reviewed source contains the necessary revision and host reload guards. The bounded production source verdict remains clean, with final runtime evidence pending a genuinely frozen, matching fixture hash and the follow-up assertions above.

## Final fixture corrections — source review of the frozen 25-case file

Read the two requested fixture corrections after root archived the earlier session `8068` as non-final evidence because its fixture changed after launch. This review is bound to fixture SHA-256:

`714039137c5ed234efbf76b85f14fa221a047225977c87072f433a96f0645fde`

Actual expansion is **25 cases**: eight producer/stale-response matrix instances, fifteen individual tests, and two clear/append hydration loop instances. The source-only conclusion below does not establish that those assertions passed. Root identified frozen regression session `35166` for this hash; this auditor did not inspect or intervene in the run.

| Correction | Actual source evidence | Conclusion |
| --- | --- | --- |
| Capture an old host snapshot before the held reload | `_TestPreferencesStore.getAllWithParameters` :147–160 optionally reads `super` before signaling and awaiting the gate; clear/append cases :841–918 enable `captureReadsBeforeGate` after initial preferences acquisition and await the mutation before releasing the read | The suspended reload returns the seeded `cached-weekly` snapshot even though the live mutation has already changed memory and physical storage. Empty/current-new-row assertions now distinguish a correct revision fence from stale snapshot replacement. The option defaults to false for other fixtures. |
| Clean host reload after failed setter cache pollution | New test :546–584 makes the weekly setter return false, asserts the SharedPreferences process cache contains one attempted row while the host has no history key, resets local state, then loads | The assertions directly exercise the clean host reload path: memory remains empty, public weekly cache remains null, and the same SharedPreferences object's cached history becomes null. One recorded setter snapshot and the retained drain failure also prevent a silent persistence retry from explaining the result. |

The captured map is a stable old snapshot for these mutations: the locally read InMemorySharedPreferencesStore dependency returns a new map, and its setters replace stored list values rather than mutating the old captured list. Capture happens before the read-start signal, so awaiting `getAllStarted` establishes that the old data has already been obtained.

Both material fixture weaknesses in the preceding section are closed by this actual file. **No remaining concrete blocker was found in the bounded source/fixture contract review.** Runtime acceptance still requires root's completed verification against the matching frozen fixture; source assertions alone are not passing runtime evidence.

Production hashes were rechecked and are unchanged:

- AiService: `9be2268481ed1154d453fac5ae1d6c25e0248ff4077444b3ff2583606c01a77c`
- main: `f206c1324df231dabb55c79811f2c512632375eed895473f0e1e6630bf40c6fd`

Only this private report was edited. No production/fixture edits, tests, analyzer, builds, Git, network calls, or process intervention were performed by this auditor.

## Final mechanical fixture cleanup and hash binding

Root reported that the frozen `71403913…` fixture regression completed with **669 passing checks**. Root's analysis of 54 paths reported only `unused_local_variable` for `cachedReview` at the then-current line 599, and root terminated analysis session `63883`. These are root-reported verification results for the preceding hash; this auditor did not run or inspect those processes.

Root removed exactly the unused `Future<String>? cachedReview` declaration and its assignment. Source reread of the pending-platform-write fixture confirms the observed Future (`cachedObserved = pendingCachedReview.then(...)`), the pending/completion/cache assertions, and `finally`'s `await _ignoreFailure(cachedObserved)` remain. The cleanup does not alter the fixture's assertions, asynchronous observation or teardown contract; the 25-case source verdict above carries forward.

**Final fixture SHA-256:** `bd34d0c5f4b7631cc499888cc91c99a3fe99d8c35ed267eb7ccc059a399ce708`

Both production hashes were reread and remain AiService `9be2268481ed1154d453fac5ae1d6c25e0248ff4077444b3ff2583606c01a77c` and main `f206c1324df231dabb55c79811f2c512632375eed895473f0e1e6630bf40c6fd`. No production correction accompanies this two-line fixture cleanup.

Root archived both preceding checks and identified restarted regression session `87012` to obtain final checks bound to `bd34d0c5…`. Final runtime acceptance for that new hash remains root-owned; the earlier 669-check result is not relabeled as a run of the changed file. This follow-up edited only the private report and performed no repository edits or verification commands.
