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

The widgets read the same App Group data written by `HomeWidgetService`:
`group.com.duoyi.duoyi`. The Flutter iOS Runner target and this Widget
Extension target must both enable the same App Group entitlement in Xcode.
`DuoyiFocusWidget` also reads the shared `focus_timer_*` keys and renders the
active focus countdown with WidgetKit timer text when a session is running.

There is intentionally no overview/combo widget kind.
