package com.duoyi.duoyi

import android.content.Context
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.RemoteViews
import android.widget.TextView
import java.time.Instant
import java.time.ZoneId
import kotlin.math.ceil
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Preparation261. Only the five @Test methods are local JUnit cases.
 * Their dp inputs are supplied geometry, never claimed Android measurements.
 * AndroidCases below are callable assertions for a future instrumented adapter:
 * Context/resources, real SP conversion, Snapshot finishing and RemoteViews.apply.
 * They are intentionally not registered as host-JVM tests or silently ignored.
 * No production planner, font scaler, glyph fixture or missing API is invented.
 */
class DuoyiWidgetPriorityRemainingTest {
    @Test
    fun suppliedTwoRowHeaderAndUnequalRowsReserveCompleteBlocksBeforeFooter() {
        val expectations = listOf(
            Triple(282, listOf(false, false, false), 186),
            Triple(283, listOf(true, false, false), 283),
            Triple(451, listOf(true, true, false), 345),
            Triple(452, listOf(true, true, true), 452),
            Triple(538, listOf(true, true, true), 452),
            Triple(539, listOf(true, true, true), 539),
            Triple(608, listOf(true, true, true), 539),
            Triple(609, listOf(true, true, true), 609),
        )
        for ((height, rows, used) in expectations) {
            val plan = DuoyiWidgetLayoutPolicy.todo(
                "detailed", 400, height, listOf(true, true), 56, 48, 44,
                headerHeight = 168, rowHeights = listOf(91, 59, 104),
                summaryHeight = 83, navigationHeight = 64,
                navigationFitsWidth = true,
            )
            assertEquals("original slots at $height", rows, plan.rows)
            assertEquals(height >= 539, plan.showSummary)
            assertEquals(height == 609, plan.showNavigation)
            assertEquals("complete blocks at $height", used, plan.usedHeight)
            assertTrue(plan.usedHeight <= height)
        }
    }

    @Test
    fun suppliedNaturalHabitHeaderHintAndDetailsPrecedeCompleteFooter() {
        val expectations = listOf(
            263 to 263, 358 to 263, 359 to 359, 445 to 359,
            446 to 446, 516 to 446, 517 to 517, 597 to 517, 598 to 598,
        )
        for ((height, used) in expectations) {
            val plan = DuoyiWidgetLayoutPolicy.habit(
                "detailed", 400, height, true, true, 56, 48, 44,
                headerHeight = 112, hintHeight = 117, summaryHeight = 96,
                streakHeight = 81, subtitleHeight = 69,
                navigationHeight = 73, navigationFitsWidth = true,
            )
            assertTrue(plan.showHint)
            assertEquals(height >= 359, plan.showSummary)
            assertEquals(height >= 446, plan.showStreak)
            assertEquals(height >= 517, plan.showSubtitle)
            assertEquals(height == 598, plan.showNavigation)
            assertEquals(used, plan.usedHeight)
            assertTrue(plan.usedHeight <= height)
        }
    }

    @Test
    fun footerWidthRejectionPreservesCompleteMeasuredOriginalContent() {
        val admitted = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 400, 800, listOf(false, true), 56, 48, 44,
            headerHeight = 168, rowHeights = listOf(91, 500, 104),
            summaryHeight = 83, navigationHeight = 64,
            navigationFitsWidth = true,
        )
        val rejected = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 400, 800, listOf(false, true), 56, 48, 44,
            headerHeight = 168, rowHeights = listOf(91, 500, 104),
            summaryHeight = 83, navigationHeight = 64,
            navigationFitsWidth = false,
        )
        assertEquals(listOf(true, false, true), admitted.rows)
        assertEquals(admitted.rows, rejected.rows)
        assertTrue(admitted.showSummary)
        assertEquals(admitted.showSummary, rejected.showSummary)
        assertTrue(admitted.showNavigation)
        assertFalse(rejected.showNavigation)
        assertEquals(477, rejected.usedHeight)
        assertEquals(547, admitted.usedHeight)
    }

    @Test
    fun unfittedRequiredTodoHeaderRejectsFooterWithAmpleHeightAndPreservesRowsAndSummary() {
        for (mode in listOf("standard", "detailed", "future-mode")) {
            val defaults = DuoyiWidgetLayoutPolicy.todo(
                mode, 400, 1000, listOf(true, true), 56, 48, 44,
                headerHeight = 168, rowHeights = listOf(91, 59, 104),
                summaryHeight = 83, navigationHeight = 64, navigationFitsWidth = true,
            )
            val explicitTrue = DuoyiWidgetLayoutPolicy.todo(
                mode, 400, 1000, listOf(true, true), 56, 48, 44,
                headerHeight = 168, rowHeights = listOf(91, 59, 104),
                summaryHeight = 83, navigationHeight = 64, navigationFitsWidth = true,
                requiredHeaderFits = true,
            )
            val rejected = DuoyiWidgetLayoutPolicy.todo(
                mode, 400, 1000, listOf(true, true), 56, 48, 44,
                headerHeight = 168, rowHeights = listOf(91, 59, 104),
                summaryHeight = 83, navigationHeight = 64, navigationFitsWidth = true,
                requiredHeaderFits = false,
            )
            assertEquals("default true retains previous content admission", defaults, explicitTrue)
            assertTrue(defaults.showNavigation)
            assertFalse("ample height cannot rescue an incomplete required header", rejected.showNavigation)
            assertEquals(defaults.rows, rejected.rows)
            assertEquals(mode == "detailed", rejected.showSummary)
            assertEquals(defaults.showSummary, rejected.showSummary)
            assertEquals(defaults.usedHeight - 70, rejected.usedHeight)
        }
        val prefix = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 400, 282, listOf(true, true), 56, 48, 44,
            headerHeight = 168, rowHeights = listOf(91, 59, 104),
            summaryHeight = 83, requiredHeaderFits = true,
        )
        assertEquals(listOf(false, false, false), prefix.rows)
        assertFalse(prefix.showSummary)
        assertFalse(prefix.showNavigation)
    }

    @Test
    fun unfittedRequiredHabitHeaderRejectsFooterWithoutRemovingPrimaryOrDetails() {
        val defaults = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 400, 1000, true, true, 56, 48, 44,
            headerHeight = 112, hintHeight = 117, summaryHeight = 96,
            streakHeight = 81, subtitleHeight = 69,
            navigationHeight = 73, navigationFitsWidth = true,
        )
        val explicitTrue = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 400, 1000, true, true, 56, 48, 44,
            headerHeight = 112, hintHeight = 117, summaryHeight = 96,
            streakHeight = 81, subtitleHeight = 69,
            navigationHeight = 73, navigationFitsWidth = true, requiredHeaderFits = true,
        )
        val rejected = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 400, 1000, true, true, 56, 48, 44,
            headerHeight = 112, hintHeight = 117, summaryHeight = 96,
            streakHeight = 81, subtitleHeight = 69,
            navigationHeight = 73, navigationFitsWidth = true, requiredHeaderFits = false,
        )
        assertEquals(defaults, explicitTrue)
        assertTrue(defaults.showNavigation)
        assertFalse(rejected.showNavigation)
        assertTrue(rejected.showHint)
        assertTrue(rejected.showSummary)
        assertTrue(rejected.showStreak)
        assertTrue(rejected.showSubtitle)
        assertEquals(517, rejected.usedHeight)
        assertEquals(598, defaults.usedHeight)
    }

    /**
     * Main must call each public method on Android's main thread with the target
     * application's Context. These are six named prepared Android cases, not
     * six discovered/accepted local JUnit tests. Reflection calls the existing
     * private finishRender entry because no public isolated fitter exists.
     */
    class AndroidCases {
        fun todoFullCountAndActionOccupyRealSeparateRowsWhenOneRowCannotFit(base: Context) {
            for (locale in listOf("zh", "en")) {
                val context = configured(base, locale, 2f)
                val count = Int.MAX_VALUE.toString()
                val add = DuoyiWidgetCopy.todoQuickAdd(locale == "zh")
                val metrics = DuoyiWidgetTextMetrics(context.resources.displayMetrics)
                val countWidth = metrics.width(count, 14f)
                val addWidth = maxOf(44, metrics.width(add, 11f) + 16)
                val refreshWidth = maxOf(36, metrics.width("↻", 14f))
                val width = maxOf(180, maxOf(countWidth + refreshWidth + 4, addWidth) + 16)
                assertTrue("fixture must require actual reflow, not an arbitrary font multiplier",
                    countWidth + 6 + addWidth + 4 + refreshWidth > width - 16)
                val drawn = draw(context, true, width, 1600, locale,
                    mapOf("todo_top3_count" to Int.MAX_VALUE))
                assertEquals("the real selector must choose the two-row resource",
                    R.layout.duoyi_todo_widget_reflow, drawn.layoutId)
                val countView = drawn.text(R.id.widget_todo_count)
                val addView = drawn.text(R.id.widget_todo_quick_add)
                assertComplete(drawn, countView, count)
                assertComplete(drawn, addView, add)
                val firstRowBottom = maxOf(drawn.bounds(countView).bottom,
                    if (visible(drawn.view(R.id.widget_refresh))) {
                        drawn.bounds(drawn.view(R.id.widget_refresh)).bottom
                    } else 0)
                assertTrue("reserving two-row height must actually relocate the full action",
                    drawn.bounds(addView).top >= firstRowBottom + dp(context, 4))
                val inlineWidth = countWidth + 6 + addWidth + 4 + refreshWidth + 216
                val inline = draw(context, true, inlineWidth, 1600, locale,
                    mapOf("todo_top3_count" to Int.MAX_VALUE))
                assertEquals("the real selector must retain the fitting inline resource",
                    R.layout.duoyi_todo_widget, inline.layoutId)
                assertComplete(inline, inline.text(R.id.widget_todo_count), count)
                assertComplete(inline, inline.text(R.id.widget_todo_quick_add), add)
                assertTrue("the fitting normal resource keeps the action beside the count",
                    inline.bounds(inline.text(R.id.widget_todo_quick_add)).top <
                        inline.bounds(inline.text(R.id.widget_todo_count)).bottom)
            }
        }

        fun habit139And140ApplyHeaderVisibilityWithoutLeavingUnbudgetedSpace(base: Context) {
            val context = configured(base, "en", 2f)
            val metrics = DuoyiWidgetTextMetrics(context.resources.displayMetrics)
            for (width in listOf(139, 140)) {
                val drawn = draw(context, false, width, 1000, "en")
                val title = drawn.text(R.id.widget_habit_title)
                val percent = drawn.text(R.id.widget_habit_percent)
                val header = drawn.view(R.id.widget_habit_header)
                val refresh = drawn.text(R.id.widget_refresh)
                val hint = drawn.text(R.id.widget_habit_hint)
                val recovery = drawn.text(R.id.widget_habit_recovery)
                val contentWidth = width - 16
                val showRefresh = width == 140
                val refreshMeasurement = if (showRefresh) metrics.measureSingleLine(
                    "↻", 14f, contentWidth, minWidthDp = 36, minHeightDp = 36
                ) else null
                val refreshWidth = if (showRefresh) 4 + refreshMeasurement!!.width else 0
                val percentMeasurement = metrics.measureSingleLine("100%", 14f, contentWidth - refreshWidth)
                val hintMeasurement = metrics.measureWrappedAction(
                    "Check in: Read", 11f, contentWidth,
                    minWidthDp = 0, minHeightDp = 36,
                    horizontalPaddingDp = 0, verticalPaddingDp = 0,
                )
                val requiredWidth = percentMeasurement.width + refreshWidth
                val requiredHeight = maxOf(36, percentMeasurement.height, refreshMeasurement?.height ?: 0)
                val requiredFits = percentMeasurement.fits && hintMeasurement.fits &&
                    (refreshMeasurement?.fits ?: true) && requiredWidth <= contentWidth &&
                    16 + requiredHeight + 10 + hintMeasurement.height + 6 + 2 <= 1000
                if (width == 139) {
                    assertFalse("139dp omits only the optional title", visible(title))
                    assertFalse("139dp omits the narrow-layout refresh", visible(refresh))
                }
                if (requiredFits) {
                    assertTrue("complete required content must not be replaced by recovery", visible(header))
                    assertComplete(drawn, percent, "100%")
                    assertComplete(drawn, hint, "Check in: Read")
                    assertEquals(showRefresh, visible(refresh))
                    if (showRefresh) assertComplete(drawn, refresh, "↻")
                    if (visible(title)) assertComplete(drawn, title, "Duoyi")
                    assertFalse("normal required-first content has no recovery block", visible(recovery))
                    assertEquals(null, drawn.view(R.id.widget_habit_root).contentDescription)

                    val actualHeaderHeight = listOf(title, percent, refresh)
                        .filter(::visible).maxOf { it.measuredHeight }
                    assertEquals("optional title cannot reserve an extra invisible line",
                        actualHeaderHeight, header.height)
                    assertEquals(drawn.content.paddingTop, drawn.bounds(header).top)
                    assertTrue("required hint keeps its real body container visible",
                        visible(drawn.view(R.id.widget_habit_body)))
                    val subtitle = drawn.text(R.id.widget_habit_subtitle)
                    var afterHeader = drawn.bounds(header).bottom
                    if (visible(subtitle)) {
                        assertComplete(drawn, subtitle, DuoyiWidgetCopy.habitSubtitle(false))
                        assertEquals("subtitle follows the effective header with its XML margin",
                            afterHeader + dp(context, 2), drawn.bounds(subtitle).top)
                        afterHeader = drawn.bounds(subtitle).bottom
                    }
                    assertEquals("body follows the actual header/subtitle, with no title-line reserve",
                        afterHeader + dp(context, 10), drawn.bounds(drawn.view(R.id.widget_habit_body)).top)
                    for ((id, expected) in listOf(
                        R.id.widget_habit_summary to DuoyiWidgetCopy.habitSummary("Habit summary", false),
                        R.id.widget_habit_streak to DuoyiWidgetCopy.streakSummary("Streak", false))) {
                        val text = drawn.text(id)
                        if (visible(text)) assertComplete(drawn, text, expected)
                    }
                } else {
                    for (id in listOf(R.id.widget_habit_header, R.id.widget_habit_title,
                        R.id.widget_habit_percent, R.id.widget_refresh, R.id.widget_habit_subtitle,
                        R.id.widget_habit_body, R.id.widget_habit_summary, R.id.widget_habit_streak,
                        R.id.widget_habit_hint, R.id.widget_habit_spacer, R.id.widget_habit_bottom_nav)) {
                        assertFalse("incomplete required content cannot leave a partial block id=$id",
                            visible(drawn.view(id)))
                    }
                    val recoveryText = DuoyiWidgetCopy.habitRecoveryText(false)
                    val measuredRecovery = metrics.measureWrapped(recoveryText, 12f, contentWidth)
                    val recoveryFits = measuredRecovery.fits && 16 + measuredRecovery.height <= 1000
                    assertEquals("recovery follows its own complete width/height admission",
                        recoveryFits, visible(recovery))
                    val description = DuoyiWidgetCopy.habitNoFitContentDescription(
                        true, false, recoveryVisible = recoveryFits)
                    assertEquals(description, drawn.view(R.id.widget_habit_root).contentDescription?.toString())
                    if (recoveryFits) {
                        assertComplete(drawn, recovery, recoveryText)
                        assertEquals(description, recovery.contentDescription?.toString())
                        assertEquals("recovery begins at content padding without hidden body reserve",
                            drawn.content.paddingTop, drawn.bounds(recovery).top)
                    }
                }
            }
        }

        fun scaledHabitPercentUsesItsActualFullWidthAndStaleStatus(base: Context) {
            val context = configured(base, "en", 2f)
            val metrics = DuoyiWidgetTextMetrics(context.resources.displayMetrics)
            assertTrue("real Android fixture must exceed the obsolete 48dp child cap",
                metrics.width("100%", 14f) > 48)
            val fresh = draw(context, false, 1000, 1200, "en")
            assertComplete(fresh, fresh.text(R.id.widget_habit_percent), "100%")
            val stale = draw(context, false, 1000, 1200, "en", fresh = false)
            assertComplete(stale, stale.text(R.id.widget_habit_percent), "—")
        }

        fun refreshFramesContainTheActualHorizontalGlyphInBothLayouts(base: Context) {
            val context = configured(base, "en", 2f)
            for ((todo, layout) in listOf(
                true to R.layout.duoyi_todo_widget,
                true to R.layout.duoyi_todo_widget_reflow,
                false to R.layout.duoyi_habit_widget,
            )) {
                val drawn = draw(context, todo, 1000, 1200, "en", layoutOverride = layout)
                assertEquals(layout, drawn.layoutId)
                val refresh = drawn.text(R.id.widget_refresh)
                assertComplete(drawn, refresh, "↻")
                val density = context.resources.displayMetrics.density
                val expectedGlyphDp = ceil(refresh.paint.measureText("↻") / density).toInt()
                assertEquals("shared production width matches the rendered14sp paint",
                    expectedGlyphDp,
                    DuoyiWidgetTextMetrics(context.resources.displayMetrics).width("↻", 14f))
                assertTrue(refresh.measuredWidth >= maxOf(dp(context, 36),
                    ceil(refresh.paint.measureText("↻")).toInt() +
                        refresh.compoundPaddingLeft + refresh.compoundPaddingRight))
            }
        }

        fun incompleteRequiredTodoHeaderCannotAdmitAnOtherwiseFittingFooter(base: Context) {
            for (locale in listOf("zh", "en")) {
                val context = configured(base, locale, 2f)
                for (layout in listOf(null, R.layout.duoyi_todo_widget,
                    R.layout.duoyi_todo_widget_reflow)) {
                    val drawn = draw(context, true, 180, 1600, locale,
                        mapOf("todo_top3_count" to Int.MAX_VALUE), layoutOverride = layout)
                    if (layout != null) assertEquals(layout, drawn.layoutId)
                    val required = listOf(R.id.widget_todo_count, R.id.widget_todo_quick_add)
                        .map(drawn::text)
                    val headerComplete = required.all { complete(drawn, it) }
                    if (!headerComplete) {
                        assertFalse("ample-height/short-label footer must wait for the real header",
                            visible(drawn.view(R.id.widget_todo_bottom_nav)))
                    } else {
                        // A real full reflow is an acceptable repair; do not force a
                        // formerly impossible header to remain impossible forever.
                        assertComplete(drawn, required[0], Int.MAX_VALUE.toString())
                        assertComplete(drawn, required[1], DuoyiWidgetCopy.todoQuickAdd(locale == "zh"))
                    }
                }
            }
        }

        fun eachMultilineCustomFooterLabelRejectsTheWholeBarWithoutEvictingContent(base: Context) {
            val context = configured(base, "en", 1f)
            for ((todo, layout) in listOf(
                true to R.layout.duoyi_todo_widget,
                true to R.layout.duoyi_todo_widget_reflow,
                false to R.layout.duoyi_habit_widget,
            )) {
                val baseline = draw(context, todo, 400, 1000, "en", layoutOverride = layout)
                assertEquals(layout, baseline.layoutId)
                val navId = if (todo) R.id.widget_todo_bottom_nav else R.id.widget_habit_bottom_nav
                assertTrue("single-line control fixture must actually admit navigation",
                    visible(baseline.view(navId)))
                val primaryIds = if (todo) {
                    listOf(R.id.widget_todo_item_1, R.id.widget_todo_quick_add,
                        R.id.widget_todo_today_summary)
                } else {
                    listOf(R.id.widget_habit_summary, R.id.widget_habit_hint,
                        R.id.widget_habit_streak, R.id.widget_habit_subtitle)
                }
                for (key in listOf("nav_todo", "nav_habit", "nav_calendar", "nav_focus")) {
                    val rejected = draw(context, todo, 400, 1000, "en", mapOf(key to "A\nB"),
                        layoutOverride = layout)
                    assertFalse("$key must not lose an authored second line", visible(rejected.view(navId)))
                    for (id in primaryIds) {
                        val before = baseline.text(id)
                        val after = rejected.text(id)
                        assertEquals(before.text.toString(), after.text.toString())
                        assertEquals(visible(before), visible(after))
                        if (visible(before)) {
                            assertComplete(rejected, after, before.text.toString())
                            assertEquals("rejected footer cannot alter admitted block allocation",
                                baseline.bounds(before), rejected.bounds(after))
                        }
                    }
                }
            }
        }

        private fun configured(base: Context, locale: String, scale: Float): Context {
            check(Looper.myLooper() == Looper.getMainLooper()) { "Android cases require the main thread" }
            val configuration = Configuration(base.resources.configuration)
            configuration.setLocale(java.util.Locale.forLanguageTag(locale))
            configuration.fontScale = scale
            return base.createConfigurationContext(configuration)
        }

        private fun draw(
            context: Context, todo: Boolean, width: Int, height: Int, locale: String,
            overrides: Map<String, Any?> = emptyMap(), fresh: Boolean = true,
            layoutOverride: Int? = null,
        ): Drawn {
            val clock = DuoyiWidgetFrameClock(Instant.parse("2026-11-10T12:00:00Z").toEpochMilli(),
                1000, ZoneId.of("UTC"))
            val values = linkedMapOf<String, Any?>(
                "widget_publication_state" to "published", "widget_account_nonce" to "fixture261",
                "widget_snapshot_day" to if (fresh) clock.day else "2026-11-09",
                "widget_snapshot_utc_offset_minutes" to 0,
                "widget_locale" to locale, "widget_display_mode_261" to "detailed",
                "brand_app_title" to if (locale == "zh") "多仪" else "Duoyi",
                "todo_top3_count" to 1, "todo_top3_1" to "Read", "todo_top3_1_id" to "literal261",
                "habit_active_count" to 1, "habit_percent" to 100,
                "habit_summary" to "Habit summary", "streak_summary" to "Streak",
                "habit_quick_check_id" to "habit261", "habit_quick_check_label" to "Check in: Read",
                "nav_todo" to "A", "nav_habit" to "B", "nav_calendar" to "C", "nav_focus" to "D",
            ).apply { putAll(overrides) }
            val frame = DuoyiWidgetRenderFrame(DuoyiWidgetFrameCore(values, clock,
                DuoyiWidgetFrameOptions(width, height, width, height), 261, locale))
            assertEquals(fresh, frame.fresh)
            val prefs = frame.prefs
            val zh = DuoyiWidgetCopy.isZh(prefs)
            val selectedLayout = if (todo) {
                if (DuoyiWidgetSnapshot.needsTodoReflow(context, frame)) {
                    R.layout.duoyi_todo_widget_reflow
                } else {
                    R.layout.duoyi_todo_widget
                }
            } else R.layout.duoyi_habit_widget
            require(layoutOverride == null || if (todo) {
                layoutOverride == R.layout.duoyi_todo_widget ||
                    layoutOverride == R.layout.duoyi_todo_widget_reflow
            } else layoutOverride == R.layout.duoyi_habit_widget)
            val layoutId = layoutOverride ?: selectedLayout
            val views = RemoteViews(context.packageName, layoutId)
            fun text(id: Int, value: String) { views.setTextViewText(id, value) }
            val tabs = listOf(DuoyiWidgetCopy.navTodo(prefs, zh), DuoyiWidgetCopy.navHabit(prefs, zh),
                DuoyiWidgetCopy.navCalendar(prefs, zh), DuoyiWidgetCopy.navFocus(prefs, zh))
            if (todo) {
                text(R.id.widget_todo_title, DuoyiWidgetCopy.appTitle(prefs, zh))
                text(R.id.widget_todo_count, if (frame.fresh) {
                    prefs.getInt("todo_top3_count", 0).toString()
                } else "—")
                text(R.id.widget_todo_unit, DuoyiWidgetCopy.todoCountUnit(prefs.getInt("todo_top3_count", 0), zh))
                text(R.id.widget_todo_quick_add, DuoyiWidgetCopy.todoQuickAdd(zh))
                listOf(R.id.widget_todo_item_1, R.id.widget_todo_item_2, R.id.widget_todo_item_3)
                    .forEachIndexed { slot, id -> text(id, DuoyiWidgetCopy.todoItemTitle(prefs, slot + 1, zh)) }
                text(R.id.widget_todo_today_summary,
                    DuoyiWidgetCopy.todoSummary(prefs.getInt("todo_top3_count", 0), zh))
                views.setViewVisibility(R.id.widget_todo_done_1, if (fresh) View.VISIBLE else View.GONE)
                listOf(R.id.widget_todo_nav_todo, R.id.widget_todo_nav_habit,
                    R.id.widget_todo_nav_calendar, R.id.widget_todo_nav_focus)
                    .forEachIndexed { slot, id -> text(id, tabs[slot]) }
            } else {
                text(R.id.widget_habit_title, DuoyiWidgetCopy.appTitle(prefs, zh))
                text(R.id.widget_habit_percent, "${prefs.getInt("habit_percent", 0)}%")
                text(R.id.widget_habit_subtitle, DuoyiWidgetCopy.habitSubtitle(zh))
                text(R.id.widget_habit_summary, DuoyiWidgetCopy.habitSummary(prefs.getString("habit_summary", null), zh))
                text(R.id.widget_habit_streak, DuoyiWidgetCopy.streakSummary(prefs.getString("streak_summary", null), zh))
                text(R.id.widget_habit_hint, DuoyiWidgetCopy.habitQuickCheckLabel(prefs.getString("habit_quick_check_label", null), zh))
                listOf(R.id.widget_habit_nav_todo, R.id.widget_habit_nav_habit,
                    R.id.widget_habit_nav_calendar, R.id.widget_habit_nav_focus)
                    .forEachIndexed { slot, id -> text(id, tabs[slot]) }
            }
            val finish = DuoyiWidgetSnapshot::class.java.getDeclaredMethod("finishRender",
                Context::class.java, RemoteViews::class.java, DuoyiWidgetRenderFrame::class.java)
            finish.isAccessible = true
            finish.invoke(DuoyiWidgetSnapshot, context, views, frame)
            val root = views.apply(context, FrameLayout(context)) as ViewGroup
            root.measure(View.MeasureSpec.makeMeasureSpec(dp(context, width), View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(dp(context, height), View.MeasureSpec.EXACTLY))
            root.layout(0, 0, root.measuredWidth, root.measuredHeight)
            val content = root.findViewById<ViewGroup>(
                if (todo) R.id.widget_todo_content else R.id.widget_habit_content)
            return Drawn(root, content, layoutId)
        }

        private data class Drawn(val root: ViewGroup, val content: ViewGroup, val layoutId: Int) {
            fun view(id: Int): View = requireNotNull(root.findViewById<View>(id))
            fun text(id: Int): TextView = view(id) as TextView
            fun bounds(view: View): Rect = Rect(0, 0, view.width, view.height).also {
                content.offsetDescendantRectToMyCoords(view, it)
            }
        }

        private fun visible(view: View): Boolean {
            var current: View? = view
            while (current != null) {
                if (current.visibility != View.VISIBLE) return false
                current = current.parent as? View
            }
            return true
        }

        private fun complete(drawn: Drawn, view: TextView): Boolean {
            if (!visible(view)) return false
            val layout = view.layout ?: return false
            if (layout.lineCount == 0 || layout.getLineEnd(layout.lineCount - 1) != view.text.length) return false
            if ((0 until layout.lineCount).any { layout.getEllipsisCount(it) != 0 }) return false
            if (layout.height > view.height - view.compoundPaddingTop - view.compoundPaddingBottom) return false
            if ((0 until layout.lineCount).any {
                    layout.getLineMax(it) > layout.width + 0.5f
                }) return false
            val rect = drawn.bounds(view)
            return rect.left >= drawn.content.paddingLeft &&
                rect.right <= drawn.content.width - drawn.content.paddingRight &&
                rect.top >= drawn.content.paddingTop &&
                rect.bottom <= drawn.content.height - drawn.content.paddingBottom
        }

        private fun assertComplete(drawn: Drawn, view: TextView, expected: String) {
            assertEquals("must draw the complete projected string", expected, view.text.toString())
            assertTrue("complete visible text/frame for id=${view.id}: $expected", complete(drawn, view))
        }

        private fun dp(context: Context, value: Int): Int =
            (value * context.resources.displayMetrics.density).roundToInt()
    }
}
