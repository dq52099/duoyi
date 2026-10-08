# Widget and Settings Locale Acceptance

Version candidate: **1.1.45+140011**. This batch advances the active widget, iOS-style, global-localization and settings goal. It does not close the full goal.

## Implemented

- All ten in-app widget previews and catalog entries have Chinese/English copy, preserve selected category/density during language changes, and use theme surface radii. Enlarged text gets more height; navigation labels wrap as whole items.
- Locale changes notify immediately and save in selection order. Rejected/failed saves are reported and subsequent saves can proceed. Widget refresh revisions include locale and UTC offset; obsolete async refreshes cannot become the successful current snapshot.
- Android live widgets use published app language for state, labels and dates, preserving nonempty themed navigation names. Chinese and English resource keys match.
- WidgetKit target versions inherit Flutter generated build settings for Debug/Release/Profile. The device evidence script regenerates that configuration before its signed Xcode build, avoiding stale version metadata. Xcode execution remains unverified on this host.
- iOS captures payload and account/day/offset metadata together. Todo completion, habit check-in and focus start URLs use the existing Flutter validator. Stale daily data and item IDs are hidden; an unpublished timer cannot revive old saved fields. Focus root taps open the focus page. Published timer trust remains separate from daily freshness.
- Preferences, navigation, app lock, backup/restore, theme rewards, integrations and notification history have bilingual UI. Narrow/enlarged layouts and theme price/status rows were adjusted.
- Text-input dialogs retain controllers through route exit. Import/WebDAV/ICS inputs survive language changes and cancel/reopen cleanly. Language-save Retry persists the selected language.

## Evidence and limits

See `verification.json` for current command results and artifact hashes. Screenshot sets under `evidence/screenshots/{widget-locale-20261006,settings-locale-20261006,data-settings-locale-20261007}` use synthetic data; widget and data screenshots were refreshed on 2026-10-08. They are Flutter-rendered evidence, not Android launcher or WidgetKit captures. English default-theme previews and settings contact sheets were personally reviewed at width 320 and text scale 1.6.

No attached Android/iOS device, macOS/Xcode build or production signing is available. New debug APKs remain private. Android Kotlin/resources compiled successfully in the debug candidate. iOS compilation, native widget runtime acceptance and real startup/frame timing remain open. Static Swift contract checks do not establish compilation or WidgetKit behavior.

## Remaining goal work

- iOS running count-up, paused/ended states, accessory clock values, bounded countdown expiry and explicit timeline transitions.
- Real iOS month grid; Android today highlighting and localized launcher preview assets. OS gallery language follows system resources rather than the saved app locale.
- Profile draft identity binding and state-preserving locale rebuilds, login/Me/avatar overlays, server-message localization, and the remaining Todo/Habit/Calendar/Focus dialogs and shared pickers.
- Full route localization, success/cancel/retry/account-switch acceptance, Android/iOS device regression and measured mobile fluency.

The full requirement matrix and device gates in `docs/goal-requirement-matrix.md` remain authoritative and open. Broader frontend implementation remains subject to the established AGY ownership; Gemini high quota recovery and Sonnet high invocation availability are tracked separately. The pending user clarification about broader direct takeover has not been treated as approval.
