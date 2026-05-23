import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

void main() {
  group('Android 小组件资源', () {
    final legacyWidget = _WidgetResource(
      title: '历史兼容主小组件',
      providerXml: 'duoyi_widget_info.xml',
      layoutXml: 'duoyi_widget.xml',
      previewPng: 'widget_preview.png',
      receiver: 'DuoyiWidgetProvider',
      previewDrawable: 'widget_preview',
      layoutName: 'duoyi_widget',
      ids: [
        '@+id/widget_bottom_nav',
        '@+id/widget_nav_todo',
        '@+id/widget_nav_habit',
        '@+id/widget_nav_calendar',
        '@+id/widget_nav_focus',
        '@+id/widget_goal_summary',
        '@+id/widget_anniversary_summary',
        '@+id/widget_course_summary',
      ],
      compact: true,
    );
    final widgets = <_WidgetResource>[
      _WidgetResource(
        title: '今日待办',
        providerXml: 'duoyi_todo_widget_info.xml',
        layoutXml: 'duoyi_todo_widget.xml',
        previewPng: 'widget_todo_preview.png',
        receiver: 'DuoyiTodoWidgetProvider',
        previewDrawable: 'widget_todo_preview',
        layoutName: 'duoyi_todo_widget',
        ids: [
          '@+id/widget_todo_bottom_nav',
          '@+id/widget_todo_nav_todo',
          '@+id/widget_todo_nav_habit',
          '@+id/widget_todo_nav_calendar',
          '@+id/widget_todo_nav_focus',
          '@+id/widget_todo_row_1',
          '@+id/widget_todo_row_2',
          '@+id/widget_todo_row_3',
          '@+id/widget_todo_today_summary',
          '@+id/widget_todo_quick_add',
        ],
        compact: true,
      ),
      _WidgetResource(
        title: '专注',
        providerXml: 'duoyi_focus_habit_widget_info.xml',
        layoutXml: 'duoyi_focus_habit_widget.xml',
        previewPng: 'widget_focus_habit_preview.png',
        receiver: 'DuoyiFocusHabitWidgetProvider',
        previewDrawable: 'widget_focus_habit_preview',
        layoutName: 'duoyi_focus_habit_widget',
        ids: [
          '@+id/widget_focus_habit_bottom_nav',
          '@+id/widget_focus_nav_todo',
          '@+id/widget_focus_nav_habit',
          '@+id/widget_focus_nav_calendar',
          '@+id/widget_focus_nav_focus',
          '@+id/widget_focus_quick_start',
          '@+id/widget_focus_habit_summary',
          '@+id/widget_focus_streak_summary',
          '@+id/widget_focus_timer_caption',
        ],
        compact: true,
      ),
      _WidgetResource(
        title: '习惯',
        providerXml: 'duoyi_habit_widget_info.xml',
        layoutXml: 'duoyi_habit_widget.xml',
        previewPng: 'widget_habit_preview.png',
        receiver: 'DuoyiHabitWidgetProvider',
        previewDrawable: 'widget_habit_preview',
        layoutName: 'duoyi_habit_widget',
        ids: [
          '@+id/widget_habit_bottom_nav',
          '@+id/widget_habit_nav_todo',
          '@+id/widget_habit_nav_habit',
          '@+id/widget_habit_nav_calendar',
          '@+id/widget_habit_nav_focus',
          '@+id/widget_habit_summary',
          '@+id/widget_habit_streak',
          '@+id/widget_habit_hint',
        ],
        compact: true,
      ),
      _WidgetResource(
        title: '月历',
        providerXml: 'duoyi_calendar_widget_info.xml',
        layoutXml: 'duoyi_calendar_widget.xml',
        previewPng: 'widget_calendar_preview.png',
        receiver: 'DuoyiCalendarWidgetProvider',
        previewDrawable: 'widget_calendar_preview',
        layoutName: 'duoyi_calendar_widget',
        ids: [
          '@+id/widget_calendar_bottom_nav',
          '@+id/widget_calendar_nav_todo',
          '@+id/widget_calendar_nav_habit',
          '@+id/widget_calendar_nav_calendar',
          '@+id/widget_calendar_nav_focus',
          '@+id/widget_calendar_grid',
          '@+id/widget_calendar_summary',
        ],
        compact: true,
      ),
      _WidgetResource(
        title: '今日日程',
        providerXml: 'duoyi_schedule_widget_info.xml',
        layoutXml: 'duoyi_schedule_widget.xml',
        previewPng: 'widget_schedule_preview.png',
        receiver: 'DuoyiScheduleWidgetProvider',
        previewDrawable: 'widget_schedule_preview',
        layoutName: 'duoyi_schedule_widget',
        ids: [
          '@+id/widget_schedule_bottom_nav',
          '@+id/widget_schedule_nav_todo',
          '@+id/widget_schedule_nav_habit',
          '@+id/widget_schedule_nav_calendar',
          '@+id/widget_schedule_nav_focus',
          '@+id/widget_schedule_1',
          '@+id/widget_schedule_2',
          '@+id/widget_schedule_3',
        ],
        compact: false,
      ),
      _WidgetResource(
        title: '目标',
        providerXml: 'duoyi_goal_widget_info.xml',
        layoutXml: 'duoyi_goal_widget.xml',
        previewPng: 'widget_goal_preview.png',
        receiver: 'DuoyiGoalWidgetProvider',
        previewDrawable: 'widget_goal_preview',
        layoutName: 'duoyi_goal_widget',
        ids: [
          '@+id/widget_goal_bottom_nav',
          '@+id/widget_goal_nav_todo',
          '@+id/widget_goal_nav_habit',
          '@+id/widget_goal_nav_calendar',
          '@+id/widget_goal_nav_focus',
          '@+id/widget_goal_1',
          '@+id/widget_goal_2',
          '@+id/widget_goal_3',
        ],
        compact: false,
      ),
      _WidgetResource(
        title: '课程表',
        providerXml: 'duoyi_course_widget_info.xml',
        layoutXml: 'duoyi_course_widget.xml',
        previewPng: 'widget_course_preview.png',
        receiver: 'DuoyiCourseWidgetProvider',
        previewDrawable: 'widget_course_preview',
        layoutName: 'duoyi_course_widget',
        ids: [
          '@+id/widget_course_bottom_nav',
          '@+id/widget_course_nav_todo',
          '@+id/widget_course_nav_habit',
          '@+id/widget_course_nav_calendar',
          '@+id/widget_course_nav_focus',
          '@+id/widget_course_1',
          '@+id/widget_course_2',
          '@+id/widget_course_3',
        ],
        compact: false,
      ),
      _WidgetResource(
        title: '随手记',
        providerXml: 'duoyi_note_widget_info.xml',
        layoutXml: 'duoyi_note_widget.xml',
        previewPng: 'widget_note_preview.png',
        receiver: 'DuoyiNoteWidgetProvider',
        previewDrawable: 'widget_note_preview',
        layoutName: 'duoyi_note_widget',
        ids: [
          '@+id/widget_note_bottom_nav',
          '@+id/widget_note_nav_todo',
          '@+id/widget_note_nav_habit',
          '@+id/widget_note_nav_calendar',
          '@+id/widget_note_nav_focus',
          '@+id/widget_note_1',
          '@+id/widget_note_2',
          '@+id/widget_note_3',
        ],
        compact: false,
      ),
      _WidgetResource(
        title: '纪念日',
        providerXml: 'duoyi_anniversary_widget_info.xml',
        layoutXml: 'duoyi_anniversary_widget.xml',
        previewPng: 'widget_anniversary_preview.png',
        receiver: 'DuoyiAnniversaryWidgetProvider',
        previewDrawable: 'widget_anniversary_preview',
        layoutName: 'duoyi_anniversary_widget',
        ids: [
          '@+id/widget_anniversary_bottom_nav',
          '@+id/widget_anniversary_nav_todo',
          '@+id/widget_anniversary_nav_habit',
          '@+id/widget_anniversary_nav_calendar',
          '@+id/widget_anniversary_nav_focus',
          '@+id/widget_anniversary_1',
          '@+id/widget_anniversary_2',
          '@+id/widget_anniversary_3',
        ],
        compact: false,
      ),
      _WidgetResource(
        title: '日记',
        providerXml: 'duoyi_diary_widget_info.xml',
        layoutXml: 'duoyi_diary_widget.xml',
        previewPng: 'widget_diary_preview.png',
        receiver: 'DuoyiDiaryWidgetProvider',
        previewDrawable: 'widget_diary_preview',
        layoutName: 'duoyi_diary_widget',
        ids: [
          '@+id/widget_diary_bottom_nav',
          '@+id/widget_diary_nav_todo',
          '@+id/widget_diary_nav_habit',
          '@+id/widget_diary_nav_calendar',
          '@+id/widget_diary_nav_focus',
          '@+id/widget_diary_1',
          '@+id/widget_diary_2',
          '@+id/widget_diary_3',
        ],
        compact: false,
      ),
    ];

    for (final widget in widgets) {
      test('${widget.title}小组件声明底部导航和 PNG 预览', () {
        _assertWidgetResource(widget);
      });
    }

    test('历史兼容主小组件不再注册为可见组合入口', () {
      _assertWidgetResource(legacyWidget, registered: false);
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final strings = File(
        'android/app/src/main/res/values/strings.xml',
      ).readAsStringSync();
      final service = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();
      final configActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
      ).readAsStringSync();

      expect(manifest, isNot(contains('android:name=".DuoyiWidgetProvider"')));
      expect(strings, isNot(contains('今日待办 / 习惯')));
      expect(strings, contains('历史兼容小组件'));
      expect(service, isNot(contains('_androidProviderName')));
      expect(
        configActivity,
        isNot(contains('DuoyiWidgetProvider.requestUpdate')),
      );
    });

    test('专注、习惯、月历、今日日程、目标保持独立，不再暴露组合入口', () {
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();
      final focusLayout = File(
        'android/app/src/main/res/layout/duoyi_focus_habit_widget.xml',
      ).readAsStringSync();
      final calendarLayout = File(
        'android/app/src/main/res/layout/duoyi_calendar_widget.xml',
      ).readAsStringSync();
      final calendarProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt',
      ).readAsStringSync();
      final manager = File(
        'lib/services/android_widget_manager.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();

      expect(widgetScreen, isNot(contains('专注与习惯预览')));
      expect(widgetScreen, isNot(contains('月历日程预览')));
      expect(widgetScreen, contains('专注预览'));
      expect(widgetScreen, contains('习惯预览'));
      expect(widgetScreen, contains('月历预览'));
      expect(widgetScreen, contains('今日日程预览'));
      expect(widgetScreen, contains('目标预览'));
      expect(widgetScreen, contains('WidgetPreviewCard.focus'));
      expect(widgetScreen, contains('WidgetPreviewCard.habit'));
      expect(widgetScreen, contains('WidgetPreviewCard.schedule'));
      expect(widgetScreen, contains('WidgetPreviewCard.goal'));
      expect(focusLayout, isNot(contains('专注与习惯')));
      expect(focusLayout, isNot(contains('习惯完成')));
      expect(calendarLayout, isNot(contains('widget_calendar_today_')));
      expect(calendarProvider, isNot(contains('calendar_day_summary_')));
      expect(manager, contains('DuoyiWidgetKind.focus'));
      expect(manager, contains('DuoyiWidgetKind.habit'));
      expect(manager, contains('DuoyiWidgetKind.schedule'));
      expect(manager, contains('DuoyiWidgetKind.goal'));
      expect(manager, isNot(contains('DuoyiWidgetKind.focusHabit')));
      expect(manager, isNot(contains("'focus_habit'")));
      expect(mainActivity, isNot(contains('"focus_habit"')));
    });

    test('底部导航每个入口都绑定到对应深链', () {
      final providerSources = {
        'todo': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt',
        ).readAsStringSync(),
        'focus': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusHabitWidgetProvider.kt',
        ).readAsStringSync(),
        'habit': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiHabitWidgetProvider.kt',
        ).readAsStringSync(),
        'calendar': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCalendarWidgetProvider.kt',
        ).readAsStringSync(),
        'schedule': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiScheduleWidgetProvider.kt',
        ).readAsStringSync(),
        'goal': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiGoalWidgetProvider.kt',
        ).readAsStringSync(),
        'course': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiCourseWidgetProvider.kt',
        ).readAsStringSync(),
        'note': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiNoteWidgetProvider.kt',
        ).readAsStringSync(),
        'anniversary': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiAnniversaryWidgetProvider.kt',
        ).readAsStringSync(),
        'diary': File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiDiaryWidgetProvider.kt',
        ).readAsStringSync(),
      };

      for (final source in providerSources.values) {
        expect(source, contains('Uri.parse("duoyi://tab/todo")'));
        expect(source, contains('Uri.parse("duoyi://tab/habit")'));
        expect(source, contains('Uri.parse("duoyi://tab/calendar")'));
        expect(source, contains('Uri.parse("duoyi://tab/focus")'));
        expect(source, contains('HomeWidgetLaunchIntent.getActivity'));
      }
      expect(providerSources['todo'], contains('duoyi://action/quick_todo'));
      expect(
        providerSources['todo'],
        contains('R.id.widget_todo_quick_add, quickAdd'),
      );
      expect(
        providerSources['focus'],
        contains('duoyi://action/start_pomodoro'),
      );
      expect(providerSources['focus'], contains('focus_timer_running'));
      expect(
        providerSources['focus'],
        contains('focus_timer_remaining_seconds'),
      );
      expect(providerSources['focus'], contains('focus_timer_ends_at_millis'));
      expect(providerSources['focus'], contains('formatTimer'));
      expect(providerSources['focus'], contains('查看倒计时'));
      expect(
        providerSources['habit'],
        contains('duoyi://action/checkin_habit?id='),
      );
      expect(
        providerSources['habit'],
        contains('R.id.widget_habit_hint, quickCheckHabit'),
      );
      expect(providerSources['goal'], contains('duoyi://tab/today'));
      expect(providerSources['goal'], contains('goal_highlight_1_id'));
      expect(providerSources['goal'], contains('goal_highlight_2_id'));
      expect(providerSources['goal'], contains('goal_highlight_3_id'));
      expect(
        providerSources['goal'],
        contains(
          'Uri.parse((prefs.getString(key, "") ?: "").ifBlank { fallback })',
        ),
      );
      expect(providerSources['course'], contains('course_highlight_1_id'));
      expect(providerSources['course'], contains('course_highlight_2_id'));
      expect(providerSources['schedule'], contains('schedule_highlight_1_id'));
      expect(providerSources['schedule'], contains('schedule_highlight_2_id'));
      expect(providerSources['schedule'], contains('schedule_highlight_3_id'));
      expect(providerSources['note'], contains('Uri.parse("duoyi://note")'));
      expect(providerSources['note'], contains('note_highlight_1_id'));
      expect(providerSources['note'], contains('note_highlight_2_id'));
      expect(providerSources['note'], contains('note_highlight_3_id'));
      expect(
        providerSources['anniversary'],
        contains('Uri.parse("duoyi://anniversary")'),
      );
      expect(
        providerSources['anniversary'],
        contains('memorial_highlight_1_id'),
      );
      expect(
        providerSources['anniversary'],
        contains('memorial_highlight_2_id'),
      );
      expect(
        providerSources['anniversary'],
        contains('memorial_highlight_3_id'),
      );
      expect(providerSources['diary'], contains('Uri.parse("duoyi://diary")'));
      expect(providerSources['diary'], contains('diary_highlight_1_id'));
      expect(providerSources['diary'], contains('diary_highlight_2_id'));
      expect(providerSources['diary'], contains('diary_highlight_3_id'));
      expect(
        providerSources['focus'],
        isNot(contains('HomeWidgetBackgroundIntent')),
      );
    });

    test('小组件样式密度设置会写入并影响原生行数', () {
      final service = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();
      final helper = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetDisplayMode.kt',
      ).readAsStringSync();

      expect(service, contains('setDisplayMode'));
      expect(service, contains('widget_display_mode'));
      expect(widgetScreen, contains('小组件样式'));
      expect(widgetScreen, contains('SegmentedButton<_WidgetDisplayMode>'));
      expect(widgetScreen, contains('HomeWidgetService.setDisplayMode'));
      expect(helper, contains('standardOrDetailedVisibility'));
      expect(helper, contains('detailedVisibility'));
      final todoLayout = File(
        'android/app/src/main/res/layout/duoyi_todo_widget.xml',
      ).readAsStringSync();
      final todoProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt',
      ).readAsStringSync();
      expect(todoLayout, contains('@+id/widget_todo_row_2'));
      expect(todoLayout, contains('@+id/widget_todo_row_3'));
      expect(
        todoProvider,
        contains('views.setViewVisibility(R.id.widget_todo_row_2'),
      );
      expect(
        todoProvider,
        contains('views.setViewVisibility(R.id.widget_todo_row_3'),
      );
      for (final widget in widgets) {
        final source = File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/${widget.receiver}.kt',
        ).readAsStringSync();
        expect(source, contains('DuoyiWidgetDisplayMode'));
      }
    });

    test('桌面快捷创建失败会返回明确原因并接入成功回调', () {
      final manager = File(
        'lib/services/android_widget_manager.dart',
      ).readAsStringSync();
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final callbackReceiver = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPinResultReceiver.kt',
      ).readAsStringSync();

      expect(manager, contains('enum AndroidWidgetPinResult'));
      expect(manager, contains('permissionDenied'));
      expect(manager, contains('invalidKind'));
      expect(manager, contains('invokeMethod<String>'));
      expect(manager, contains("'requestPinWidget'"));
      expect(widgetScreen, contains('AndroidWidgetPinResult.unsupported'));
      expect(widgetScreen, contains('AndroidWidgetPinResult.permissionDenied'));
      expect(widgetScreen, contains('当前桌面不支持应用内直接添加小组件'));
      expect(widgetScreen, contains('系统没有允许本次添加到桌面'));
      expect(mainActivity, contains('PendingIntent.getBroadcast'));
      expect(
        mainActivity,
        contains('DuoyiWidgetPinResultReceiver::class.java'),
      );
      expect(
        mainActivity,
        contains('requestPinAppWidget(provider, null, callback)'),
      );
      expect(mainActivity, contains('return "unsupported"'));
      expect(mainActivity, contains('"permission_denied"'));
      expect(mainActivity, contains('return "invalid_kind"'));
      expect(mainActivity, contains('"unavailable"'));
      expect(
        manifest,
        contains('android:name=".DuoyiWidgetPinResultReceiver"'),
      );
      expect(callbackReceiver, contains('class DuoyiWidgetPinResultReceiver'));
      for (final widget in widgets) {
        expect(
          callbackReceiver,
          contains('${widget.receiver}.requestUpdate(context)'),
          reason: '${widget.receiver} should refresh after pin callback',
        );
      }
    });

    test('升级后刷新已有小组件，避免旧布局继续留在桌面', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      for (final widget in widgets) {
        final source = File(
          'android/app/src/main/kotlin/com/duoyi/duoyi/${widget.receiver}.kt',
        ).readAsStringSync();
        expect(
          RegExp(
            'android:name="\\.${widget.receiver}"[\\s\\S]*?android\\.intent\\.action\\.MY_PACKAGE_REPLACED',
          ).hasMatch(manifest),
          isTrue,
          reason: '${widget.receiver} should refresh on package replace',
        );
        expect(source, contains('Intent.ACTION_MY_PACKAGE_REPLACED'));
        expect(source, contains('fun requestUpdate(context: Context)'));
        expect(source, contains('${widget.receiver}::class.java'));
      }
    });

    test('应用内小组件页展示 10 个可见独立预览并接入底部导航', () {
      final main = File('lib/main.dart').readAsStringSync();
      final deepLinkService = File(
        'lib/services/deep_link_service.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final service = File(
        'lib/services/home_widget_service.dart',
      ).readAsStringSync();
      final widgetScreen = File(
        'lib/screens/widget_screen.dart',
      ).readAsStringSync();

      expect(main, contains('WidgetScreen(key: widgetKey)'));
      expect(main, contains("label: I18n.tr('nav.widget')"));
      expect(main, contains("action == 'quick_todo'"));
      expect(main, contains("action == 'checkin_habit'"));
      expect(main, contains('_homeWidgetEventsForToday'));
      expect(main, contains('_homeWidgetEventDeepLink'));
      expect(main, contains("'duoyi://goal/\${Uri.encodeComponent(goal.id)}'"));
      expect(
        main,
        contains("'duoyi://course/\${Uri.encodeComponent(course.id)}'"),
      );
      expect(main, contains("'duoyi://note/\${Uri.encodeComponent(note.id)}'"));
      expect(
        main,
        contains("'duoyi://diary/\${Uri.encodeComponent(entry.id)}'"),
      );
      expect(
        main,
        contains(
          'TodayDetailRouter.open(ctx, TodaySectionKind.courses, id: id)',
        ),
      );
      expect(
        main,
        contains('TodayDetailRouter.open(ctx, TodaySectionKind.notes, id: id)'),
      );
      expect(
        main,
        contains('TodayDetailRouter.open(ctx, TodaySectionKind.diary, id: id)'),
      );
      expect(
        main,
        isNot(contains("todayEventSummary: top3.isEmpty ? '今日没有日程'")),
      );
      expect(main, contains('habits.incrementHabit(id)'));
      expect(main, contains('_showQuickTodoDialog'));
      expect(main, contains('DeepLinkService.takeInitialLink()'));
      expect(deepLinkService, contains('_isDuoyiDeepLink(uri)'));
      expect(mainActivity, contains('duoyiDeepLinkFrom(intent)'));
      expect(mainActivity, contains('pendingInitialDeepLink'));
      expect(service, contains('habit_quick_check_id'));
      expect(service, contains('habit_quick_check_label'));
      expect(widgetScreen, contains('WidgetPreviewCard'));
      expect(widgetScreen, contains('_WidgetPreviewNav'));
      for (final title in [
        '今日待办预览',
        '专注预览',
        '习惯预览',
        '月历预览',
        '今日日程预览',
        '目标预览',
        '课程表预览',
        '随手记预览',
        '纪念日预览',
        '日记预览',
      ]) {
        expect(widgetScreen, contains(title));
      }
      expect(widgetScreen, isNot(contains('多仪概览')));
      expect(widgetScreen, isNot(contains('WidgetPreviewCard.overview')));
      expect(widgetScreen, isNot(contains('WidgetPreviewKind.overview')));
      expect(widgetScreen, isNot(contains('_WidgetPreviewOverviewBody')));
      expect(widgetScreen, contains("'待办', '习惯', '日历', '专注'"));
      expect(widgetScreen, contains('展示进行中目标和进度'));
      expect(widgetScreen, contains('发版准备 · 68%'));
      expect(widgetScreen, contains('今日优先处理'));
      expect(widgetScreen, contains('+ 添加待办'));
      expect(widgetScreen, contains('开始 25 分钟专注'));
    });

    test('桌面快捷创建只支持 10 种可见独立小组件', () {
      final manager = File(
        'lib/services/android_widget_manager.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();

      for (final kind in [
        'todo',
        'focus',
        'habit',
        'calendar',
        'schedule',
        'goal',
        'course',
        'note',
        'anniversary',
        'diary',
      ]) {
        expect(manager, contains('DuoyiWidgetKind.$kind'));
        expect(manager, contains("'$kind'"));
        expect(mainActivity, contains('"$kind"'));
      }
      expect(manager, isNot(contains('DuoyiWidgetKind.overview')));
      expect(manager, isNot(contains("'overview'")));
      expect(mainActivity, isNot(contains('"overview"')));
      expect(
        mainActivity,
        isNot(contains('else -> ComponentName(this, DuoyiWidgetProvider')),
      );
      for (final receiver in widgets.map((w) => w.receiver)) {
        expect(mainActivity, contains('$receiver::class.java'));
      }
    });

    test('10 种可见独立小组件都通过配置入口初始化对应 provider', () {
      final configActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetConfigActivity.kt',
      ).readAsStringSync();

      expect(configActivity, contains('getAppWidgetInfo(widgetId)'));
      expect(
        configActivity,
        contains('requestInitialUpdate(providerClassName)'),
      );
      for (final widget in widgets) {
        final provider = File(
          'android/app/src/main/res/xml/${widget.providerXml}',
        ).readAsStringSync();
        expect(
          provider,
          contains(
            'android:configure="com.duoyi.duoyi.DuoyiWidgetConfigActivity"',
          ),
          reason:
              '${widget.providerXml} should initialize through config activity',
        );
        expect(
          configActivity,
          contains('${widget.receiver}.requestUpdate(applicationContext)'),
          reason: '${widget.receiver} should be refreshed after placement',
        );
      }
    });

    test('10 种可见独立小组件都声明可调整尺寸范围', () {
      for (final widget in widgets) {
        final provider = File(
          'android/app/src/main/res/xml/${widget.providerXml}',
        ).readAsStringSync();
        expect(provider, contains('android:resizeMode="horizontal|vertical"'));
        expect(provider, contains('android:minResizeWidth="110dp"'));
        expect(provider, contains('android:minResizeHeight="80dp"'));
        expect(
          provider,
          contains(
            widget.compact
                ? 'android:maxResizeWidth="360dp"'
                : 'android:maxResizeWidth="420dp"',
          ),
        );
        expect(
          provider,
          contains(
            widget.compact
                ? 'android:maxResizeHeight="320dp"'
                : 'android:maxResizeHeight="260dp"',
          ),
        );
      }
    });
  });
}

void _assertWidgetResource(_WidgetResource widget, {bool registered = true}) {
  final provider = File(
    'android/app/src/main/res/xml/${widget.providerXml}',
  ).readAsStringSync();
  final layout = File(
    'android/app/src/main/res/layout/${widget.layoutXml}',
  ).readAsStringSync();
  final preview = File(
    'android/app/src/main/res/drawable-nodpi/${widget.previewPng}',
  );

  expect(
    provider,
    contains('android:previewImage="@drawable/${widget.previewDrawable}"'),
  );
  expect(
    provider,
    contains('android:previewLayout="@layout/${widget.layoutName}"'),
  );
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  if (registered) {
    expect(
      _receiverBlock(manifest, widget.receiver),
      contains('android:resource="@drawable/${widget.previewDrawable}"'),
    );
  } else {
    expect(
      manifest,
      isNot(contains('android:name=".${widget.receiver}"')),
      reason: '${widget.receiver} should not be visible in widget picker',
    );
  }
  expect(preview.existsSync(), isTrue);
  expect(preview.lengthSync(), greaterThan(1024));
  expect(_pngSize(preview), const _PngSize(720, 480));
  expect(_pngContainsTextLikeContent(preview), isTrue);
  for (final id in widget.ids) {
    expect(
      layout,
      contains(id),
      reason: '${widget.layoutXml} should contain $id',
    );
  }
  expect(
    File(
      'android/app/src/main/res/drawable/${widget.previewDrawable}.xml',
    ).existsSync(),
    isFalse,
  );
}

String _receiverBlock(String manifest, String receiverName) {
  final match = RegExp(
    '<receiver[\\s\\S]*?android:name="\\.$receiverName"[\\s\\S]*?</receiver>',
  ).firstMatch(manifest);
  expect(match, isNotNull, reason: '$receiverName receiver not found');
  return match!.group(0)!;
}

bool _pngContainsTextLikeContent(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  // The real preview is a rendered screenshot-style PNG with many colors and
  // dark text pixels. A blank/abstract placeholder typically lacks this range.
  final unique = <int>{};
  var darkPixels = 0;
  for (var i = 0; i < bytes.length - 2; i += 97) {
    final r = bytes[i];
    final g = bytes[i + 1];
    final b = bytes[i + 2];
    unique.add((r << 16) | (g << 8) | b);
    if (r < 80 && g < 80 && b < 80) darkPixels++;
  }
  return width == 720 && height == 480 && unique.length > 24 && darkPixels > 5;
}

_PngSize _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  expect(bytes.take(signature.length).toList(), signature);
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return _PngSize(data.getUint32(16), data.getUint32(20));
}

class _WidgetResource {
  final String title;
  final String providerXml;
  final String layoutXml;
  final String previewPng;
  final String receiver;
  final String previewDrawable;
  final String layoutName;
  final List<String> ids;
  final bool compact;

  const _WidgetResource({
    required this.title,
    required this.providerXml,
    required this.layoutXml,
    required this.previewPng,
    required this.receiver,
    required this.previewDrawable,
    required this.layoutName,
    required this.ids,
    required this.compact,
  });
}

class _PngSize {
  final int width;
  final int height;

  const _PngSize(this.width, this.height);

  @override
  bool operator ==(Object other) =>
      other is _PngSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}
