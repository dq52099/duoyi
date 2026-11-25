# Duoyi iOS Widgets

This folder contains the WidgetKit source for the 10 visible Duoyi widgets:

- DuoyiTodoWidget
- DuoyiFocusWidget
- DuoyiHabitWidget
- DuoyiCalendarWidget
- DuoyiScheduleWidget
- DuoyiGoalWidget
- DuoyiCourseWidget
- DuoyiNoteWidget
- DuoyiAnniversaryWidget
- DuoyiDiaryWidget

The widgets read validated canonical publications through
`DuoyiWidgetPublicationStore` in the App Group `group.com.duoyi.duoyi`.
The store lives under `Library/Application Support/WidgetPublicationStore/`
and uses `duoyi_widget_store_v1.sqlite` with the fixed
`duoyi_widget_store_v1.lock`. The Flutter iOS Runner target and this Widget
Extension target must both enable the same App Group entitlement in Xcode.

`DuoyiWidgetPublicationCapture` projects one validated document for each
timeline capture. Account data, theme, language and `focus_timer_*` values
come from that document. The only preference override is the device display
mode `widget_display_mode`, limited to `compact`, `standard` or `detailed`.
`DuoyiFocusWidget` uses the captured timer values to render the active focus
countdown with WidgetKit timer text when a session is running.

There is intentionally no overview/combo widget kind.
