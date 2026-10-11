# Widget entity-link inventory — 2026-10-11

Scope: source inspection of Android and iOS widget entity targets, native launch transport, and Flutter deep-link dispatch in the current `/home/ubuntu/duoyi` tree.

## Entity links

| Widget/entity | Android renderer | iOS renderer | ID source and handling |
| --- | --- | --- | --- |
| Todo | `DuoyiTodoWidgetProvider.kt:206–250` | `DuoyiWidgets.swift:1188–1194, 1840–1877` | `todo_top3_<n>_id`; Android encodes the ID in `duoyi://todo/<id>` only for a fresh frame, otherwise opens the todo tab. iOS routes its detail URL through `snapshot.actionURL`, so current row links carry snapshot binding. |
| Note, goal, schedule, course, diary | `Duoyi{Note,Goal,Schedule,Course,Diary}WidgetProvider.kt:125–173` | `DuoyiWidgets.swift:1488–1510, 1555–1572, 1825–1830` | Flutter publishes the corresponding `*_highlight_*_id` as `duoyi://<kind>/<encoded-id>` (`lib/main.dart:2889–2945, 2997–3010`). Android `detailUri` passes `duoyi://` values through and wraps legacy plain IDs in the kind’s route. iOS row links pass the target through `snapshot.actionURL` and bind supported entity paths. |
| Anniversary / memorial | `DuoyiAnniversaryWidgetProvider.kt:76–84, 139–161`; target parser in `DuoyiWidgetContent.kt:142–193, 202–262` | `DuoyiWidgets.swift:522–645, 1406–1425` | Reads anniversary and memorial highlight IDs. Both native parsers accept a single `duoyi://anniversary/<id>` path segment or encode a legacy plain ID; invalid/foreign targets and empty IDs fall back to `duoyi://anniversary`. |
| Calendar event summary | `DuoyiCalendarWidgetProvider.kt:114–132`; target resolution in `DuoyiWidgetContent.kt:265–363` | `DuoyiWidgets.swift:1376–1392, 647–767, 1773–1782` | Summary text is paired with `schedule_highlight_1_id`. Dart derives that ID from the first event’s `sourceId` (`lib/main.dart:2947–2969, 3095–3110`). Native resolution allows a validated calendar/focus target or a supported single-segment entity target; empty, stale, placeholder, or invalid targets fall back to `duoyi://calendar`. |

## Binding and dispatch behavior

Current Android entity targets pass through `DuoyiWidgetSnapshot.entityUri`, which uses the captured fresh render frame to add `source=widget`, `widget_day`, `widget_offset`, and `widget_account`; stale or invalid targets become section fallbacks (`DuoyiWidgetSnapshot.kt:99–122`). This covers Todo, Goal, Note, Diary, Course, Schedule, Calendar summary, and Anniversary rows. On tap, `DuoyiWidgetLaunchBridge.capture` replaces the origin and adds a new `widget_delivery` transport ID while preserving those rendered binding values; it does not create missing snapshot bindings (`android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetLaunchBridge.kt:21–46`). Flutter treats a sourced entity URI with a nonempty path as binding-required. If the snapshot validator rejects a stale or legacy unbound entity target, dispatch returns the kind’s route without the ID and flags it stale (`lib/services/widget_link_dispatch.dart:21–65`).

iOS current entity links pass through `DuoyiWidgetSnapshot.actionURL`, which binds supported entity paths when the snapshot is fresh. This includes todo detail URLs (`ios/DuoyiWidgets/DuoyiWidgets.swift:1188–1194, 337–369, 1825–1830`). The iOS AppDelegate then buffers the link through the shared launch channel and adds `widget_delivery` while preserving the snapshot fields (`ios/Runner/AppDelegate.swift:22–45, 54–97`). Old cached links without `source=widget` retain ordinary deep-link behavior and are not snapshot-validated.

Flutter reads the first decoded path segment as the entity ID. Todo, habit, goal, course, anniversary, note, diary, countdown and time-entry routes pass it to their detail screen/router; a route without an ID opens the section or fallback screen (`lib/main.dart:4065–4145`). Calendar and focus routes open their sections.

## Snapshot-bound actions (comparison)

Android `DuoyiWidgetSnapshot.actionUri` requires a fresh render frame and adds `source=widget`, `widget_day`, `widget_offset`, and `widget_account` (`android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetSnapshot.kt:99–106`). It is used for todo completion (`DuoyiTodoWidgetProvider.kt:248`), habit check-in (`DuoyiHabitWidgetProvider.kt:130–135`), and focus start (`DuoyiFocusHabitWidgetProvider.kt:262–266`, `DuoyiWidgetProvider.kt:197–203`).

iOS `DuoyiWidgetSnapshot.actionURL` applies those four binding fields to supported entity paths and mutating action URLs; actions include `complete_todo`, `checkin_habit`, and `start_pomodoro`, plus `quick_todo` with nonblank text (`ios/DuoyiWidgets/DuoyiWidgets.swift:337–369`). Todo entity detail/completion, row entity links, habit quick check-in, and focus quick start call it (`ios/DuoyiWidgets/DuoyiWidgets.swift:1188–1205, 1825–1830, 2204–2213`).

Flutter validates sourced action/entity links against the current local day, UTC offset, and owner epoch (`lib/main.dart:686–705, 4400–4444`; `lib/services/home_widget_service.dart:214–236`). Only a validated link loses its `source` marker; `widget_delivery` remains for delivery acknowledgment/deduplication (`lib/services/widget_link_dispatch.dart:61–65`).

Unmarked ordinary links—including current iOS section/footer navigation, refresh and empty quick entry, old cached iOS entity links, and external/plain reminder links—retain existing routing behavior and the ordinary bridge's single early pending slot. The transport delivery ID identifies a tap and does not substitute for account/day binding or authenticate the sender.
