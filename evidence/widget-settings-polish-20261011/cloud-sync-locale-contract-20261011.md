# Cloud sync live-locale notice contract — 2026-10-11

Read-only source audit. No app code or tests were changed or run for this report.

## Finding

`CloudSyncProvider` stores presentation text in `_lastError`, `_syncRetryMessage`, and `_lastRealtimeWarning` (`lib/providers/cloud_sync_provider.dart:147-150`). A locale change updates `I18n.current` and `I18n.localeListenable` (`lib/core/i18n.dart:2376-2399`), but does not regenerate those stored strings. A sync event is therefore required before parts of the UI stop showing the previous language. The problem reaches the status card through `SyncStatusController.lastError`, the conflict log through all three getters, the Todo banner through `main.dart`'s one-way rendered-string mirror, and the widget quick-add notice through its frozen `syncReason`.

There is a second independent issue: `_userVisibleSyncError` passes the Chinese `_serviceUnavailableMessage` as `fallbackMessage` to `userVisibleApiError` (`cloud_sync_provider.dart:116,397-403`). That overrides the latter's own English fallback even if the error is rendered again under English locale. `userVisibleApiError` does correctly suppress unexpected exceptions and sensitive diagnostics and preserves allowed API details (`lib/services/api_client.dart:527-564`); keep that gate in use.

## State and rendering contract

Use one immutable notice value in a dedicated service or core file for app-owned sync status: a typed reason plus optional original error/detail. Store the **reason and safe input**, not the completed Chinese sentence. Render in a getter with `I18n.current` (or an explicit `AppLocale` argument), and localize the fallback at render time. An error may be retained as an `Object` only if every render passes it through `userVisibleApiError`; its raw `toString()` must never be interpolated into UI. App-authored reasons need explicit variants; arbitrary server-provided `ApiException` details must remain literal.

| Existing state | Capture as | Render at read time |
| --- | --- | --- |
| `_lastError` from upload/pull failure | error detail and failed-operation context | `lastError` as a safe localized error; retain the existing nullable/error semantics |
| account-change upload timeout / still pending | distinct app-owned reasons | localized `lastError`; retain the blocked account change and pending-data facts |
| `_syncRetryMessage` | baseline, event, remote-check, or remote-pull retry reason plus error detail | localized `syncRetryStatus`; preserve `hasSyncRetryPending` as the control flag |
| `_lastRealtimeWarning` | stream fallback reason plus error detail | localized `lastRealtimeWarning`; clear on stream recovery or `stopRemotePolling()` |
| `syncUnavailableStatus`, `queuedRemotePullStatus`, `localSaveSyncMessage()` | existing state booleans/enum | localize generated text directly from current locale; preserve current priority and nullability |

Rendering should preserve the current priority in `localSaveSyncMessage`: unavailable, automatic sync off, retry pending, failed pending upload, then background upload (`cloud_sync_provider.dart:214-240`). The Todo mirror currently prioritizes error, retry, unavailable with pending changes, auto-sync off with pending changes, then queued remote pull (`lib/main.dart:1456-1494`); keep this order and levels. The widget `WidgetActionSyncStatus.fromFacts` has a related order: disabled, account transition, signed out, server disabled, auto-sync off, retry pending, failed pending changes, background upload (`lib/services/widget_action_message.dart:55-86`). Do not turn a retry-only state into a local upload failure or clear pending changes when changing locale.

Capture the original exception before `_userVisibleSyncError` renders it. A rendered string cannot reliably be parsed back into an error category, and re-translating the entire string would alter server-authored detail. In particular, a `4xx` API detail currently passes through as supplied after the status prefix, while network timeout/connection and `5xx` failures use safe app-owned copy. Any new notice renderer should match that filtering behavior and provide a locale-specific fallback instead of the current fixed Chinese one.

## Notification and copy boundaries

Changing only `CloudSyncProvider` getters is insufficient. `main.dart:1454-1500` creates a `TodoCloudSyncNotice(message: ...)` and updates it only when the provider notifies. The Todo banner also adds a Chinese sentence around `notice.message` (`lib/screens/todo_screen.dart:1542-1572`). On locale change, notify the provider's listeners or explicitly remirror the current notice from `main.dart`, and render the banner's own app copy in the active locale. Make sure the status card and conflict log rebuild on locale change; `MineScreen` and `TodoScreen` already listen to the locale, while the conflict log needs its own rebuild path or a provider notification. Remove any new locale listener on disposal.

`main.dart:4749-4774` snapshots `syncRetryStatus`/`lastError` into `WidgetActionSyncStatus.reason`; `WidgetActionMessage.render()` then localizes the surrounding sentence but appends that reason literally (`lib/services/widget_action_message.dart:286-288`). Carry a typed reason to render time, or take the snapshot only after the final locale is known at dispatch. Preserve authored API details verbatim in either design. The `WidgetActionSyncState` snapshot should continue to reflect the action's original sync facts; changing locale must not reread a different account or turn an old action into a new one.

Avoid treating all Chinese-looking text as translatable. Server messages, task/user content, protocol values, and diagnostic identifiers are data. Translate only app-owned framing and safe fallback copy. `UserVisibleApiException.userVisibleMessage` can itself be computed from `I18n.current`; rendering it at read time supports its existing contract.

## Account and lifetime constraints

`suspendForAccountChange()` increments `_accountGeneration` and stops remote polling; `resetForAccountChange()` clears `_lastError`, retry state, remote queue, pending state, and cached account metadata (`cloud_sync_provider.dart:880-941`). Keep typed notice cleanup aligned with those paths. Stream callbacks and sync/poll catches guard account generation before setting visible state (`cloud_sync_provider.dart:715-728,982-1005,1641-1662,1776-1790`); a delayed old-account error must never populate the new account's notice. `stopRemotePolling()` clears realtime warnings. Clearing a typed notice must preserve all corresponding null/boolean conditions so the rest of the sync control flow behaves as before.

## Acceptance cases for implementation review

1. After a failed local upload, switch Chinese → English → Chinese without another sync: `lastError`, `localSaveSyncMessage`, status card, conflict log, and Todo banner show current-language app copy; pending/retry state and error level do not change.
2. For baseline, remote event, remote check, and remote pull retry states, switch locale without another request: each app-owned prefix and fallback updates, `hasSyncRetryPending` remains true, and the widget quick-add message has one language for its generated copy.
3. A server-authored `4xx` detail stays byte-for-byte the same in both locales; unexpected exceptions, malformed responses, sensitive diagnostics, network failures, and `5xx` errors still use safe localized output. No raw exception or URL/token detail leaks through the new notice path.
4. Realtime stream failure shows localized polling-fallback wording and its safe detail; recovery or stopping polling clears the warning. A queued remote-pull status also follows the active locale without altering the queue.
5. Unavailable states (feature off, account transition, signed out, server backup off), auto-sync off, and ordinary background upload render in both locales with the current priority; no failure is invented for these states.
6. During account switch, a blocked upload retains its warning for the old account; successful reset removes all old-account notices. Late callbacks from that generation cannot restore them for the new account.

Existing provider and widget tests assert several Chinese strings and literal `syncReason` behavior (`test/services/cloud_sync_provider_test.dart`, `test/services/widget_action_message_test.dart`). The acceptance cases above describe needed coverage when implementation testing is authorized.

## Implementation review of the current working tree

The proposed provider/service diff now uses `lib/services/cloud_sync_notice.dart`. It stores a typed `CloudSyncNoticeKind` and original error, renders through the existing safe `userVisibleApiError` filter with an explicit locale, and leaves the provider's nullable error/retry flags and account-generation guards intact. `CloudSyncProvider` subscribes to `I18n.localeListenable` and removes its listener in `dispose()`. The widget path carries the typed notice with frozen sync state and renders it at dispatch time; the older literal `syncReason` path remains available. `userVisibleApiError` now accepts an optional locale, and the only current `UserVisibleApiException` implementation (`AdminResponseException`) supplies explicit-locale rendering. Source review found no confirmed defect in those owned changes; tests were not run in this audit.

The provider cannot localize a caller-supplied `localSavedText`. Current Chinese arguments still come from `lib/screens/todo_screen.dart:379-385,819-822`, `lib/screens/ai_schedule_screen.dart:208-210`, and `lib/widgets/quick_capture_fab.dart:430-439`. Those call sites and the Chinese Todo banner wrapper (`todo_screen.dart:1542-1572`) need page-owned localization before the complete save flow can pass the English acceptance case. The conflict log also has Chinese page-owned labels and status framing (`lib/screens/sync_conflict_log_screen.dart:270-423`). They are outside this provider/service diff and remain a review boundary.
