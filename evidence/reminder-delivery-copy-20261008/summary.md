# Initial reminder delivery copy — 2026-10-08

## Implemented

- Todo, goal, habit, anniversary and countdown producers share immutable typed facts and explicit Chinese/English rendering. User titles remain literal, including whitespace, emoji and mixed languages. JSON semantic fingerprints remain stable across locale and brand rendering.
- Primary habit push retains its “Don't forget” variant; generic/multi-time push, popup and alarm retain their check-in variant. Brand titles use the injected strings. Anniversary channel prefixes and countdown signed distances remain distinct.
- Presentation-only Todo/Goal title changes compare a captured neutral intent signature and skip backend email cancellation. IDs, schedule, payload and alarm options remain unchanged. Actual body/time/channel changes retain ordinary cleanup. Goal/countdown email copy stays canonical Chinese pending a backend copy-update contract.

## Verification

- 688 regressions passed across 46 files and targeted analysis across 57 Dart paths reported no issues. All 67 frozen source/test hashes stayed unchanged; commands, logs and hashes are attached.
- Runtime matrices cover all Todo/Goal rule types, three local Goal channels, canonical multi-time popup habits, explicitly retained raw habit rules for generic popup/alarm/push routes, anniversary popup/alarm, countdown signed distances and mixed local/email Goal language changes. Control cases change time, user content and channel. Pure-copy tests cover every subject, raw user text, brand variants and fingerprint stability/collisions. Normal Habit construction/hydration intentionally normalizes its reminders to popup; raw-plan tests do not establish those other channels as user-selectable Habit features.
- A real NotificationService + LocalNotifications + iOS plugin Dart serialization fixture records the native MethodChannel boundary. Three brands × two locales cover daily/weekday semantic habit wrappers; anniversary reminders cover 0/1/3 days. It checks 24 serialized registrations from 18 semantic calls, preserved literal text, IDs/payloads/timezones/repeat fields, exact anniversary times and 18 matching history rows. The native boundary is mocked; this proves production Dart serialization and history, not native iOS delivery or Android-specific metadata. Existing scheduler fakes were not changed to manufacture localization evidence.
- The first run passed 539 cases but could not compile the integration fixture: tearDown referenced a local applyLocale function before its declaration. The second passed 685 cases and exposed the Habit fixture's unintended constructor normalization. Both sessions terminated before the fixture-only corrections; a focused 159-case run then passed before the final frozen checks. Production scheduling/model behavior was preserved.

## Remaining

Already-pending notifications, popup timers and native alarms still need owned local copy refresh, exact physical registration tracking, localized actions, account/latest-locale guards and restart/legacy bootstrap. Daily/holiday/report auxiliary reminders and Todo body decoration also remain open. No new build, deployment or APK is claimed. Full bilingual routes, default iOS visual acceptance and real Android/iOS widget/performance evidence remain required for the complete goal.
