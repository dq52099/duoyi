# Widget publication current source audit — 2026-10-11

## Scope and result

Read-only review of the main working tree at HEAD `8f9606791cfd63fa087e65e52e63be837913e407`, with source inspection of the Android canonical document, envelope, transition, store, Snapshot intake, frame core, frozen preferences, render projection, native action construction/transport, Dart publisher/action validation, and the relevant preview/copy consumers. Unrelated existing working-tree changes were present. No production source was edited by this audit. No tests, builds, browsers, devices, AGY calls, Git delivery, or deployments were run.

**One bounded data/intake defect remains at this baseline:** a wrong-type legacy global display-mode preference can suppress an otherwise safe canonical render, including the cleared frame. The canonical publication state and account/day binding gates themselves are present. Cleared/blocked/absent copy and the inaccurate standard preview remain frontend work; they are not a missing native publication-state contract.

## D1 — Wrong-type global layout preference can prevent a cleared frame from replacing the old launcher image

Priority: **P2**, with a privacy consequence when the failed render follows account clearing. Owner: root-owned `DuoyiWidgetSnapshot.kt` intake.

Concrete input: a valid canonical document, including a cleared tombstone, plus backing preferences containing `widget_display_mode = 1` (or another non-String SharedPreferences value). A valid per-widget String does not avoid the failure.

Source chain:

1. `DuoyiWidgetSnapshot.kt:30–38` copies `widget_display_mode` and `widget_display_mode_<id>` from `backing.all` without validating their type or allowed value. All business fields still come exclusively from the canonical document.
2. `DuoyiWidgetFrameCore.kt:76–83` safely uses `as? String`, so the core can select a valid fallback mode even with the malformed global value.
3. `DuoyiWidgetRenderFrame.kt:41–44` keeps that malformed global value in the display map; it only replaces the per-widget mode with the effective String.
4. `DuoyiWidgetDisplayMode.kt:52–58` reads the global key with `prefs.getString(KEY, null)` before checking the per-widget mode. Providers use these helpers for their visibility decisions.
5. `DuoyiFrozenWidgetPreferences.kt:11–12` uses the normal strict SharedPreferences String cast. A non-String value throws `ClassCastException`. This behavior is deliberate and already asserted by `DuoyiFrozenWidgetPreferencesTest.kt:72`.
6. `DuoyiWidgetSnapshot.kt:92–95` catches the exception and returns `false` without `updateAppWidget`. Consequently, the new canonical cleared frame does not replace the previously committed launcher image.

Recommended bounded repair: admit only exact `compact`, `standard`, or `detailed` String values for the two device-owned layout keys at Snapshot intake; omit malformed values. Keep strict frozen getters and canonical account-data intake. Changing the backing preference file is unnecessary for safe rendering.

Root's proposed repair is a pure validated device-layout projection in the existing FrameCore companion, used by Snapshot intake. That placement satisfies the data-boundary ownership and permits a regression through the real document/core/render/frozen/DisplayMode chain without changing the frontend renderer.

The pre-capture `DuoyiWidgetDisplayMode.saveForWidgetIfMissing(backing, id, initialStyle)` call is not a second wrong-type cast path: its implementation at `DuoyiWidgetDisplayMode.kt:40–45` checks the ID and `contains`, normalizes the supplied style String, and writes with `putString`; it never calls `getString`. A present but malformed instance key suppresses provider-default seeding. After omission by the proposed projection, the existing core semantics use a valid global mode, then standard. Recovering a provider's initial compact/detailed style from a rejected stored instance value is a separate layout-fallback decision; it is unnecessary to fix the render suppression and should not silently change valid stored mode precedence.

Acceptance criteria for the repair:

- A wrong-type global layout value never reaches provider String getters. Missing, unsupported, or wrong-type layout keys select the same safe defaults as an omitted key.
- A valid instance mode continues to take precedence over a valid global mode, with the existing launcher size downgrades preserved.
- Fresh, old-published, cleared, blocked, and absent canonical states can reach their normal safe display projection despite malformed layout preferences.
- A cleared or blocked projection contains no prior account business content or actionable entity IDs; it must be able to commit the replacement launcher image.
- The repair does not admit legacy business fields, nonce, locale, timer, or theme values from preferences.

This defect is established by the source path above; no new runtime reproduction was performed. The existing 41-test JVM run does not compile Snapshot, DisplayMode, or the providers and therefore does not cover this intake chain.

## Canonical state contract supported by current source

`DuoyiWidgetPublicationDocument.kt:37–43` now derives `widget_publication_state`, nonce, locale, day, and offset from the validated document. State is render-only provenance, outside the 89-value business/presentation manifest. `DuoyiWidgetFrameCore.kt:37–47` requires the exact `published` state, canonical day/Int offset, and nonblank nonce before trusting a session; freshness additionally requires the current local day and offset. It does not infer trust from a zero or nonzero item count.

| Source state | Session trusted / fresh | Daily business projection | Timer and action behavior |
| --- | --- | --- | --- |
| Fresh `published`, including genuinely empty data | Yes / yes | Published values retained, including localized empty-state copy and zero counters | Canonical timer fields retained; fresh entity and mutation links may be built |
| Old `published` with a valid session tuple | Yes / no | Text replaced, counters zeroed, entity and quick-check IDs removed | Absolute timer fields retained across the day boundary; entity/mutation links fall back to section navigation |
| Canonical `cleared` | No / no | Canonical business values must be empty; display uses stale placeholders | Timer keys removed; no fresh bound actions |
| Canonical `blocked` | No / no | Same empty-business requirement and masking | Timer keys removed; no fresh bound actions |
| No readable envelope: absent, busy, corrupt, unsupported, unavailable, or durability unknown | No / no | No preference business fallback; safe placeholders and system-language fallback | No account tuple or timer payload is borrowed from preferences |

`DuoyiWidgetPublicationDocument.kt:168–204` strictly validates the complete document and canonical tombstones. `DuoyiWidgetPublicationEnvelope.kt:153–168` prevents a sealed envelope from carrying published content and checks receipt/document ownership and revisions. `DuoyiWidgetPublicationTransition.kt:177–191,233–246` creates an empty tombstone with a new epoch on initialize/invalidate and rejects a future capture or a capture outside the current local day/offset. A guest workspace uses the same publication/tombstone mechanics (`lib/main.dart:2373–2386`). **Cleared state is not evidence that the user should sign in.**

## Intake, frozen reads, and commit boundary

Except for D1's unchecked layout values, Snapshot intake is appropriately narrow: only `document.toFlatValues()` supplies account data, locale, timer, and theme; exactly the global and instance display-mode keys can come from backing preferences (`DuoyiWidgetSnapshot.kt:30–38`). Absent or unreadable canonical data never merges a legacy account mirror.

The frozen implementation defensively copies values, provides strict typed reads, rejects editing/listener registration, and prevents mutable String-set exposure (`DuoyiFrozenWidgetPreferences.kt:5–30`; `DuoyiWidgetFrameCore.kt:86–95`). The document normalizes Int counters/offset and Long timer millis, including zero, before they reach those strict getters.

Snapshot compares raw values and options with a fresh clock before committing, retries at most twice, and holds the canonical read lock during an envelope's final `updateAppWidget` call (`DuoyiWidgetSnapshot.kt:57–89`; `DuoyiWidgetPublicationStore.kt:44–51`). The core also rejects changed data, options, zone/day/offset, locale, wall/elapsed disagreement, and countdown expiry during the build (`DuoyiWidgetFrameCore.kt:52–73`). Source supports these boundaries; the JVM evidence does not establish Android SQLite/file-lock/Binder behavior or launcher replacement timing.

## Native action and timer trust boundaries

`DuoyiWidgetSnapshot.actionUri` requires `frame.fresh` and replaces all incoming binding fields with the captured canonical day, offset, epoch, and widget origin (`DuoyiWidgetSnapshot.kt:99–112`). Entity links use the same binding when fresh and fall back when stale (`115–121`). Native Todo completion, Habit check-in, and Focus start build those bound links only when fresh (`DuoyiTodoWidgetProvider.kt:214–250`; `DuoyiHabitWidgetProvider.kt:130–138`; `DuoyiFocusHabitWidgetProvider.kt:262–266`).

Transport adds widget origin and a delivery ID while retaining the original binding, including its absence on legacy links; it does not stamp an old link with a new account identity (`DuoyiWidgetLaunchBridge.kt:26–36`). Dart checks the current active, published canonical snapshot and matches current day, offset, and owner epoch (`lib/main.dart:689–707`). Dispatch hydrates providers and checks account generation before and after validation, then removes the origin marker only after successful validation (`widget_link_dispatch.dart:42–65`; `lib/main.dart:4409–4444`). Refresh and an empty quick-entry draft are intentionally recoverable without the publication binding (`widget_link_dispatch.dart:26–39`).

An old published day's timer remains trusted deliberately, while its daily metrics and action IDs are masked (`DuoyiWidgetRenderFrame.kt:45–60`). Cleared/blocked/no-session data removes every `focus_timer_` key. Focus uses only frozen timer values, allows native alarm scheduling only after an accepted trusted frame, and its alarm receiver only requests a new canonical render (`DuoyiFocusHabitWidgetProvider.kt:103–120,186–200,18–22`). This source review accepts the account/publication provenance gate. It does not certify the consistency of every possible timer field combination, exact-alarm delivery, or real Chronometer behavior.

## Updates to the earlier UX decision record

`widget-final-ux-contract-20261011.md` remains a useful product decision record, but these source facts supersede its earlier claims:

| Earlier claim | Current source and remaining work |
| --- | --- |
| Native flat publication values omit canonical state | Resolved in source: Document projects `widget_publication_state` at `37–43`, and FrameCore consumes it at `37–47` |
| Freshness relies only on day, offset, and nonce | Incomplete for current Android: exact `published` state is an additional mandatory gate |
| Clearing is described through HomeWidget legacy flat defaults | Current Android authority is the native canonical store and new-epoch tombstone. HomeWidget flat clearing remains relevant to the separate iOS path |
| Cleared/absent widgets need neutral guidance distinct from old published data | Still pending presentation work: RenderFrame branches only on `fresh` and `sessionTrusted`; Copy uses generic pending-refresh text (`DuoyiWidgetRenderFrame.kt:45–60`; `DuoyiWidgetCopy.kt:38–83`). The state data needed for the distinction is already available |
| Android standard preview shows a footer absent at nominal 3×2 height | Still present: native standard is 180×110dp; Snapshot hides navigation through 149dp; Flutter standard preview uses 1.5 ratio and footer for every noncompact mode; launcher standard preview includes a fixed 26dp footer |
| Calendar grid taps open Calendar, without date selection | Still correct. No new date-specific action contract was found; this remains an optional feature |

The copy acceptance criteria remain: cleared, blocked, and absent states use neutral “Open Duoyi to update this widget / 打开多仪以更新小组件”; an old published snapshot can retain pending-refresh wording; a fresh empty publication keeps its normal empty-state copy. No sign-in prompt may be inferred from cleared state or an empty count. The renderer/copy/providers and Flutter preview edits remain AGY-owned under the assigned scope.

The Dart `WidgetPublication.toFlatValues()` helper at `widget_publication.dart:251–260` does not include the new render-only state field. Source search found no active caller of that helper. Android uses the Kotlin projection directly, so this is a contract/documentation synchronization limit rather than a demonstrated current Android failure. If that helper becomes a native frame input, it must carry the exact state rather than rely on a default `published` value.

## Accepted evidence and remaining acceptance limits

The existing `widget-frozen-state-jvm-acceptance-20261011.md` records **41 passing JVM tests** across Document, FrameCore, and FrozenPreferences. Those 41 include the earlier 31; they are not 72 independent tests. This audit reuses that evidence and adds no tests or run result. It covers the named pure document/frame/projection implementation and typed read-only preference behavior. It does not cover D1's Snapshot/provider chain, native publication store/transition runtime, action transport runtime, or UI.

No Android launcher, emulator/device, browser, or Xcode evidence was produced in this pass. The following cannot be accepted from this audit: actual ten-kind layout legibility, iOS-style visual fidelity, OEM size constraints, pinning, touch delivery, rapid action behavior, Binder replacement, alarm/Chronometer transitions, account clearing on a real launcher, or end-to-end zh/en rendering.

iOS is a separate legacy flat App Group reader (`ios/DuoyiWidgets/DuoyiWidgets.swift:255–269,1350–1375`), with frozen timeline metadata and day/offset/nonce action binding (`337–370`). It does not consume the Android canonical store/state gate. The 41-test Android JVM evidence must not be presented as iOS or cross-platform acceptance.

After D1 is repaired, no additional definite data-contract defect was established by this bounded review. The remaining explicit product issues are the neutral unpublished-state copy and nominal standard preview accuracy, followed by real launcher/iOS acceptance when the required platforms are available.

## Final source review of root's D1 repair

The root-owned working-tree repair was reviewed against HEAD `8f96067`. **Source acceptance: D1 is addressed; no additional blocking data-boundary defect was found in this diff.** This review edited only this report and did not execute any test/build command.

- `DuoyiWidgetFrameCore.kt:87–97` adds `deviceDisplayValues`, which reads only the global key and the current positive widget ID's key. It admits only exact supported String modes via the existing `normalizeMode`, copies selected values into a new map, and returns an unmodifiable view. Unknown Strings, non-String values, other widget IDs, and all publication/business keys are excluded.
- `DuoyiWidgetSnapshot.kt:30–35` now adds that validated projection to the canonical document's flat values. The former unchecked preference-copy loop is removed. As a result, the global String getter cannot encounter the wrong-type value established in D1.
- The existing effective-mode logic at `DuoyiWidgetFrameCore.kt:76–83` preserves valid instance precedence, valid global fallback, standard default, and launcher size downgrades. A valid preference change remains part of the raw captured data and can produce `data_changed` during the commit check. Changes among rejected preference values cannot affect rendered content and do not require rejection.
- Pre-capture `saveForWidgetIfMissing` still uses only `contains`, normalization of the supplied String, and `putString`; it introduces no wrong-type typed read. An already present malformed instance value falls through to the global/standard semantics described above after intake validation.
- `DuoyiWidgetDeviceDisplayValuesTest.kt` contains six bounded cases. It reproduces the raw malformed-global exception with the real FrozenPreferences/DisplayMode implementation, checks the exact whitelist, rejects legacy publication/business and other widget values, checks instance/global/default precedence, exercises published/cleared/blocked documents through the real document → validated projection → frame core → render projection → frozen preference → DisplayMode chain, and checks an absent publication plus valid mode-change rejection. The state fixture is a parser-valid document fixture, not a native store/transition or Android launcher acceptance claim.
- `test/services/android_widget_frame_static_test.dart:54–59` now asserts Snapshot's validated helper wiring and removal of the unsafe copy expression. This was reviewed as a static source assertion; it was not run by this audit.

**At the initial source decision, JVM execution was pending.** Root reported compilation/run in progress through `.dart_tool/task-temp-20261011/run_widget_device_mode_intake_jvm.py`; no successful run result was claimed at that point. The collected result below supersedes that pending status. The earlier 41-test report must not be added to the overlapping rerun's total.

The frontend copy/preview ownership and Android/iOS platform acceptance limits above remain unchanged by this data-boundary repair.

## Collected runtime evidence after the source decision

Root subsequently supplied the completed runner result. Read-only inspection of `widget-device-mode-intake-jvm-acceptance-logs/runner-summary.json` and `02-junit.log` confirms Kotlin compile exit **0**, JUnit exit **0**, and **OK (47 tests)**. The actual `DuoyiWidgetDisplayMode.kt` implementation is included in the compile/runtime input; all 11 compiled production/test source hashes are unchanged. The total is the prior 41 plus six device-mode cases, not 88 independent tests.

Snapshot, platform adapters, and providers are not compiled by this pure JVM runner. This result accepts the tested real document/core/display/frozen/DisplayMode chain; actual Snapshot/platform behavior remains supported by source review and the separately recorded wiring checks. The later main-tree integration report records six passing `android_widget_frame_static_test.dart` checks, including the updated Snapshot helper assertion, plus a clean scoped analysis of that test. No launcher, device, Binder, SQLite, or iOS runtime acceptance is implied. Root owns the separate final intake acceptance report.
