# Todo shared locale batch — source audit, 2026-10-09

## Review boundary and conclusion

Reviewed the stopped production batch in `/home/ubuntu/duoyi-worktrees/todo-shared-locale-20261009`, parent-reported HEAD `1b715503`:

- `lib/core/todo_ui_copy.dart`
- `lib/core/todo_kanban.dart`
- `lib/widgets/eisenhower_matrix.dart`
- `lib/widgets/todo_completion_flow.dart`

Stable dependencies and the baseline completion-flow source in `/home/ubuntu/duoyi` were read only where needed to assess lifecycle and account boundaries. The evolving test fixture was not read. No checks, tests, SDK inspection, network access, or Git commands were performed. This report is the only reviewer write.

**The locale presentation changes are sound at source level. The completion flow still needs lifecycle/account repairs before the full goal is satisfied.** The definite mutation/feedback defects below existed in the baseline source; they are included because disposal and account fences are part of the requested outcome. The new FocusNode also shares an unsafe route-resource disposal boundary with the inherited controller.

## Locale and data behavior

| Requirement | Source assessment |
| --- | --- |
| Matrix refresh | `eisenhower_matrix.dart:32–38` listens locally to `I18n.localeListenable`. Brand strings are fetched inside that builder; `AppBrand.strings` reads the current locale. Empty, completed, overdue, and overflow copy also reads current locale. No locale key or business mutation was added. |
| Dialog refresh | Both dialogs have local locale builders. The duration controller and FocusNode are allocated outside the locale builder, so locale updates retain their identities, text, selection, and focus while the dialog is active. Resource lifetime during dismissal needs the repair below. |
| Snackbar lifetime | `todo_completion_flow.dart:109–119` creates one Snackbar and updates only its content via a locale builder. Its duration is unchanged; locale updates do not replay, hide, or show it. This preserves the original lifetime by construction, pending widget evidence. |
| User title fidelity | Matrix titles and feedback use `t.title` directly. Confirmation, duration prompt, completion feedback, and TimeAudit title interpolate the original title without translation or normalization. |
| Stored keys/titles | Kanban enum order, storage keys, default column IDs/titles, and serialization are unchanged. Localized `.label` does not alter persisted keys. Default/custom stored column titles were explicitly left for a later caller batch. |
| Duration note | `TodoUiCopy.manualDurationNote` supplies current-language copy only when a new manual entry is created. Existing stored notes are not rewritten. The inherited automatic note in `TimeAuditProvider` remains outside this presentation batch. |
| Permissions and actions | Matrix drag source/target checks and callbacks are preserved. No locale listener calls completion or recording. Existing per-ID completion exclusion and its `finally` cleanup remain, but require account scoping below. |

`I18n.setLocale` updates its current value before notifying listeners (`lib/core/i18n.dart:2336–2350`), so these builders see the new language. A Kanban caller must itself rebuild to read the new `.label`; caller listeners belong to the separately planned caller batch.

## Required repairs in `todo_completion_flow.dart`

### 1. Revalidate immediately after the duration prompt, before mutation

**Inherited defect; blocks acceptance.** At lines 65–73, `_showRecordPrompt` is awaited and `completeTodos` is then invoked without another availability check. The mounted check at line 75 occurs after the completion mutation.

If the originating page disappears while the duration dialog is open or dismissing, a still-live TodoProvider can complete the task. The later guard merely prevents recording and feedback. The required outcome is **zero completion and zero time-recording calls from an invalid originating flow**.

Smallest repair: check the captured origin scope immediately after `_showRecordPrompt` returns and before `completeTodos`. Preserve `null`/Skip semantics: skipping duration still completes a valid task.

### 2. Revalidate after every business await and before feedback

**Inherited defect; blocks acceptance.** Lines 83–106 await `TimeAuditProvider.add` or `recordTodoCompletion`; line 109 then uses a messenger cached before the dialogs without rechecking the originating page, account, or messenger.

The page can disappear while time recording is pending. The messenger may be disposed, or may still be mounted and display old-route feedback on a different page. Add a fresh origin-scope check after `completeTodos`, before starting optional time recording, and after time recording before `showSnackBar`. Require `messenger.mounted` at the final use as well. Retain the existing single Snackbar and its local locale builder.

A mutation already validly started before caller disposal cannot be retroactively undone by these checks. Held-await evidence should distinguish preventing subsequent calls from rolling back a previously started provider operation.

### 3. Capture the originating account generation, and scope in-flight exclusion

**Inherited defect; blocks acceptance.** The flow never captures the account at the original interaction. The app reuses providers during account reset (`main.dart:729–776`), and `AccountLocalDataCleaner.invalidateInFlightAccountWrites` increments an available generation synchronously (`account_local_data_cleaner.dart:17–33`).

TodoProvider already fences an operation against disposal/account reset **after that provider operation starts** (`todo_provider.dart:966–1020`, `2230–2238`). This correctly protects an in-progress completion. It cannot reject an old A-account dialog that calls `completeTodos` only after switching to B: that invocation captures B's new generation. TimeAudit saves likewise capture their generation when called, rather than the dialog's origin.

Deterministic case: open A's completion dialog; switch/reset to B while its originating context remains mounted; load B with the same Todo ID; accept/skip the old dialog. Without an origin fence, the provider can complete B's task and accept A's duration/title input as a new B operation.

Smallest repair in this file:

1. Return early for an unmounted entry context before provider lookup.
2. Capture `AccountLocalDataCleaner.accountDataGeneration` at flow entry, before dialogs.
3. Define an origin-availability predicate requiring both `context.mounted` and the captured account generation to remain current.
4. Check it after each dialog/provider await, immediately before completion and recording calls, and before feedback. No await should intervene between a passed check and the ensuing call.
5. Key `_completionFlowInFlightTodoIds` by origin generation plus Todo ID (rename as appropriate). Capture that exact key once and remove only that key in `finally`. A stale A dialog must not suppress an otherwise valid B flow with the same ID; duplicate actions within one origin scope must remain excluded.

This does not require changing stored Todo keys, rewriting provider persistence, or replacing a dialog/route on locale changes. If account invalidation dismisses the active dialog, avoid popping an unrelated route; origin checks remain necessary either way.

### 4. Tie controller and FocusNode disposal to the dialog State

**Inherited controller lifetime gap; new FocusNode repeats it.** `_showRecordPrompt` creates the controller at lines 127–129 and the new FocusNode at line 130, then disposes both in `finally` at lines 178–180 as soon as the `showDialog` result resolves.

The dialog-result Future reports the pop/result; it does not establish that the route's reverse transition and overlay subtree have been removed. The outgoing TextField can therefore still reference already-disposed resources. A locale notification during dismissal can rebuild that retained subtree and reattach listeners to disposed objects. This is a source-level lifetime mismatch; no runtime failure was executed or observed in this review. Immediate controller disposal also exists in the baseline source, while the immediately disposed FocusNode is new.

Smallest robust repair: introduce a private StatefulWidget for the duration dialog **in this same file**. Its State creates the TextEditingController and FocusNode once, builds the existing local locale listener and TextField with those objects, and disposes them in `State.dispose`. `_showRecordPrompt` only awaits the dialog result. Keep the same State, controller, node, selection, and route across locale changes. Keep result parsing and Skip/Record behavior unchanged.

Waiting for a route's actual completed/removal lifecycle could also repair the ownership mismatch, but it requires more route plumbing than State ownership. Merely moving the current `finally` or adding `context.mounted` there does not establish the resources' lifetime.

## Separate inherited dependency gap

`TimeAuditProvider.add` immediately changes `_entries`, awaits `_save`, then unconditionally calls `notifyListeners` (`time_audit_provider.dart:115–118`). `upsertAuto` has the same pattern (`147–158`). The provider has no disposal flag/override. Its save-generation checks protect persistence across resets, but do not prevent a pending operation from notifying a disposed ChangeNotifier.

A flow check **after** this await cannot repair a notification already attempted inside the provider. The bounded flow repairs above can be confined to `todo_completion_flow.dart`; they should not be described as proof that disposing TimeAuditProvider during an already-started recording is safe. If that provider-disposal case is required by acceptance, the smallest additional production scope is `lib/providers/time_audit_provider.dart`: add provider lifetime tracking and guard post-await notifications, retaining existing storage/account-generation checks. Do not broaden this into a storage refactor.

## Evidence required after the production repair

Source review alone does not establish runtime state/lifetime behavior. Useful focused evidence is:

- Toggle zh/en repeatedly with confirmation and duration dialogs open. Confirm one route and one duration State; retain controller/node identity, text, selection, and focus. Use an exact mixed-language/custom title, including spaces and punctuation.
- Switch locale during the duration dialog's dismissal transition; finish the transition without disposed-resource/framework errors.
- Display one completion Snackbar, switch language near its original expiry, and confirm it disappears on the original schedule without replay or a second recording/completion call.
- Hold the duration prompt, remove the originating caller, then return both Record and Skip results: **zero** completion/recording/feedback calls.
- Hold completion or recording awaits and invalidate/remove the origin. Verify no subsequent stage/feedback is invoked; a completion already in progress remains subject to TodoProvider's existing generation fences.
- Switch A→B during each dialog and each held await, keeping the caller mounted and reusing a Todo ID. Verify the stale flow never mutates B, records A input into B, or displays stale feedback. Verify B can start its own same-ID flow.
- Verify duplicate same-account taps remain excluded and each exact in-flight key is released on success, cancel, disposal, account invalidation, and error.
- If provider disposal is included, dispose TimeAuditProvider while its save is held and verify no post-disposal notification/error. A caller-only fake cannot establish this provider property.
- Verify Kanban storage keys/serialized columns and existing entries remain unchanged; confirm Matrix drag permissions/actions still follow their original callbacks.

The caller-disposal fixture described by the parent currently records `completeTodos = 1`; after repair its expected outcome should become zero. This statement is based on the parent's report, not a read of the evolving fixture.

## Reviewed-file fingerprints and freeze

Parent supplied the HEAD above; this reviewer did not run Git. Production SHA-256 values from the stopped reviewed batch:

| File | SHA-256 |
| --- | --- |
| `lib/core/todo_ui_copy.dart` | `d9ed5f0df9fe7f129f4b6c4a6183c495b63e5c598d2890b51c0894dc7886f701` |
| `lib/core/todo_kanban.dart` | `a1bd60b9af50b4f561402c6b7750a5fe635ef6130143da15ffdab7d028cea71e` |
| `lib/widgets/eisenhower_matrix.dart` | `36370581453e3768ecc2e3f1803fd247835cf7f6a54ad27715d166dd113cae69` |
| `lib/widgets/todo_completion_flow.dart` | `60cfa766b9996b62a437da359f1c69c0ddcd73cbc96e730938bdfe0cce30456b` |

**Production reads are frozen at report completion.** No further production reads or writes are needed from this reviewer before the producer's next revision.

## Revision 2 — frozen completion-flow repair

### Boundary and verdict

Parent reported AGY revision `implement-mv0f748p-0838f325` terminal success, absent producer PID, byte-preserved integration of the route baseline, scoped Dart formatting, and all Todo writers frozen. This review read only the resulting `lib/widgets/todo_completion_flow.dart` in the same worktree and obtained its fingerprint. The parent reported the other three shared-target hashes and the separately reviewed TimeAuditProvider hash preserved; those files were not reread in this revision. No SDK, tests, builds, Git, or network operations were performed, and no Mine/Calendar worktrees or evolving fixtures were read.

**Pass for the requested source scope: none of the original four completion-flow must-fix findings remains.** Runtime acceptance remains for root's sequential checks; this verdict does not claim that those checks have run.

### Original findings resolved

| Finding | Revision 2 source evidence |
| --- | --- |
| Entry and account origin | Entry rejects an unmounted context before lookup (`19`). It captures `AccountLocalDataCleaner.accountDataGeneration` (`20`) and passes that original value through the private flow. `isOriginValid` requires both the originating context to remain mounted and that generation to remain current (`35–40`), and is checked before provider lookup (`42`). |
| In-flight scope and cleanup | The key is `(originGeneration, todo.id)` (`13`, `21–22`). A stale A-account flow no longer excludes B's same-ID flow. Same-account duplicates remain excluded. `finally` removes the exact captured key (`23–27`) on success, cancellation, invalidation, or an exception. |
| Dialog → next mutation | Confirmation checks result and origin immediately after its await (`77`). Duration result checks origin immediately after its await (`84`), before `completeTodos` (`86–88`). No await intervenes between each passed check and the next stage. Skip/null still proceeds to completion when the origin is valid; invalid origins perform no completion call. |
| Completion → recording | Immediately after `completeTodos`, changed-zero or invalid origin returns (`89`). Both manual and automatic recording branches follow synchronously (`91–120`), with no additional await before their guarded invocation. Existing provider-generation protection still governs a completion already started before invalidation; the UI check prevents the next stage. |
| Recording → feedback | After either recording branch's await, the common continuation checks origin and `messenger.mounted` (`123`) before the sole `showSnackBar` (`125`). Disposal/account invalidation suppresses subsequent feedback, including use of a disposed cached messenger. |
| Duration resource lifetime | `_RecordDurationDialog` is a private StatefulWidget (`151–162`). Its State creates the late-final controller and FocusNode once in `initState` (`164–175`), uses those same objects in the TextField (`197–199`), and disposes them in `State.dispose` (`177–182`). `_showRecordPrompt` now only returns the dialog Future (`137–149`); resource disposal is no longer tied to the pop/result Future. Resources therefore survive the outgoing route subtree until State unmount. |

### Locale, state, and data behavior retained

- Confirmation remains a local locale builder (`58–75`); the duration State contains its own local locale builder (`185–227`). Neither route nor duration State has a locale-dependent key. Controller/node creation and numeric initialization are outside the locale rebuild, preserving their identities, entered text, selection, and focus.
- The duration content uses `widget.todoTitle` directly (`195`); confirmation, manual/automatic TimeAudit title paths, and feedback likewise use the original/current Todo title directly. No title translation or normalization was introduced by this repair.
- Snackbar creation still occurs once; only its content listens to locale (`125–134`). Its duration is not overridden and no locale callback hides/replays it, preserving the original-lifetime design.
- The numeric keyboard, initial clamp, parsing, invalid-value/null behavior, Skip/Record actions, dedupe keys, and manual note path remain. This repair introduces no persistence-key/schema/column-title changes and no locale-driven business calls.

The earlier focused evidence requirements still apply, especially caller removal after the duration prompt, A→B reuse of a Todo ID, held completion/recording awaits, same-State locale switching, and locale switching during dismissal. The separate TimeAuditProvider report describes provider-owned lifetime protections and inherited delegated-helper/reload boundaries; those are not reopened or reclassified by this flow review.

### Revision 2 fingerprint and freeze

Reviewed `lib/widgets/todo_completion_flow.dart` SHA-256:

`d7e4796da8d8bebf0912ff707ac76db5e62b3a674a6778e603f36d55b6f751b7`

**Revision 2 production reads are frozen.** No production edits were made by this reviewer.
