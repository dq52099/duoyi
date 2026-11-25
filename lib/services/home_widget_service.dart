import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../core/account_preference_writes.dart';
import '../core/app_brand.dart';
import '../core/brand_strings.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/calendar_date_navigation.dart';
import '../core/platform_info.dart';
import '../providers/theme_provider.dart';
import 'android_widget_manager.dart';
import 'widget_launch_service.dart';

/// Pushes today's stats and brand strings out to Android/iOS home widgets.
/// 在 web / 其他平台下为空实现。
class HomeWidgetService {
  static const String _androidTodoProviderName = 'DuoyiTodoWidgetProvider';
  static const String _androidFocusProviderName =
      'DuoyiFocusHabitWidgetProvider';
  static const String _androidHabitProviderName = 'DuoyiHabitWidgetProvider';
  static const String _androidCalendarProviderName =
      'DuoyiCalendarWidgetProvider';
  static const String _androidScheduleProviderName =
      'DuoyiScheduleWidgetProvider';
  static const String _androidGoalProviderName = 'DuoyiGoalWidgetProvider';
  static const String _androidCourseProviderName = 'DuoyiCourseWidgetProvider';
  static const String _androidNoteProviderName = 'DuoyiNoteWidgetProvider';
  static const String _androidAnniversaryProviderName =
      'DuoyiAnniversaryWidgetProvider';
  static const String _androidDiaryProviderName = 'DuoyiDiaryWidgetProvider';
  static const String _iosTodoWidgetName = 'DuoyiTodoWidget';
  static const String _iosFocusWidgetName = 'DuoyiFocusWidget';
  static const String _iosHabitWidgetName = 'DuoyiHabitWidget';
  static const String _iosCalendarWidgetName = 'DuoyiCalendarWidget';
  static const String _iosScheduleWidgetName = 'DuoyiScheduleWidget';
  static const String _iosGoalWidgetName = 'DuoyiGoalWidget';
  static const String _iosCourseWidgetName = 'DuoyiCourseWidget';
  static const String _iosNoteWidgetName = 'DuoyiNoteWidget';
  static const String _iosAnniversaryWidgetName = 'DuoyiAnniversaryWidget';
  static const String _iosDiaryWidgetName = 'DuoyiDiaryWidget';
  static const String _appGroupId = 'group.com.duoyi.duoyi';
  static const String _pendingBgActionsKey = 'duoyi_widget_pending_bg_actions';
  static const String _todoCompletedBgIdsKey = 'todo_completed_bg_ids';
  static const String _habitCheckedBgIdsKey = 'habit_checked_bg_ids';

  /// 账号清理（登出/切号）时写回小组件的兜底 payload。文案值经 I18n 取词：
  /// en 用户登出后小组件不应回退为中文占位；其余为与语言无关的默认数值。
  static Map<String, Object> get accountPayloadDefaults => <String, Object>{
    'widget_account_nonce': '',
    'widget_snapshot_day': '',
    'widget_snapshot_utc_offset_minutes': 0,
    'widget_locale': I18n.current.name,
    'widget_first_day_of_week': DateTime.monday,
    'todo_count': 0,
    'habit_percent': 0,
    'habit_active_count': 0,
    'pomodoro_today': 0,
    'focus_minutes_today': 0,
    'brand_app_title': I18n.tr('mine.about.title'),
    'nav_todo': I18n.tr('nav.todo'),
    'nav_habit': I18n.tr('nav.habit'),
    'nav_calendar': I18n.tr('nav.calendar'),
    'nav_focus': I18n.tr('nav.focus'),
    'todo_top3_count': 0,
    'todo_top3_1': I18n.tr('widget.todo_top3_empty'),
    'todo_top3_1_id': '',
    'todo_top3_2': '',
    'todo_top3_2_id': '',
    'todo_top3_3': '',
    'todo_top3_3_id': '',
    'goal_highlight_1': I18n.tr('widget.goal_empty'),
    'goal_highlight_1_id': '',
    'goal_highlight_2': '',
    'goal_highlight_2_id': '',
    'goal_highlight_3': '',
    'goal_highlight_3_id': '',
    'anniversary_highlight_1': I18n.tr('widget.anniversary_empty'),
    'anniversary_highlight_1_id': '',
    'anniversary_highlight_2': '',
    'anniversary_highlight_2_id': '',
    'course_highlight_1': I18n.tr('widget.course_empty'),
    'course_highlight_1_id': '',
    'course_highlight_2': '',
    'course_highlight_2_id': '',
    'course_highlight_3': '',
    'course_highlight_3_id': '',
    'note_highlight_1': I18n.tr('widget.note_empty'),
    'note_highlight_1_id': '',
    'note_highlight_2': '',
    'note_highlight_2_id': '',
    'note_highlight_3': '',
    'note_highlight_3_id': '',
    'memorial_highlight_1': I18n.tr('widget.anniversary_empty'),
    'memorial_highlight_1_id': '',
    'memorial_highlight_2': '',
    'memorial_highlight_2_id': '',
    'memorial_highlight_3': '',
    'memorial_highlight_3_id': '',
    'diary_highlight_1': I18n.tr('widget.diary_empty'),
    'diary_highlight_1_id': '',
    'diary_highlight_2': '',
    'diary_highlight_2_id': '',
    'diary_highlight_3': '',
    'diary_highlight_3_id': '',
    'today_event_summary': I18n.tr('widget.no_schedule_today'),
    'schedule_highlight_1': '· ${I18n.tr('widget.no_schedule_today')}',
    'schedule_highlight_1_id': '',
    'schedule_highlight_2': '',
    'schedule_highlight_2_id': '',
    'schedule_highlight_3': '',
    'schedule_highlight_3_id': '',
    'calendar_month_summary': I18n.tr('widget.calendar_month_summary'),
    'focus_summary': I18n.tr('widget.focus_not_started'),
    'habit_summary': I18n.tr('widget.habit_pending'),
    'streak_summary':
        '${I18n.tr('widget.streak_record_prefix')}0'
        '${I18n.tr('widget.streak_suffix')}',
    'next_focus_label': '25${I18n.tr('widget.next_focus_suffix')}',
    'focus_timer_count_up': false,
    'focus_timer_started_at_millis': 0,
    'focus_timer_running': false,
    'focus_timer_remaining_seconds': 0,
    'focus_timer_total_seconds': 0,
    'focus_timer_ends_at_millis': 0,
    'focus_timer_label': I18n.tr('widget.focus_countdown'),
    'habit_quick_check_id': '',
    'habit_quick_check_label': I18n.tr('widget.habit_quick_check_hint'),
    'widget_theme_brand_id': 'defaultBrand',
    'widget_theme_card_skin_id': 'plain_card',
    'widget_theme_dark': false,
    'widget_theme_primary': '#FF0066D6',
    'widget_theme_background': '#FFF6F7F9',
    'widget_theme_surface': '#FFFFFFFF',
    'widget_theme_nav_background': '#FFF1F3F6',
    'widget_theme_border': '#000066D6',
    'widget_theme_text': '#FF1F2933',
    'widget_theme_muted_text': '#FF667085',
    'widget_theme_on_primary': '#FFFFFFFF',
    'widget_theme_accent_start': '#FF0066D6',
    'widget_theme_accent_end': '#FF3898FF',
    'widget_theme_background_asset_key': '',
    'widget_theme_corner_radius_dp': 16,
    'widget_theme_control_radius_dp': 12,
    'widget_theme_border_width_dp': 0,
  };
  static Future<bool> Function()? dashboardDataRefresher;

  /// A hint to the hydrated publication queue; the OS may suspend before finish.
  static void Function(bool inBackground)? widgetLifecycleChanged;

  static void setAppInBackground(bool value) {
    widgetLifecycleChanged?.call(value);
  }

  /// Android and iOS publish one complete native snapshot instead of exposing
  /// partially updated HomeWidget preference keys to native readers.
  static Future<bool> Function(Map<String, Object> values, DateTime capturedAt)?
  publicationWriter;
  static Future<bool> Function(Uri uri)? publicationActionValidator;

  static Future<bool> refreshDashboardData() async {
    if (!_supported) return false;
    final refresh = dashboardDataRefresher;
    return refresh == null ? false : await refresh();
  }

  static Future<bool> refreshPublishedWidgets() => _updateAllWidgets();

  static void invalidatePushSignature() {
    _lastPushSignature = '';
    _refreshPending = true;
  }

  @visibleForTesting
  static bool? supportedForTesting;

  @visibleForTesting
  static bool? isAndroidForTesting;

  @visibleForTesting
  static bool? nativePublicationForTesting;

  static bool get usesNativePublication =>
      nativePublicationForTesting ??
      (!kIsWeb && (PlatformInfo.isAndroid || PlatformInfo.isIOS));

  static String _lastThemeSignature = '';
  static String _lastPushSignature = '';
  static final Map<String, Object> _lastSavedPayloadValues = <String, Object>{};
  static Future<bool>? _accountPayloadClearInFlight;
  static Future<void> _payloadQueue = Future<void>.value();
  static int _accountGeneration = 0;
  static int get accountGeneration => _accountGeneration;
  static bool _refreshPending = false;
  static bool _clearOptimisticBgIdsOnNextRefresh = false;
  static bool _accountPayloadStorageCleared = true;
  static String? _accountActionNonce;
  static Future<void>? _nonceInitialization;

  static String _newActionNonce() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Future<void> _ensureActionNonce() async {
    if (_accountActionNonce != null) return;
    final existing = _nonceInitialization;
    if (existing != null) return existing;
    final generation = _accountGeneration;
    final pending = () async {
      final stored = await HomeWidget.getWidgetData<String>(
        'widget_account_nonce',
      );
      if (generation != _accountGeneration) return;
      // Native snapshot readers require a nonblank nonce. Keep valid raw
      // identity strings intact, but recover corrupt blank data on cold start.
      final nonce = stored?.trim().isNotEmpty == true
          ? stored!
          : _newActionNonce();
      // Persist only with the serialized payload. Independent init calls must
      // never race account clearing by publishing an old nonce afterwards.
      if (generation == _accountGeneration) _accountActionNonce = nonce;
    }();
    _nonceInitialization = pending;
    try {
      await pending;
    } finally {
      if (identical(_nonceInitialization, pending)) _nonceInitialization = null;
    }
  }

  static Future<bool> isCurrentWidgetAction(Uri uri) async {
    if (uri.queryParameters['source'] != 'widget') return true;
    final nativeValidator = publicationActionValidator;
    if (usesNativePublication) {
      if (nativeValidator == null) return false;
      try {
        return await nativeValidator(uri);
      } catch (error, stackTrace) {
        debugPrint(
          '[HomeWidget] action validation failed: $error\n$stackTrace',
        );
        return false;
      }
    }
    final generation = _accountGeneration;
    if (!await init() || generation != _accountGeneration) return false;
    final now = DateTime.now();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return uri.queryParameters['widget_day'] == day &&
        uri.queryParameters['widget_account'] == _accountActionNonce &&
        uri.queryParameters['widget_offset'] ==
            now.timeZoneOffset.inMinutes.toString();
  }

  // All payload writers share one queue. Account resets invalidate old work
  // immediately, including a push already waiting for the clear to finish.
  static Future<bool> _serializePayload(Future<bool> Function() operation) {
    final result = _payloadQueue.then((_) => operation());
    _payloadQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  static bool get _supported {
    final override = supportedForTesting;
    if (override != null) return override;
    if (kIsWeb) return false;
    return (isAndroidForTesting ?? PlatformInfo.isAndroid) ||
        PlatformInfo.isIOS;
  }

  static bool get _isAndroid {
    if (kIsWeb) return false;
    if (supportedForTesting == false) return false;
    return isAndroidForTesting ?? PlatformInfo.isAndroid;
  }

  static Future<bool> init() async {
    if (!_supported) return true;
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      if (!usesNativePublication) await _ensureActionNonce();
      return true;
    } catch (e, st) {
      debugPrint('[HomeWidget] init failed: $e\n$st');
      return false;
    }
  }

  static Future<bool> setDisplayMode(
    String mode, {
    int? expectedAccountGeneration,
    int? expectedPreferenceGeneration,
  }) async {
    if (!_supported) return true;
    final generation = expectedAccountGeneration ?? _accountGeneration;
    final preferenceGeneration =
        expectedPreferenceGeneration ?? AccountPreferenceWrites.generation;
    bool isCurrent() =>
        generation == _accountGeneration &&
        preferenceGeneration == AccountPreferenceWrites.generation;
    // This native operation is untracked. Never wait for cleanup while holding
    // the payload queue: account cleanup itself needs that queue to drain.
    await AccountPreferenceWrites.waitForBoundary();
    if (!isCurrent()) return false;
    await _drainPendingAccountClear();
    return _serializePayload(() async {
      if (!isCurrent()) return false;
      try {
        final saved = await HomeWidget.saveWidgetData<String>(
          'widget_display_mode',
          mode,
        );
        if (saved != true || !isCurrent()) return false;
        if (PlatformInfo.isAndroid) {
          final applied =
              await AndroidWidgetManager.applyDisplayModeToExistingWidgets(
                AndroidWidgetStyle.fromId(mode),
              );
          if (applied == null || !isCurrent()) return false;
        }
        if (!isCurrent()) return false;
        final refreshed = await _updateAllWidgets();
        return refreshed && isCurrent();
      } catch (e, st) {
        debugPrint('[HomeWidget] setDisplayMode($mode) failed: $e\n$st');
        return false;
      }
    });
  }

  static Future<bool> updateTheme(HomeWidgetThemePayload theme) async {
    if (!_supported) return true;
    if (usesNativePublication) return publicationWriter != null;
    final generation = _accountGeneration;
    await _drainPendingAccountClear();
    return _serializePayload(() async {
      if (generation != _accountGeneration) return false;
      final signature = theme.signature;
      if (signature == _lastThemeSignature && !_refreshPending) return true;
      try {
        final saveResult = await _saveWidgetPayload(theme.payloadValues);
        if (!saveResult.ok || generation != _accountGeneration) return false;
        _refreshPending |= saveResult.changed;
        if (!_refreshPending) {
          _lastThemeSignature = signature;
          return true;
        }
        final ok = await _updateAllWidgets();
        if (ok && generation == _accountGeneration) {
          _lastThemeSignature = signature;
          _refreshPending = false;
        }
        return ok;
      } catch (e, st) {
        debugPrint('[HomeWidget] updateTheme failed: $e\n$st');
        return false;
      }
    });
  }

  static void resetAccountCache() {
    _accountGeneration++;
    _accountPayloadStorageCleared = !_supported;
    _accountActionNonce = _newActionNonce();
    _refreshPending = true;
    _lastThemeSignature = '';
    _lastPushSignature = '';
    _lastSavedPayloadValues.clear();
    _accountPayloadClearInFlight =
        (_accountPayloadClearInFlight ?? Future<bool>.value(true)).then(
          (_) => clearAccountWidgetData(),
        );
  }

  static Future<bool> waitForAccountClear() async {
    final pending = _accountPayloadClearInFlight;
    if (pending != null) await pending;
    return _accountPayloadStorageCleared;
  }

  static Future<bool> clearAccountWidgetData() async {
    if (!_supported) return true;
    return _serializePayload(() async {
      try {
        final initialized = await init();
        if (!initialized) return false;
        _lastThemeSignature = '';
        _lastPushSignature = '';
        _lastSavedPayloadValues.clear();
        if (!await _saveWidgetPayloadValue('widget_snapshot_day', '')) {
          return false;
        }
        final saveResult = await _saveWidgetPayload({
          ...accountPayloadDefaults,
          'widget_account_nonce': _accountActionNonce ?? '',
        }, force: true);
        if (!saveResult.ok) return false;
        _accountPayloadStorageCleared = true;
        _refreshPending = true;
        await _clearPendingBgState(includeActionQueue: true);
        final ok = await _updateAllWidgets();
        if (ok) _refreshPending = false;
        return ok;
      } catch (e, st) {
        debugPrint('[HomeWidget] clear account widget data failed: $e\n$st');
        return false;
      }
    });
  }

  static Future<void> _drainPendingAccountClear() async {
    while (true) {
      final pending = _accountPayloadClearInFlight;
      if (pending == null) return;
      await pending;
      if (identical(_accountPayloadClearInFlight, pending)) {
        _accountPayloadClearInFlight = null;
        return;
      }
    }
  }

  static Future<_HomeWidgetPayloadSaveResult> _saveWidgetPayload(
    Map<String, Object> payload, {
    bool force = false,
  }) async {
    final saveOperations = <Future<bool>>[];
    var changed = false;
    for (final entry in payload.entries) {
      if (!force && _lastSavedPayloadValues[entry.key] == entry.value) {
        continue;
      }
      changed = true;
      saveOperations.add(_saveWidgetPayloadValue(entry.key, entry.value));
    }
    if (saveOperations.isEmpty) {
      return const _HomeWidgetPayloadSaveResult(ok: true, changed: false);
    }
    final results = await Future.wait(saveOperations);
    return _HomeWidgetPayloadSaveResult(
      ok: results.every((saved) => saved),
      changed: changed,
    );
  }

  static Future<bool> _saveWidgetPayloadValue(String key, Object value) async {
    final bool? saved;
    if (value is bool) {
      saved = await HomeWidget.saveWidgetData<bool>(key, value);
    } else if (value is int) {
      saved = await HomeWidget.saveWidgetData<int>(key, value);
    } else {
      saved = await HomeWidget.saveWidgetData<String>(key, value.toString());
    }
    if (saved == false) return false;
    _lastSavedPayloadValues[key] = value;
    return true;
  }

  static Future<bool> push({
    required int todoCount,
    required int habitPercent,
    int habitActiveCount = -1,
    required int pomodoroToday,
    required int focusMinutesToday,
    required BrandStrings strings,
    List<String> todoTop3 = const [],
    List<String> todoTop3Ids = const [],
    List<String> goalHighlights = const [],
    List<String> goalHighlightIds = const [],
    List<String> anniversaryHighlights = const [],
    List<String> anniversaryHighlightIds = const [],
    List<String> courseHighlights = const [],
    List<String> courseHighlightIds = const [],
    List<String> noteHighlights = const [],
    List<String> noteHighlightIds = const [],
    List<String> memorialHighlights = const [],
    List<String> memorialHighlightIds = const [],
    List<String> diaryHighlights = const [],
    List<String> diaryHighlightIds = const [],
    List<String> scheduleHighlights = const [],
    List<String> scheduleHighlightIds = const [],
    String? todayEventSummary,
    String? focusSummary,
    String? habitSummary,
    String? streakSummary,
    String? nextFocusLabel,
    String? calendarMonthSummary,
    bool focusTimerCountUp = false,
    int focusTimerStartedAtMillis = 0,
    bool focusTimerRunning = false,
    int focusTimerRemainingSeconds = 0,
    int focusTimerTotalSeconds = 0,
    int focusTimerEndsAtMillis = 0,
    String? focusTimerLabel,
    String habitQuickCheckId = '',
    String? habitQuickCheckLabel,
    required HomeWidgetThemePayload theme,
    bool force = false,
    DateTime? snapshotAt,
    int firstDayOfWeek = DateTime.monday,
    bool Function()? isPresentationCurrent,
  }) async {
    if (!_supported) return true;
    final locale = I18n.current;
    final resolvedTodayEventSummary =
        todayEventSummary ?? I18n.tr('widget.no_schedule_today');
    final resolvedFocusSummary =
        focusSummary ?? I18n.tr('widget.focus_not_started');
    final resolvedHabitSummary =
        habitSummary ?? I18n.tr('widget.habit_pending');
    final resolvedStreakSummary =
        streakSummary ??
        '${I18n.tr('widget.streak_record_prefix')}0${I18n.tr('widget.streak_suffix')}';
    final resolvedNextFocusLabel =
        nextFocusLabel ?? '25${I18n.tr('widget.next_focus_suffix')}';
    final resolvedCalendarMonthSummary =
        calendarMonthSummary ?? I18n.tr('widget.calendar_month_summary');
    final resolvedFocusTimerLabel =
        focusTimerLabel ?? I18n.tr('widget.focus_countdown');
    final resolvedHabitQuickCheckLabel =
        habitQuickCheckLabel ?? I18n.tr('widget.habit_quick_check_hint');
    final capturedAt = snapshotAt ?? DateTime.now();
    final generation = _accountGeneration;
    final first = CalendarDateNavigation.normalizeFirstDayOfWeek(
      firstDayOfWeek,
    );
    bool isCurrent() =>
        generation == _accountGeneration &&
        locale == I18n.current &&
        (isPresentationCurrent?.call() ?? true);
    if (!isCurrent()) return false;
    await _drainPendingAccountClear();
    return _serializePayload(() async {
      final nativeWriter = usesNativePublication ? publicationWriter : null;
      if (usesNativePublication && nativeWriter == null) return false;
      if (!isCurrent()) {
        return false;
      }
      if ((nativeWriter == null && !await init()) || !isCurrent()) {
        return false;
      }
      final now = capturedAt;
      final day =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final offset = now.timeZoneOffset.inMinutes;
      final signature = _pushSignature(
        todoCount: todoCount,
        habitPercent: habitPercent,
        pomodoroToday: pomodoroToday,
        focusMinutesToday: focusMinutesToday,
        strings: strings,
        todoTop3: todoTop3,
        todoTop3Ids: todoTop3Ids,
        goalHighlights: goalHighlights,
        goalHighlightIds: goalHighlightIds,
        anniversaryHighlights: anniversaryHighlights,
        anniversaryHighlightIds: anniversaryHighlightIds,
        courseHighlights: courseHighlights,
        courseHighlightIds: courseHighlightIds,
        noteHighlights: noteHighlights,
        noteHighlightIds: noteHighlightIds,
        memorialHighlights: memorialHighlights,
        memorialHighlightIds: memorialHighlightIds,
        diaryHighlights: diaryHighlights,
        diaryHighlightIds: diaryHighlightIds,
        scheduleHighlights: scheduleHighlights,
        scheduleHighlightIds: scheduleHighlightIds,
        todayEventSummary: resolvedTodayEventSummary,
        focusSummary: resolvedFocusSummary,
        habitSummary: resolvedHabitSummary,
        streakSummary: resolvedStreakSummary,
        nextFocusLabel: resolvedNextFocusLabel,
        calendarMonthSummary: resolvedCalendarMonthSummary,
        focusTimerCountUp: focusTimerCountUp,
        focusTimerStartedAtMillis: focusTimerStartedAtMillis,
        focusTimerRunning: focusTimerRunning,
        focusTimerRemainingSeconds: focusTimerRemainingSeconds,
        focusTimerTotalSeconds: focusTimerTotalSeconds,
        focusTimerEndsAtMillis: focusTimerEndsAtMillis,
        focusTimerLabel: resolvedFocusTimerLabel,
        habitQuickCheckId: habitQuickCheckId,
        habitQuickCheckLabel: resolvedHabitQuickCheckLabel,
        theme: theme,
      );
      final datedSignature =
          '$day|$offset|${locale.name}|$first|$habitActiveCount|$signature';
      if (!force && datedSignature == _lastPushSignature && !_refreshPending) {
        return true;
      }
      try {
        // A reader must never treat a partially written snapshot as today's data.
        _refreshPending = true;
        _lastPushSignature = '';
        final payload = <String, Object>{
          'widget_account_nonce': _accountActionNonce ?? '',
          'widget_locale': locale.name,
          'widget_first_day_of_week': first,
          'todo_count': todoCount,
          'habit_percent': habitPercent.clamp(0, 100),
          'habit_active_count': habitActiveCount,
          'pomodoro_today': pomodoroToday,
          'focus_minutes_today': focusMinutesToday,
          'brand_app_title': strings.appTitle,
          'nav_todo': strings.navTodo,
          'nav_habit': strings.navHabit,
          'nav_calendar': strings.navCalendar,
          'nav_focus': strings.navFocus,
          'todo_top3_count': todoCount,
          'todo_top3_1': todoTop3.isNotEmpty
              ? '· ${todoTop3[0]}'
              : I18n.tr('widget.todo_top3_empty'),
          'todo_top3_1_id': todoTop3Ids.isNotEmpty ? todoTop3Ids[0] : '',
          'todo_top3_2': todoTop3.length > 1 ? '· ${todoTop3[1]}' : '',
          'todo_top3_2_id': todoTop3Ids.length > 1 ? todoTop3Ids[1] : '',
          'todo_top3_3': todoTop3.length > 2 ? '· ${todoTop3[2]}' : '',
          'todo_top3_3_id': todoTop3Ids.length > 2 ? todoTop3Ids[2] : '',
          'goal_highlight_1': goalHighlights.isNotEmpty
              ? '· ${goalHighlights[0]}'
              : I18n.tr('widget.goal_empty'),
          'goal_highlight_1_id': goalHighlightIds.isNotEmpty
              ? goalHighlightIds[0]
              : '',
          'goal_highlight_2': goalHighlights.length > 1
              ? '· ${goalHighlights[1]}'
              : '',
          'goal_highlight_2_id': goalHighlightIds.length > 1
              ? goalHighlightIds[1]
              : '',
          'goal_highlight_3': goalHighlights.length > 2
              ? '· ${goalHighlights[2]}'
              : '',
          'goal_highlight_3_id': goalHighlightIds.length > 2
              ? goalHighlightIds[2]
              : '',
          'anniversary_highlight_1': anniversaryHighlights.isNotEmpty
              ? '· ${anniversaryHighlights[0]}'
              : I18n.tr('widget.anniversary_empty'),
          'anniversary_highlight_1_id': anniversaryHighlightIds.isNotEmpty
              ? anniversaryHighlightIds[0]
              : '',
          'anniversary_highlight_2': anniversaryHighlights.length > 1
              ? '· ${anniversaryHighlights[1]}'
              : '',
          'anniversary_highlight_2_id': anniversaryHighlightIds.length > 1
              ? anniversaryHighlightIds[1]
              : '',
          'course_highlight_1': courseHighlights.isNotEmpty
              ? '· ${courseHighlights[0]}'
              : I18n.tr('widget.course_empty'),
          'course_highlight_1_id': courseHighlightIds.isNotEmpty
              ? courseHighlightIds[0]
              : '',
          'course_highlight_2': courseHighlights.length > 1
              ? '· ${courseHighlights[1]}'
              : '',
          'course_highlight_2_id': courseHighlightIds.length > 1
              ? courseHighlightIds[1]
              : '',
          'course_highlight_3': courseHighlights.length > 2
              ? '· ${courseHighlights[2]}'
              : '',
          'course_highlight_3_id': courseHighlightIds.length > 2
              ? courseHighlightIds[2]
              : '',
          'note_highlight_1': noteHighlights.isNotEmpty
              ? '· ${noteHighlights[0]}'
              : I18n.tr('widget.note_empty'),
          'note_highlight_1_id': noteHighlightIds.isNotEmpty
              ? noteHighlightIds[0]
              : '',
          'note_highlight_2': noteHighlights.length > 1
              ? '· ${noteHighlights[1]}'
              : '',
          'note_highlight_2_id': noteHighlightIds.length > 1
              ? noteHighlightIds[1]
              : '',
          'note_highlight_3': noteHighlights.length > 2
              ? '· ${noteHighlights[2]}'
              : '',
          'note_highlight_3_id': noteHighlightIds.length > 2
              ? noteHighlightIds[2]
              : '',
          'memorial_highlight_1': memorialHighlights.isNotEmpty
              ? '· ${memorialHighlights[0]}'
              : I18n.tr('widget.anniversary_empty'),
          'memorial_highlight_1_id': memorialHighlightIds.isNotEmpty
              ? memorialHighlightIds[0]
              : '',
          'memorial_highlight_2': memorialHighlights.length > 1
              ? '· ${memorialHighlights[1]}'
              : '',
          'memorial_highlight_2_id': memorialHighlightIds.length > 1
              ? memorialHighlightIds[1]
              : '',
          'memorial_highlight_3': memorialHighlights.length > 2
              ? '· ${memorialHighlights[2]}'
              : '',
          'memorial_highlight_3_id': memorialHighlightIds.length > 2
              ? memorialHighlightIds[2]
              : '',
          'diary_highlight_1': diaryHighlights.isNotEmpty
              ? '· ${diaryHighlights[0]}'
              : I18n.tr('widget.diary_empty'),
          'diary_highlight_1_id': diaryHighlightIds.isNotEmpty
              ? diaryHighlightIds[0]
              : '',
          'diary_highlight_2': diaryHighlights.length > 1
              ? '· ${diaryHighlights[1]}'
              : '',
          'diary_highlight_2_id': diaryHighlightIds.length > 1
              ? diaryHighlightIds[1]
              : '',
          'diary_highlight_3': diaryHighlights.length > 2
              ? '· ${diaryHighlights[2]}'
              : '',
          'diary_highlight_3_id': diaryHighlightIds.length > 2
              ? diaryHighlightIds[2]
              : '',
          'today_event_summary': resolvedTodayEventSummary,
          'schedule_highlight_1': scheduleHighlights.isNotEmpty
              ? '· ${scheduleHighlights[0]}'
              : '· $resolvedTodayEventSummary',
          'schedule_highlight_1_id': scheduleHighlightIds.isNotEmpty
              ? scheduleHighlightIds[0]
              : '',
          'schedule_highlight_2': scheduleHighlights.length > 1
              ? '· ${scheduleHighlights[1]}'
              : '',
          'schedule_highlight_2_id': scheduleHighlightIds.length > 1
              ? scheduleHighlightIds[1]
              : '',
          'schedule_highlight_3': scheduleHighlights.length > 2
              ? '· ${scheduleHighlights[2]}'
              : '',
          'schedule_highlight_3_id': scheduleHighlightIds.length > 2
              ? scheduleHighlightIds[2]
              : '',
          'calendar_month_summary': resolvedCalendarMonthSummary,
          'focus_summary': resolvedFocusSummary,
          'habit_summary': resolvedHabitSummary,
          'streak_summary': resolvedStreakSummary,
          'next_focus_label': resolvedNextFocusLabel,
          'focus_timer_count_up': focusTimerCountUp,
          'focus_timer_started_at_millis': focusTimerStartedAtMillis,
          'focus_timer_running': focusTimerRunning,
          'focus_timer_remaining_seconds': focusTimerRemainingSeconds,
          'focus_timer_total_seconds': focusTimerTotalSeconds,
          'focus_timer_ends_at_millis': focusTimerEndsAtMillis,
          'focus_timer_label': resolvedFocusTimerLabel,
          'habit_quick_check_id': habitQuickCheckId,
          'habit_quick_check_label': resolvedHabitQuickCheckLabel,
          ...theme.payloadValues,
        };
        if (nativeWriter != null) {
          _clearOptimisticBgIdsOnNextRefresh = true;
          try {
            final ok = await nativeWriter(payload, now);
            if (ok && isCurrent()) {
              if (_clearOptimisticBgIdsOnNextRefresh) {
                _clearOptimisticBgIdsOnNextRefresh = false;
                await _clearPendingBgState();
              }
              _refreshPending = false;
              _lastPushSignature = datedSignature;
              _lastThemeSignature = theme.signature;
              return true;
            }
            return false;
          } finally {
            _clearOptimisticBgIdsOnNextRefresh = false;
          }
        }
        if (!isCurrent()) return false;
        if (!await _saveWidgetPayloadValue('widget_snapshot_day', '')) {
          return false;
        }
        if (!isCurrent()) return false;
        final saveResult = await _saveWidgetPayload(payload);
        if (!saveResult.ok || !isCurrent()) {
          return false;
        }
        if (!await _saveWidgetPayloadValue(
          'widget_snapshot_utc_offset_minutes',
          offset,
        )) {
          return false;
        }
        if (!isCurrent()) {
          return false;
        }
        final current = DateTime.now();
        if (current.year != now.year ||
            current.month != now.month ||
            current.day != now.day ||
            current.timeZoneOffset != now.timeZoneOffset) {
          return false;
        }
        if (!await _saveWidgetPayloadValue('widget_snapshot_day', day)) {
          return false;
        }
        if (!isCurrent()) {
          return false;
        }
        await _clearPendingBgState();
        _refreshPending = true;
        final ok = await _updateAllWidgets(isCurrent: isCurrent);
        if (!isCurrent()) {
          return false;
        }
        if (ok) {
          _refreshPending = false;
          _lastPushSignature = datedSignature;
          _lastThemeSignature = theme.signature;
        }
        return ok;
      } catch (e, st) {
        debugPrint('[HomeWidget] push failed: $e\n$st');
        return false;
      }
    });
  }

  static Future<bool> _updateAllWidgets({bool Function()? isCurrent}) async {
    if (!(isCurrent?.call() ?? true)) return false;
    if (_clearOptimisticBgIdsOnNextRefresh) {
      _clearOptimisticBgIdsOnNextRefresh = false;
      await _clearPendingBgState();
      if (!(isCurrent?.call() ?? true)) return false;
    }
    if (PlatformInfo.isAndroid) {
      final updated = await AndroidWidgetManager.refreshAllWidgets();
      if (updated == null) {
        debugPrint('[HomeWidget] Android refreshAllWidgets failed');
        return false;
      }
      if (updated == 0) {
        debugPrint('[HomeWidget] Android refreshAllWidgets updated 0 widgets');
      }
      return true;
    }
    // WidgetKit exposes several independent families. Keep a small bounded
    // fan-out so a refresh does not wait for ten sequential platform calls,
    // while avoiding an unbounded burst on older devices.
    const maxConcurrentUpdates = 3;
    var nextIndex = 0;
    var ok = true;
    Future<void> worker() async {
      while (true) {
        if (!(isCurrent?.call() ?? true)) return;
        final index = nextIndex++;
        if (index >= _widgetUpdateTargets.length) return;
        final target = _widgetUpdateTargets[index];
        final updated = await _updateWidgetFamily(
          androidName: target.androidName,
          iOSName: target.iOSName,
        );
        ok = updated && ok;
      }
    }

    final workerCount = maxConcurrentUpdates < _widgetUpdateTargets.length
        ? maxConcurrentUpdates
        : _widgetUpdateTargets.length;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    if (!ok) {
      debugPrint('[HomeWidget] one or more widget providers failed to update');
    }
    return ok && (isCurrent?.call() ?? true);
  }

  static Future<bool> _updateWidgetFamily({
    required String androidName,
    required String iOSName,
  }) async {
    var ok = true;
    Future<void> updateOne(String name, {String? ios}) async {
      try {
        await HomeWidget.updateWidget(
          name: name,
          androidName: name,
          iOSName: ios,
        );
      } catch (e, st) {
        ok = false;
        debugPrint('[HomeWidget] updateWidget($name) failed: $e\n$st');
      }
    }

    await updateOne(androidName, ios: iOSName);
    return ok;
  }

  static Stream<Uri?> get widgetClickedStream {
    if (!_supported) return const Stream.empty();
    if (PlatformInfo.isAndroid || PlatformInfo.isIOS) {
      return WidgetLaunchService.instance.links;
    }
    return HomeWidget.widgetClicked;
  }

  static Future<Uri?> initialLaunchUri() async {
    if (!_supported) return null;
    // Native cold and hot launches drain from one queue. Reading a plugin's
    // initial launch later can replay the latest tap or collapse early taps.
    if (PlatformInfo.isAndroid || PlatformInfo.isIOS) return null;
    return HomeWidget.initiallyLaunchedFromHomeWidget();
  }

  static Future<void> acknowledgeLaunch(Uri uri) async {
    if (PlatformInfo.isAndroid || PlatformInfo.isIOS) {
      await WidgetLaunchService.instance.acknowledge(uri);
    }
  }

  static bool isReceivedLaunch(Uri uri) =>
      (PlatformInfo.isAndroid || PlatformInfo.isIOS) &&
      WidgetLaunchService.instance.ownsDelivery(uri);

  /// Reads and clears any pending Android background widget action URIs
  /// (`duoyi_widget_pending_bg_actions`) and resets optimistic background
  /// completion/check-in ID sets. No-op outside Android.
  static Future<List<Uri>> drainPendingBgActions() async {
    if (!_isAndroid) return const <Uri>[];
    try {
      final raw = await HomeWidget.getWidgetData<String>(_pendingBgActionsKey);
      if (raw == null || raw.trim().isEmpty) {
        if (raw != null) {
          await _clearPendingBgState(includeActionQueue: true);
        }
        return const <Uri>[];
      }
      final actions = <Uri>[];
      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final uri = Uri.tryParse(trimmed);
        if (uri != null && uri.scheme == 'duoyi' && uri.hasAuthority) {
          actions.add(uri);
        }
      }
      await _clearPendingBgState(includeActionQueue: true);
      return actions;
    } catch (e, st) {
      debugPrint('[HomeWidget] drainPendingBgActions failed: $e\n$st');
      return const <Uri>[];
    }
  }

  static Future<void> _clearPendingBgState({
    bool includeActionQueue = false,
  }) async {
    if (!_isAndroid) return;
    try {
      final keys = <String>[
        if (includeActionQueue) _pendingBgActionsKey,
        _todoCompletedBgIdsKey,
        _habitCheckedBgIdsKey,
      ];
      await Future.wait(
        keys.map((key) => HomeWidget.saveWidgetData<String>(key, null)),
      );
    } catch (e, st) {
      debugPrint('[HomeWidget] clear pending bg state failed: $e\n$st');
    }
  }

  static String _pushSignature({
    required int todoCount,
    required int habitPercent,
    required int pomodoroToday,
    required int focusMinutesToday,
    required BrandStrings strings,
    required List<String> todoTop3,
    required List<String> todoTop3Ids,
    required List<String> goalHighlights,
    required List<String> goalHighlightIds,
    required List<String> anniversaryHighlights,
    required List<String> anniversaryHighlightIds,
    required List<String> courseHighlights,
    required List<String> courseHighlightIds,
    required List<String> noteHighlights,
    required List<String> noteHighlightIds,
    required List<String> memorialHighlights,
    required List<String> memorialHighlightIds,
    required List<String> diaryHighlights,
    required List<String> diaryHighlightIds,
    required List<String> scheduleHighlights,
    required List<String> scheduleHighlightIds,
    required String todayEventSummary,
    required String focusSummary,
    required String habitSummary,
    required String streakSummary,
    required String nextFocusLabel,
    required String calendarMonthSummary,
    required bool focusTimerCountUp,
    required int focusTimerStartedAtMillis,
    required bool focusTimerRunning,
    required int focusTimerRemainingSeconds,
    required int focusTimerTotalSeconds,
    required int focusTimerEndsAtMillis,
    required String focusTimerLabel,
    required String habitQuickCheckId,
    required String habitQuickCheckLabel,
    required HomeWidgetThemePayload theme,
  }) {
    return [
      todoCount,
      habitPercent,
      pomodoroToday,
      focusMinutesToday,
      strings.appTitle,
      strings.navTodo,
      strings.navHabit,
      strings.navCalendar,
      strings.navFocus,
      _listSignature(todoTop3),
      _listSignature(todoTop3Ids),
      _listSignature(goalHighlights),
      _listSignature(goalHighlightIds),
      _listSignature(anniversaryHighlights),
      _listSignature(anniversaryHighlightIds),
      _listSignature(courseHighlights),
      _listSignature(courseHighlightIds),
      _listSignature(noteHighlights),
      _listSignature(noteHighlightIds),
      _listSignature(memorialHighlights),
      _listSignature(memorialHighlightIds),
      _listSignature(diaryHighlights),
      _listSignature(diaryHighlightIds),
      _listSignature(scheduleHighlights),
      _listSignature(scheduleHighlightIds),
      todayEventSummary,
      focusSummary,
      habitSummary,
      streakSummary,
      nextFocusLabel,
      calendarMonthSummary,
      focusTimerCountUp,
      focusTimerStartedAtMillis,
      focusTimerRunning,
      focusTimerRemainingSeconds,
      focusTimerTotalSeconds,
      focusTimerEndsAtMillis,
      focusTimerLabel,
      habitQuickCheckId,
      habitQuickCheckLabel,
      theme.signature,
    ].map(_signaturePart).join('|');
  }

  static String _listSignature(List<String> values) {
    return values.map(_signaturePart).join(',');
  }

  static String _signaturePart(Object? value) {
    final text = value?.toString() ?? '';
    return '${text.length}:$text';
  }
}

class _HomeWidgetPayloadSaveResult {
  final bool ok;
  final bool changed;

  const _HomeWidgetPayloadSaveResult({required this.ok, required this.changed});
}

class HomeWidgetThemePayload {
  final String brandId;
  final String cardSkinId;
  final bool dark;
  final Color primary;
  final Color background;
  final Color surface;
  final Color navBackground;
  final Color border;
  final Color text;
  final Color mutedText;
  final Color onPrimary;
  final Color accentStart;
  final Color accentEnd;
  final String backgroundAssetKey;
  final int cornerRadiusDp;
  final int controlRadiusDp;
  final int borderWidthDp;

  const HomeWidgetThemePayload({
    required this.brandId,
    required this.cardSkinId,
    required this.dark,
    required this.primary,
    required this.background,
    required this.surface,
    required this.navBackground,
    required this.border,
    required this.text,
    required this.mutedText,
    required this.onPrimary,
    required this.accentStart,
    required this.accentEnd,
    required this.backgroundAssetKey,
    required this.cornerRadiusDp,
    required this.controlRadiusDp,
    required this.borderWidthDp,
  });

  factory HomeWidgetThemePayload.fromThemeProvider(
    ThemeProvider provider, {
    bool? darkOverride,
  }) {
    final brand = provider.activeWidgetBackgroundBrand;
    final cardSkin = provider.activeWidgetCardSkin;
    final isBrandDark = brand.theme.brightness == Brightness.dark;
    if (darkOverride == true &&
        (!isBrandDark ||
            brand.id == AppBrands.defaultBrand.id ||
            brand.id == AppBrands.liquidGlass.id)) {
      return HomeWidgetThemePayload.darkVariantFor(brand, cardSkin);
    }
    if (darkOverride == false && isBrandDark) {
      return HomeWidgetThemePayload._lightVariantFor(brand, cardSkin);
    }
    return HomeWidgetThemePayload._fromBrandAndSkin(
      brand,
      cardSkin,
      dark: darkOverride ?? isBrandDark,
    );
  }

  /// Dark Mode widget theme palette for light-first themes (`defaultBrand` &
  /// `liquidGlass`) and fallback dark preview for any light brand.
  factory HomeWidgetThemePayload.darkVariantFor(
    AppBrand brand,
    CardSkinReward skin,
  ) {
    final usesCardSkin = skin.id != ThemeProvider.defaultCardSkinId;
    final cornerRadiusDp = _cornerRadiusForSkin(
      skin.id,
      defaultOrGlass:
          (brand.id == AppBrands.defaultBrand.id ||
              brand.id == AppBrands.liquidGlass.id) &&
          !usesCardSkin,
    );
    final controlRadiusDp =
        !usesCardSkin &&
            (brand.id == AppBrands.defaultBrand.id ||
                brand.id == AppBrands.liquidGlass.id)
        ? 12
        : 8;
    if (brand.id == AppBrands.liquidGlass.id) {
      return HomeWidgetThemePayload(
        brandId: brand.id,
        cardSkinId: skin.id,
        dark: true,
        primary: const Color(0xFF0A84FF),
        background: const Color(0xE6161B24),
        surface: const Color(0xD91F2633),
        navBackground: const Color(0xCC283142),
        border: const Color(0xFF3A465C),
        text: const Color(0xFFF5F8FC),
        mutedText: const Color(0xFFB0BCD0),
        onPrimary: const Color(0xFFFFFFFF),
        accentStart: usesCardSkin
            ? skin.colors.first
            : const Color(0xFF0A84FF),
        accentEnd: usesCardSkin ? skin.colors.last : const Color(0xFF5AC8FA),
        backgroundAssetKey: _backgroundAssetKey(brand.backgroundAsset),
        cornerRadiusDp: cornerRadiusDp,
        controlRadiusDp: controlRadiusDp,
        borderWidthDp: 1,
      );
    }
    if (brand.id == AppBrands.defaultBrand.id ||
        brand.theme.brightness == Brightness.light) {
      final cs = brand.theme.colorScheme;
      final isDefault = brand.id == AppBrands.defaultBrand.id;
      const baseBg = Color(0xFF14171F);
      const baseSurface = Color(0xFF1C212B);
      const baseNav = Color(0xFF242A36);
      const baseBorder = Color(0xFF2F3847);
      final primary = isDefault ? const Color(0xFF0A84FF) : cs.primary;
      return HomeWidgetThemePayload(
        brandId: brand.id,
        cardSkinId: skin.id,
        dark: true,
        primary: primary,
        background: isDefault
            ? baseBg
            : Color.alphaBlend(primary.withValues(alpha: 0.12), baseBg),
        surface: isDefault
            ? baseSurface
            : Color.alphaBlend(primary.withValues(alpha: 0.10), baseSurface),
        navBackground: isDefault
            ? baseNav
            : Color.alphaBlend(primary.withValues(alpha: 0.14), baseNav),
        border: baseBorder,
        text: const Color(0xFFF2F5FA),
        mutedText: const Color(0xFFA5B0C2),
        onPrimary: isDefault ? const Color(0xFFFFFFFF) : cs.onPrimary,
        accentStart: usesCardSkin
            ? skin.colors.first
            : (isDefault ? const Color(0xFF0A84FF) : cs.primary),
        accentEnd: usesCardSkin
            ? skin.colors.last
            : (isDefault ? const Color(0xFF409CFF) : cs.secondary),
        backgroundAssetKey: _backgroundAssetKey(brand.backgroundAsset),
        cornerRadiusDp: cornerRadiusDp,
        controlRadiusDp: controlRadiusDp,
        borderWidthDp: 1,
      );
    }
    return HomeWidgetThemePayload._fromBrandAndSkin(brand, skin, dark: true);
  }

  factory HomeWidgetThemePayload._lightVariantFor(
    AppBrand brand,
    CardSkinReward skin,
  ) {
    final cs = brand.theme.colorScheme;
    final usesCardSkin = skin.id != ThemeProvider.defaultCardSkinId;
    final accentStart = usesCardSkin ? skin.colors.first : cs.primary;
    final accentEnd = usesCardSkin ? skin.colors.last : cs.secondary;
    final cornerRadiusDp = _cornerRadiusForSkin(skin.id, defaultOrGlass: false);
    const lightBase = DesignTokens.defaultPageBackground;
    final primaryTint = cs.primary.computeLuminance() > 0.45
        ? const Color(0xFF0066D6)
        : cs.primary;
    return HomeWidgetThemePayload(
      brandId: brand.id,
      cardSkinId: skin.id,
      dark: false,
      primary: primaryTint,
      background: Color.alphaBlend(primaryTint.withValues(alpha: 0.06), lightBase),
      surface: DesignTokens.defaultSurface,
      navBackground: Color.alphaBlend(
        primaryTint.withValues(alpha: 0.08),
        DesignTokens.defaultSurfaceMuted,
      ),
      border: Color.alphaBlend(
        accentStart.withValues(alpha: usesCardSkin ? 0.34 : 0.20),
        const Color(0xFFD0D5DD),
      ),
      text: DesignTokens.defaultText,
      mutedText: DesignTokens.defaultTextMuted,
      onPrimary: const Color(0xFFFFFFFF),
      accentStart: accentStart,
      accentEnd: accentEnd,
      backgroundAssetKey: _backgroundAssetKey(brand.backgroundAsset),
      cornerRadiusDp: cornerRadiusDp,
      controlRadiusDp: 8,
      borderWidthDp: usesCardSkin ? 1 : 0,
    );
  }

  static int _cornerRadiusForSkin(
    String cardSkinId, {
    required bool defaultOrGlass,
  }) {
    return switch (cardSkinId) {
      'paper_card' => 14,
      'mint_card' => 15,
      'starlight_card' => 16,
      _ => defaultOrGlass ? 16 : 13,
    };
  }

  factory HomeWidgetThemePayload._fromBrandAndSkin(
    AppBrand brand,
    CardSkinReward cardSkin, {
    required bool dark,
  }) {
    final theme = brand.theme;
    final cs = theme.colorScheme;
    final usesCardSkin = cardSkin.id != ThemeProvider.defaultCardSkinId;
    final defaultIosStyle =
        brand.id == AppBrands.defaultBrand.id && !usesCardSkin;
    final glassStyle = brand.id == AppBrands.liquidGlass.id && !usesCardSkin;
    // Native widget hosts cannot reproduce the app's backdrop. Publish opaque
    // glass surfaces composed on the brand's known base instead of wallpaper.
    final glassBase = Color.alphaBlend(
      brand.backgroundOverlay,
      const Color(0xFFFFFFFF),
    );
    final imageBacked = brand.backgroundAsset != null;
    final accentStart = usesCardSkin ? cardSkin.colors.first : cs.primary;
    final accentEnd = defaultIosStyle
        ? const Color(0xFF3898FF)
        : (usesCardSkin ? cardSkin.colors.last : cs.secondary);
    final baseBackground = defaultIosStyle
        ? DesignTokens.defaultPageBackground
        : Color.alphaBlend(
            brand.backgroundOverlay.withValues(
              alpha: imageBacked
                  ? brand.backgroundOverlayOpacity.clamp(0.56, 0.82).toDouble()
                  : brand.backgroundOverlayOpacity,
            ),
            dark ? const Color(0xFF0B0F17) : const Color(0xFFFFFFFF),
          );
    final background = defaultIosStyle
        ? DesignTokens.defaultPageBackground
        : glassStyle
        ? Color.alphaBlend(
            AppSurfaceStyle.liquidGlass.cardFillColor!,
            glassBase,
          )
        : Color.alphaBlend(
            accentEnd.withValues(
              alpha: imageBacked ? (dark ? 0.22 : 0.14) : 0.08,
            ),
            Color.alphaBlend(
              accentStart.withValues(alpha: dark ? 0.22 : 0.12),
              baseBackground,
            ),
          );
    final surface = defaultIosStyle
        ? DesignTokens.defaultSurface
        : glassStyle
        ? Color.alphaBlend(
            const Color(
              0xFFFFFFFF,
            ).withValues(alpha: DesignTokens.navBarIosBackgroundAlpha),
            glassBase,
          )
        : Color.alphaBlend(
            accentEnd.withValues(
              alpha: usesCardSkin
                  ? (dark ? 0.24 : 0.16)
                  : imageBacked
                  ? (dark ? 0.16 : 0.09)
                  : 0.06,
            ),
            Color.alphaBlend(
              brand.backgroundOverlay.withValues(
                alpha: imageBacked ? 0.18 : 0.0,
              ),
              cs.surface,
            ),
          );
    final navBackground = defaultIosStyle
        ? DesignTokens.defaultSurfaceMuted
        : glassStyle
        ? Color.alphaBlend(
            const Color(0xFFFFFFFF).withValues(alpha: 0.28),
            glassBase,
          )
        : Color.alphaBlend(
            cs.primary.withValues(
              alpha: imageBacked ? (dark ? 0.24 : 0.12) : 0.10,
            ),
            surface,
          );
    final border = defaultIosStyle
        ? const Color(0x000066D6)
        : glassStyle
        ? const Color(
            0xFFFFFFFF,
          ).withValues(alpha: DesignTokens.glassHighlightAlpha)
        : Color.alphaBlend(
            accentStart.withValues(
              alpha: usesCardSkin ? (dark ? 0.50 : 0.34) : 0.18,
            ),
            cs.outlineVariant,
          );
    final cornerRadiusDp = _cornerRadiusForSkin(
      cardSkin.id,
      defaultOrGlass: defaultIosStyle || glassStyle,
    );
    return HomeWidgetThemePayload(
      brandId: brand.id,
      cardSkinId: cardSkin.id,
      dark: dark,
      primary: cs.primary,
      background: background,
      surface: surface,
      navBackground: navBackground,
      border: border,
      text: cs.onSurface,
      mutedText: defaultIosStyle
          ? DesignTokens.defaultTextMuted
          : cs.onSurfaceVariant,
      onPrimary: cs.onPrimary,
      accentStart: accentStart,
      accentEnd: accentEnd,
      backgroundAssetKey: _backgroundAssetKey(brand.backgroundAsset),
      cornerRadiusDp: cornerRadiusDp,
      controlRadiusDp: defaultIosStyle || glassStyle ? 12 : 8,
      // Publication v1 uses integer dp: retain a 1dp static highlight rather
      // than rounding the app's 0.55px border down to zero.
      borderWidthDp: usesCardSkin || glassStyle ? 1 : 0,
    );
  }

  Map<String, Object> get payloadValues => {
    'widget_theme_brand_id': brandId,
    'widget_theme_card_skin_id': cardSkinId,
    'widget_theme_dark': dark,
    'widget_theme_primary': _hex(primary),
    'widget_theme_background': _hex(background),
    'widget_theme_surface': _hex(surface),
    'widget_theme_nav_background': _hex(navBackground),
    'widget_theme_border': _hex(border),
    'widget_theme_text': _hex(text),
    'widget_theme_muted_text': _hex(mutedText),
    'widget_theme_on_primary': _hex(onPrimary),
    'widget_theme_accent_start': _hex(accentStart),
    'widget_theme_accent_end': _hex(accentEnd),
    'widget_theme_background_asset_key': backgroundAssetKey,
    'widget_theme_corner_radius_dp': cornerRadiusDp,
    'widget_theme_control_radius_dp': controlRadiusDp,
    'widget_theme_border_width_dp': borderWidthDp,
  };

  List<Future<bool>> saveOperations() => payloadValues.entries
      .map(
        (entry) =>
            HomeWidgetService._saveWidgetPayloadValue(entry.key, entry.value),
      )
      .toList();

  String get signature {
    return [
      brandId,
      cardSkinId,
      dark,
      _hex(primary),
      _hex(background),
      _hex(surface),
      _hex(navBackground),
      _hex(border),
      _hex(text),
      _hex(mutedText),
      _hex(onPrimary),
      _hex(accentStart),
      _hex(accentEnd),
      backgroundAssetKey,
      cornerRadiusDp,
      controlRadiusDp,
      borderWidthDp,
    ].map(HomeWidgetService._signaturePart).join('|');
  }

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  static String _backgroundAssetKey(String? asset) {
    return switch (asset) {
      'assets/backgrounds/re0.png' => 're0',
      'assets/backgrounds/genshin.png' => 'genshin',
      'assets/backgrounds/star_rail.png' => 'star_rail',
      'assets/backgrounds/wuthering.png' => 'wuthering',
      'assets/backgrounds/zzz.png' => 'zzz',
      'assets/backgrounds/yanyun.png' => 'yanyun',
      'assets/backgrounds/botw.png' => 'botw',
      _ => '',
    };
  }
}

class _HomeWidgetUpdateTarget {
  final String androidName;
  final String iOSName;

  const _HomeWidgetUpdateTarget({
    required this.androidName,
    required this.iOSName,
  });
}

const List<_HomeWidgetUpdateTarget> _widgetUpdateTargets = [
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidTodoProviderName,
    iOSName: HomeWidgetService._iosTodoWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidFocusProviderName,
    iOSName: HomeWidgetService._iosFocusWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidHabitProviderName,
    iOSName: HomeWidgetService._iosHabitWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidCalendarProviderName,
    iOSName: HomeWidgetService._iosCalendarWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidScheduleProviderName,
    iOSName: HomeWidgetService._iosScheduleWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidGoalProviderName,
    iOSName: HomeWidgetService._iosGoalWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidCourseProviderName,
    iOSName: HomeWidgetService._iosCourseWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidNoteProviderName,
    iOSName: HomeWidgetService._iosNoteWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidAnniversaryProviderName,
    iOSName: HomeWidgetService._iosAnniversaryWidgetName,
  ),
  _HomeWidgetUpdateTarget(
    androidName: HomeWidgetService._androidDiaryProviderName,
    iOSName: HomeWidgetService._iosDiaryWidgetName,
  ),
];
