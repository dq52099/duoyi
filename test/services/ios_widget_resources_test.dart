import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('iOS WidgetKit resources', () {
    final swift = File(
      'ios/DuoyiWidgets/DuoyiWidgets.swift',
    ).readAsStringSync();
    final infoPlist = File('ios/DuoyiWidgets/Info.plist').readAsStringSync();
    final runnerInfoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final sceneDelegate = File(
      'ios/Runner/SceneDelegate.swift',
    ).readAsStringSync();
    final entitlements = File(
      'ios/DuoyiWidgets/DuoyiWidgets.entitlements',
    ).readAsStringSync();
    final runnerEntitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final service = File(
      'lib/services/home_widget_service.dart',
    ).readAsStringSync();

    const widgetKinds = [
      'DuoyiTodoWidget',
      'DuoyiFocusWidget',
      'DuoyiHabitWidget',
      'DuoyiCalendarWidget',
      'DuoyiScheduleWidget',
      'DuoyiGoalWidget',
      'DuoyiCourseWidget',
      'DuoyiNoteWidget',
      'DuoyiAnniversaryWidget',
      'DuoyiDiaryWidget',
    ];

    test('declares 10 visible independent WidgetKit kinds', () {
      final declaredKinds = RegExp(
        r'kind: "([^"]+)"',
      ).allMatches(swift).map((match) => match.group(1)!).toSet();
      final bundledConfigs = RegExp(
        r'DuoyiAnyWidget\(config: ([^)]+)\)',
      ).allMatches(swift).map((match) => match.group(1)!).toList();

      expect(declaredKinds, containsAll(widgetKinds));
      expect(declaredKinds, hasLength(widgetKinds.length));
      expect(bundledConfigs, containsAll(widgetKinds.map(_configName)));
      expect(bundledConfigs, hasLength(widgetKinds.length));

      for (final kind in widgetKinds) {
        final configBlock = _swiftConfigBlock(swift, _configName(kind));
        expect(configBlock, contains('kind: "$kind"'));
        expect(swift, contains('DuoyiAnyWidget(config: ${_configName(kind)})'));
        expect(
          service,
          contains("static const String _ios${_serviceName(kind)} = '$kind';"),
        );
        expect(
          service,
          contains('iOSName: HomeWidgetService._ios${_serviceName(kind)}'),
        );
      }

      expect(swift, isNot(contains('Overview')));
      expect(swift, isNot(contains('overview')));
      expect(swift, isNot(contains('Combo')));
      expect(swift, isNot(contains('combo')));
      expect(service, isNot(contains('DuoyiOverviewWidget')));
      expect(service, isNot(contains('DuoyiComboWidget')));
      expect(service, isNot(contains('DuoyiWidgetKind.overview')));
      expect(service, isNot(contains('DuoyiWidgetKind.combo')));
    });

    test('shares the same app group and WidgetKit extension point', () {
      expect(
        swift,
        contains('private let appGroupId = "group.com.duoyi.duoyi"'),
      );
      expect(
        service,
        contains("static const String _appGroupId = 'group.com.duoyi.duoyi';"),
      );
      expect(entitlements, contains('group.com.duoyi.duoyi'));
      expect(runnerEntitlements, contains('group.com.duoyi.duoyi'));
      expect(infoPlist, contains('com.apple.widgetkit-extension'));
      expect(infoPlist, contains('CFBundleShortVersionString'));
      expect(infoPlist, contains('CFBundleVersion'));
      expect(runnerInfoPlist, contains('com.duoyi.duoyi.deep-links'));
      expect(runnerInfoPlist, contains('<string>duoyi</string>'));
    });

    test('Xcode project embeds the WidgetKit extension target', () {
      expect(project, contains('DuoyiWidgets.appex'));
      expect(
        project,
        matches(
          RegExp(
            r'/\* DuoyiWidgets \*/ = \{\s*'
            r'isa = PBXNativeTarget;[\s\S]*?'
            r'name = DuoyiWidgets;[\s\S]*?'
            r'productName = DuoyiWidgets;[\s\S]*?'
            r'productReference = [^;]+ /\* DuoyiWidgets\.appex \*/;[\s\S]*?'
            r'productType = "com\.apple\.product-type\.app-extension";',
          ),
        ),
      );
      expect(project, contains('Embed App Extensions'));
      expect(project, contains('DuoyiWidgets.swift in Sources'));
      expect(project, contains('path = DuoyiWidgets.swift;'));
      expect(project, contains('path = DuoyiWidgets.entitlements;'));
      expect(project, contains('path = DuoyiWidgets.appex;'));
      expect(project, contains('path = DuoyiWidgets;'));
      expect(project, matches(RegExp(r'target = [^;]+ /\* DuoyiWidgets \*/;')));
      expect(
        project,
        contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'),
      );
      expect(
        project,
        contains(
          'CODE_SIGN_ENTITLEMENTS = DuoyiWidgets/DuoyiWidgets.entitlements;',
        ),
      );
      expect(
        project,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.duoyi.duoyi.DuoyiWidgets;'),
      );
      for (final config in {
        'E0000000000000000000000C': 'Debug',
        'E0000000000000000000000D': 'Release',
        'E0000000000000000000000E': 'Profile',
      }.entries) {
        final start = project.indexOf(
          '${config.key} /* ${config.value} */ = {',
        );
        expect(start, greaterThanOrEqualTo(0));
        final block = project.substring(
          start,
          project.indexOf('\n\t\t};', start),
        );
        expect(
          block,
          contains(
            'baseConfigurationReference = 9740EEB31CF90195004384FC /* Generated.xcconfig */;',
          ),
        );
        expect(
          block,
          contains(r'CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";'),
        );
        expect(
          block,
          contains(r'MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)";'),
        );
        expect(block, isNot(contains('110011')));
        expect(block, isNot(contains('1.1.11')));
      }
      final evidenceScript = File(
        'scripts/ios_device_evidence.sh',
      ).readAsStringSync();
      final refresh = evidenceScript.indexOf(
        'build ios --config-only --no-codesign --debug --no-pub',
      );
      final signedBuild = evidenceScript.indexOf('xcodebuild \\');
      expect(refresh, greaterThanOrEqualTo(0));
      expect(signedBuild, greaterThan(refresh));
      expect(evidenceScript, contains('generated_build_version.txt'));
      expect(project, contains('APPLICATION_EXTENSION_API_ONLY = YES;'));
      expect(project, contains('INFOPLIST_FILE = DuoyiWidgets/Info.plist;'));
    });

    test('uses the same payload keys written by HomeWidgetService', () {
      const sharedKeys = [
        'todo_top3_1',
        'todo_top3_2',
        'todo_top3_3',
        'next_focus_label',
        'focus_summary',
        'focus_timer_running',
        'focus_timer_remaining_seconds',
        'focus_timer_total_seconds',
        'focus_timer_ends_at_millis',
        'focus_timer_label',
        'streak_summary',
        'habit_summary',
        'habit_quick_check_label',
        'habit_quick_check_id',
        'calendar_month_summary',
        'today_event_summary',
        'schedule_highlight_1',
        'schedule_highlight_2',
        'schedule_highlight_3',
        'goal_highlight_1',
        'goal_highlight_2',
        'goal_highlight_3',
        'course_highlight_1',
        'course_highlight_2',
        'note_highlight_1',
        'note_highlight_2',
        'note_highlight_3',
        'anniversary_highlight_1',
        'anniversary_highlight_2',
        'memorial_highlight_1',
        'memorial_highlight_2',
        'memorial_highlight_3',
        'diary_highlight_1',
        'diary_highlight_2',
        'diary_highlight_3',
        'widget_display_mode',
        'brand_app_title',
        'nav_todo',
        'nav_habit',
        'nav_calendar',
        'nav_focus',
      ];

      for (final key in sharedKeys) {
        expect(swift, contains('"$key"'));
        expect(service, contains("'$key'"));
      }
      const configKeys = {
        'todoConfig': ['todo_top3_1', 'todo_top3_2', 'todo_top3_3'],
        'focusConfig': ['next_focus_label', 'focus_summary', 'streak_summary'],
        'habitConfig': [
          'habit_summary',
          'habit_quick_check_label',
          'streak_summary',
        ],
        'calendarConfig': [
          'calendar_month_summary',
          'today_event_summary',
          'schedule_highlight_2',
        ],
        'scheduleConfig': [
          'today_event_summary',
          'schedule_highlight_1',
          'schedule_highlight_2',
          'schedule_highlight_3',
        ],
        'goalConfig': [
          'goal_highlight_1',
          'goal_highlight_2',
          'goal_highlight_3',
        ],
        'courseConfig': [
          'course_highlight_1',
          'course_highlight_2',
          'today_event_summary',
        ],
        'noteConfig': [
          'note_highlight_1',
          'note_highlight_2',
          'note_highlight_3',
        ],
        'anniversaryConfig': [
          'anniversary_highlight_1',
          'anniversary_highlight_2',
          'memorial_highlight_1',
          'memorial_highlight_2',
          'memorial_highlight_3',
        ],
        'diaryConfig': [
          'diary_highlight_1',
          'diary_highlight_2',
          'diary_highlight_3',
        ],
      };
      for (final configEntry in configKeys.entries) {
        final configBlock = _swiftConfigBlock(swift, configEntry.key);
        for (final key in configEntry.value) {
          expect(configBlock, contains('"$key"'));
        }
      }
      expect(swift, contains('todo_top3_\\(index)_id'));
      expect(swift, contains('private struct DuoyiWidgetRow'));
      expect(swift, contains('primaryTarget'));
      expect(swift, contains('readPrimary'));
      expect(swift, contains('config.kind == "DuoyiAnniversaryWidget"'));
      final knownFallback = _swiftFunctionBlock(swift, 'isKnownFallback');
      expect(knownFallback, contains('if trimmed == entry.config.fallback {'));
      expect(swift, contains('key: "memorial_highlight_1", fallback: ""'));
      expect(swift, contains('key: "memorial_highlight_1_id"'));
      expect(swift, contains('sourceKey = "memorial_highlight_1"'));
      expect(swift, contains('readRows'));
      expect(swift, contains('excluding: primarySource.sourceKey'));
      expect(swift, contains('"\\(config.primaryKey)_id"'));
      expect(swift, contains('"\\(key)_id"'));
      expect(swift, contains('linkedText(entry.primary'));
      expect(swift, contains('linkedText(row.title'));
      expect(swift, contains('Link(destination: url)'));
      for (final key in [
        'todo_top3_1_id',
        'todo_top3_2_id',
        'todo_top3_3_id',
        'schedule_highlight_1_id',
        'schedule_highlight_2_id',
        'schedule_highlight_3_id',
        'goal_highlight_1_id',
        'goal_highlight_2_id',
        'goal_highlight_3_id',
        'course_highlight_1_id',
        'course_highlight_2_id',
        'note_highlight_1_id',
        'note_highlight_2_id',
        'note_highlight_3_id',
        'anniversary_highlight_1_id',
        'anniversary_highlight_2_id',
        'memorial_highlight_1_id',
        'memorial_highlight_2_id',
        'memorial_highlight_3_id',
        'diary_highlight_1_id',
        'diary_highlight_2_id',
        'diary_highlight_3_id',
      ]) {
        expect(service, contains("'$key'"));
      }
    });

    test('focus widget renders the shared timer contract', () {
      expect(swift, contains('focusTimerRunning'));
      expect(swift, contains('focusTimerRemainingSeconds'));
      expect(swift, contains('focusTimerTotalSeconds'));
      expect(swift, contains('let endsAtMillis: Int64'));
      expect(swift, contains('focus_timer_count_up'));
      expect(swift, contains('focus_timer_started_at_millis'));
      expect(
        swift,
        contains('var focusTimerRemainingSeconds: Int { focusTimer.seconds }'),
      );
      expect(
        swift,
        contains('var focusTimerEndDate: Date? { focusTimer.endDate }'),
      );
      expect(swift, contains('focusTimerLabel'));
      expect(swift, contains('Text(endDate, style: .timer)'));
      expect(swift, contains('.monospacedDigit()'));
      expect(swift, contains('current.focusTimerRunning ? 1 : 15'));

      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('focusTimerRunning: focusState.isRunning'));
      expect(
        main,
        contains('focusTimerRemainingSeconds: focusState.remainingSeconds'),
      );
      expect(main, contains('focusTimerTotalSeconds: focusState.totalSeconds'));
      expect(main, contains('focusTimerEndsAtMillis: focusTimerEndsAtMillis'));
      expect(main, contains('focusTimerLabel: focusTimerLabel'));
    });

    test('binds widget mutations to the captured snapshot contract', () {
      final snapshotStart = swift.indexOf(
        'private struct DuoyiWidgetSnapshot {',
      );
      final snapshotEnd = swift.indexOf(
        'private struct DuoyiWidgetConfig {',
        snapshotStart,
      );
      final snapshot = swift.substring(snapshotStart, snapshotEnd);
      final actionURLStart = snapshot.indexOf('    func actionURL(');
      final actionURL = snapshot.substring(actionURLStart);
      final capture = _swiftFunctionBlock(swift, 'entry()');
      final entry = _swiftFunctionBlock(swift, 'entry(values');
      final readTodoRows = _swiftFunctionBlock(swift, 'readTodoRows');
      final todoRowStart = swift.indexOf('private struct DuoyiTodoRow:');
      final todoRowEnd = swift.indexOf(
        'private struct DuoyiWidgetRow:',
        todoRowStart,
      );
      final todoRow = swift.substring(todoRowStart, todoRowEnd);
      final quickURLStart = swift.indexOf('    private var quickURL: URL? {');
      final quickURLEnd = swift.indexOf(
        '\n}\n\nprivate let todoConfig',
        quickURLStart,
      );
      final quickURL = swift.substring(quickURLStart, quickURLEnd);
      final pushStart = service.indexOf('static Future<bool> push({');
      final pushEnd = service.indexOf(
        'static Future<bool> _updateAllWidgets()',
        pushStart,
      );
      final push = service.substring(pushStart, pushEnd);

      expect(snapshot, contains('let day: String'));
      expect(snapshot, contains('let utcOffsetMinutes: Int?'));
      expect(snapshot, contains('let accountNonce: String'));
      expect(snapshot, contains('values["widget_snapshot_day"]'));
      expect(
        snapshot,
        contains('values["widget_snapshot_utc_offset_minutes"]'),
      );
      expect(snapshot, contains('values["widget_account_nonce"]'));
      expect(snapshot, contains('var hasPublishedSession: Bool'));
      expect(snapshot, contains('Self.isValidDay(day)'));
      expect(snapshot, contains('utcOffsetMinutes != nil'));
      expect(snapshot, contains('CFBooleanGetTypeID()'));
      expect(snapshot, contains('Int(exactly: raw)'));
      expect(snapshot, contains('offset.multipliedReportingOverflow(by: 60)'));
      expect(snapshot, isNot(contains('number.intValue')));
      expect(
        snapshot,
        contains(
          '!accountNonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty',
        ),
      );
      final metadataInit = snapshot.substring(
        snapshot.indexOf('    init(values:'),
        snapshot.indexOf('    private init('),
      );
      expect(metadataInit, isNot(contains('.trimmingCharacters')));
      expect(snapshot, contains('func isFresh(at date: Date) -> Bool'));
      expect(snapshot, contains('day == localDay'));
      expect(
        snapshot,
        contains(
          'utcOffsetMinutes == gregorian.timeZone.secondsFromGMT(for: date) / 60',
        ),
      );

      expect(
        capture,
        contains(
          'let defaults = UserDefaults(suiteName: appGroupId)?.'
          'dictionaryRepresentation() ?? [:]',
        ),
      );
      expect(
        RegExp(r'dictionaryRepresentation\(\)').allMatches(capture),
        hasLength(1),
      );
      expect(capture, contains('return entry(values: defaults, at: Date())'));
      expect(entry, isNot(contains('UserDefaults')));
      expect(entry, isNot(contains('Date()')));
      expect(
        entry,
        contains('let snapshot = DuoyiWidgetSnapshot(values: defaults)'),
      );
      expect(entry, contains('snapshot: snapshot,'));
      expect(entry, contains('let fresh = snapshot.isFresh(at: now)'));
      expect(readTodoRows, contains('snapshot: DuoyiWidgetSnapshot'));
      expect(readTodoRows, contains('snapshot: snapshot'));
      expect(
        entry,
        contains(
          'let todoRows = fresh ? readTodoRows(defaults, locale: locale, '
          'snapshot: snapshot) : []',
        ),
      );
      expect(entry, contains('if !fresh {'));
      expect(entry, contains('habitQuickCheckId: fresh ?'));
      expect(
        push,
        contains('final capturedAt = snapshotAt ?? DateTime.now();'),
      );
      expect(push, contains('final now = capturedAt;'));
      expect(push, contains('final offset = now.timeZoneOffset.inMinutes;'));
      expect(
        push,
        contains("'widget_account_nonce': _accountActionNonce ?? ''"),
      );
      expect(push, contains("'widget_snapshot_utc_offset_minutes'"));
      expect(
        push,
        contains("_saveWidgetPayloadValue('widget_snapshot_day', day)"),
      );
      final dayInvalidated = push.indexOf(
        "_saveWidgetPayloadValue('widget_snapshot_day', '')",
      );
      final noncePrepared = push.indexOf(
        "'widget_account_nonce': _accountActionNonce ?? ''",
      );
      final payloadPublished = push.indexOf(
        'final saveResult = await _saveWidgetPayload(payload);',
      );
      final offsetPublished = push.indexOf(
        "'widget_snapshot_utc_offset_minutes'",
      );
      final dayPublished = push.indexOf(
        "_saveWidgetPayloadValue('widget_snapshot_day', day)",
      );
      expect(dayInvalidated, greaterThanOrEqualTo(0));
      expect(noncePrepared, greaterThanOrEqualTo(0));
      expect(payloadPublished, greaterThanOrEqualTo(0));
      expect(offsetPublished, greaterThanOrEqualTo(0));
      expect(dayPublished, greaterThanOrEqualTo(0));
      expect(noncePrepared, lessThan(dayInvalidated));
      expect(dayInvalidated, lessThan(payloadPublished));
      expect(payloadPublished, lessThan(offsetPublished));
      expect(offsetPublished, lessThan(dayPublished));

      expect(entry, contains('isDailyFresh: fresh,'));
      expect(
        entry,
        contains(
          'focusTimer: DuoyiFocusTimerState.resolve(values: defaults, '
          'sessionPublished: snapshot.hasPublishedSession, at: now)',
        ),
      );
      final core = swift.substring(
        swift.indexOf('// BEGIN DUOYI_WIDGET_TIMER_CORE'),
        swift.indexOf('// END DUOYI_WIDGET_TIMER_CORE'),
      );
      expect(core, contains('guard sessionPublished,'));
      expect(core, isNot(contains('UserDefaults')));
      expect(core, isNot(contains('Date()')));
      expect(core, contains('nowMillis.subtractingReportingOverflow'));
      expect(core, contains('input.endsAtMillis.subtractingReportingOverflow'));
      expect(core, contains('CFBooleanGetTypeID()'));
      expect(core, contains('Int64(exactly: floor(raw))'));
      expect(core, contains('guard isDailyFresh else { return .open }'));
      expect(core, contains('case .idle: return .start'));
      expect(
        core,
        contains('case .pausedCountdown, .pausedCountUp: return .resume'),
      );
      expect(
        swift,
        contains('focusTimer.actionIntent(isDailyFresh: isDailyFresh)'),
      );

      expect(
        actionURL,
        contains(
          'let mutates = ["complete_todo", "checkin_habit", '
          '"start_pomodoro"].contains(action)',
        ),
      );
      expect(actionURL, contains('(action == "quick_todo" && hasQuickText)'));
      expect(
        actionURL,
        contains('guard mutates else { return components.url }'),
      );
      expect(
        actionURL,
        contains('guard components.scheme?.lowercased() == "duoyi"'),
      );
      expect(
        actionURL,
        contains(
          'guard isFresh(at: date, calendar: calendar), let offset = utcOffsetMinutes '
          'else { return nil }',
        ),
      );
      expect(actionURL, contains('components.percentEncodedPath'));
      expect(actionURL, contains('encodedAction.removingPercentEncoding'));
      expect(actionURL, contains('omittingEmptySubsequences: false'));
      expect(actionURL, contains('name == "text"'));
      expect(
        actionURL,
        contains(
          r'!($0.value ?? "").trimmingCharacters(in: '
          r'.whitespacesAndNewlines).isEmpty',
        ),
      );
      expect(
        actionURL,
        contains(
          'let bindingKeys = Set(["source", "widget_day", "widget_offset", '
          '"widget_account"])',
        ),
      );
      expect(
        actionURL,
        contains('URLQueryItem(name: "source", value: "widget")'),
      );
      expect(
        actionURL,
        contains('URLQueryItem(name: "widget_day", value: day)'),
      );
      expect(
        actionURL,
        contains('URLQueryItem(name: "widget_offset", value: String(offset))'),
      );
      expect(
        actionURL,
        contains('URLQueryItem(name: "widget_account", value: accountNonce)'),
      );
      expect(actionURL, isNot(contains('UserDefaults')));
      expect(actionURL, isNot(contains('UUID')));

      expect(todoRow, contains('let snapshot: DuoyiWidgetSnapshot'));
      expect(
        todoRow,
        contains('URLComponents(string: "duoyi://action/complete_todo")'),
      );
      expect(todoRow, contains('return snapshot.actionURL(components)'));
      expect(
        quickURL,
        contains('URLComponents(string: "duoyi://action/checkin_habit")'),
      );
      expect(quickURL, contains('entry.snapshot.actionURL(components)'));
      expect(
        quickURL,
        contains(
          'entry.snapshot.actionURL(URLComponents(string: '
          'entry.config.quickActionLink))',
        ),
      );
      expect(
        swift,
        contains(
          'if let url = entry.snapshot.actionURL('
          'URLComponents(string: target))',
        ),
      );
      expect(
        _swiftConfigBlock(swift, 'todoConfig'),
        contains('quickActionLink: "duoyi://action/quick_todo"'),
      );
      expect(
        _swiftConfigBlock(swift, 'focusConfig'),
        contains('deepLink: "duoyi://focus"'),
      );
      expect(
        _swiftConfigBlock(swift, 'focusConfig'),
        contains('quickActionLink: "duoyi://action/start_pomodoro"'),
      );
    });

    test('refreshes daily data at midnight and focus timers at their end', () {
      final timelineStart = swift.indexOf('    func getTimeline(');
      final timelineEnd = swift.indexOf(
        '    private func entry()',
        timelineStart,
      );
      final timeline = swift.substring(timelineStart, timelineEnd);

      expect(timeline, contains('current.focusTimerRunning ? 1 : 15'));
      expect(
        RegExp(r'dictionaryRepresentation\(\)').allMatches(timeline),
        hasLength(1),
      );
      expect(
        timeline,
        contains('let current = entry(values: defaults, at: now)'),
      );
      expect(
        timeline,
        contains(
          r'let entries = dates.map { entry(values: defaults, at: $0) }',
        ),
      );
      expect(
        timeline,
        contains(
          'DuoyiFocusTimerTimeline.dates(now: now, timer: current.focusTimer, calendar: calendar)',
        ),
      );
      expect(
        timeline,
        contains('Timeline(entries: entries, policy: .after(nextRefresh))'),
      );
      expect(
        timeline,
        contains('nextRefresh = min(nextRefresh, nextTransition)'),
      );
      expect(swift, contains('calendar.dateInterval(of: .day, for: now)?.end'));
      expect(
        swift,
        contains('let horizon = now.addingTimeInterval(48 * 60 * 60)'),
      );
      expect(swift, contains('return Array(Set(dates)).sorted()'));
      expect(
        swift,
        contains(
          'if timer.phase == .runningCountdown { append(timer.endDate) }',
        ),
      );
    });

    test('supports home screen and lock screen WidgetKit families', () {
      expect(
        swift,
        contains(
          'var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]',
        ),
      );
      expect(swift, contains('families.append(.systemExtraLarge)'));
      expect(swift, contains('.accessoryInline'));
      expect(swift, contains('.accessoryCircular'));
      expect(swift, contains('.accessoryRectangular'));
      expect(swift, contains('private var accessoryContent: some View'));
      expect(swift, contains('AccessoryWidgetBackground()'));
      expect(swift, contains('private var isAccessoryFamily: Bool'));
      expect(swift, contains('private var accessoryPrimaryText: String'));
      expect(swift, contains('private var accessorySecondaryText: String?'));
      expect(swift, contains('private var accessorySymbol: String'));
      expect(swift, contains('formatMinutes'));
    });

    test('keeps WidgetKit text compatible with iOS 14 and clipped in bounds', () {
      final widgetTargetBlocks = RegExp(
        r'IPHONEOS_DEPLOYMENT_TARGET = 14\.0;',
      ).allMatches(project).length;
      expect(widgetTargetBlocks, greaterThanOrEqualTo(3));
      expect(swift, isNot(contains('.foregroundStyle(')));
      expect(swift, contains('.foregroundColor(entry.theme.mutedText)'));
      expect(swift, contains('.foregroundColor(entry.theme.primary)'));
      expect(
        swift,
        contains(
          '.foregroundColor(primary ? entry.theme.text : entry.theme.mutedText)',
        ),
      );
      expect(
        swift,
        contains(
          'private func todoText(_ title: String, primary: Bool) -> some View',
        ),
      );
      final rowText = _swiftFunctionBlock(swift, 'rowText');
      final todoText = _swiftFunctionBlock(swift, 'todoText');
      final navText = _swiftFunctionBlock(swift, 'navText');
      for (final block in [rowText, todoText, navText]) {
        expect(block, contains('.lineLimit('));
        expect(block, contains('.truncationMode(.tail)'));
      }
      final header = _swiftPropertyBlock(swift, 'header');
      final focusContent = _swiftPropertyBlock(swift, 'focusContent');
      final todoRow = _swiftFunctionBlock(swift, 'todoRow');
      final accessoryContent = _swiftPropertyBlock(swift, 'accessoryContent');
      for (final block in [header, focusContent, todoRow, accessoryContent]) {
        expect(block, contains('.lineLimit(1)'));
        expect(block, contains('.truncationMode(.tail)'));
      }
      expect(header, contains('.layoutPriority(1)'));
      expect(focusContent, contains('.minimumScaleFactor(0.78)'));
      expect(todoText, contains('.lineLimit(primary ? primaryLines : 1)'));
      expect(navText, contains('.lineLimit(1)'));
    });

    test('Flutter side enables iOS home_widget updates', () {
      expect(service, contains('PlatformInfo.isAndroid || PlatformInfo.isIOS'));
      expect(service, contains('HomeWidget.setAppGroupId(_appGroupId)'));
      expect(service, contains('HomeWidget.initiallyLaunchedFromHomeWidget()'));
      expect(service, contains('HomeWidget.widgetClicked'));
    });

    test(
      'exposes WidgetKit deep links for quick actions and footer navigation',
      () {
        const deepLinksByKind = {
          'DuoyiTodoWidget': 'duoyi://todo',
          'DuoyiFocusWidget': 'duoyi://focus',
          'DuoyiHabitWidget': 'duoyi://habit',
          'DuoyiCalendarWidget': 'duoyi://calendar',
          'DuoyiScheduleWidget': 'duoyi://calendar',
          'DuoyiGoalWidget': 'duoyi://goal',
          'DuoyiCourseWidget': 'duoyi://course',
          'DuoyiNoteWidget': 'duoyi://note',
          'DuoyiAnniversaryWidget': 'duoyi://anniversary',
          'DuoyiDiaryWidget': 'duoyi://diary',
        };
        const quickLinksByKind = {
          'DuoyiTodoWidget': 'duoyi://action/quick_todo',
          'DuoyiFocusWidget': 'duoyi://action/start_pomodoro',
          'DuoyiHabitWidget': 'duoyi://habit',
          'DuoyiCalendarWidget': 'duoyi://calendar',
          'DuoyiScheduleWidget': 'duoyi://calendar',
          'DuoyiGoalWidget': 'duoyi://goal',
          'DuoyiCourseWidget': 'duoyi://course',
          'DuoyiNoteWidget': 'duoyi://note',
          'DuoyiAnniversaryWidget': 'duoyi://anniversary',
          'DuoyiDiaryWidget': 'duoyi://diary',
        };
        const handlingByKind = {
          'DuoyiTodoWidget': [
            "uri.host == 'todo'",
            'state.navigateTo(1, allowHidden: true);',
            'TodayDetailRouter.open(ctx, TodaySectionKind.todos, id: id)',
            "action == 'quick_todo'",
            "action == 'complete_todo'",
          ],
          'DuoyiFocusWidget': [
            "action == 'start_pomodoro'",
            'state.navigateTo(4, allowHidden: true);',
            'pomodoro.startIfIdle()',
            'WidgetActionNotice.focusRunning',
          ],
          'DuoyiHabitWidget': [
            "uri.host == 'habit'",
            'state.navigateTo(2, allowHidden: true);',
            'TodayDetailRouter.open(ctx, TodaySectionKind.habits, id: id)',
            "action == 'checkin_habit'",
          ],
          'DuoyiCalendarWidget': [
            "uri.host == 'calendar'",
            'state.navigateTo(3, allowHidden: true);',
          ],
          'DuoyiScheduleWidget': [
            "uri.host == 'calendar'",
            'state.navigateTo(3, allowHidden: true);',
          ],
          'DuoyiGoalWidget': [
            "uri.host == 'goal'",
            '_pushHiddenWidgetFallbackRoute(ctx, const GoalScreen())',
            'TodayDetailRouter.open(ctx, TodaySectionKind.goals, id: id)',
          ],
          'DuoyiCourseWidget': [
            "uri.host == 'course'",
            'TodayDetailRouter.open(ctx, TodaySectionKind.courses, id: id)',
          ],
          'DuoyiNoteWidget': [
            "uri.host == 'note'",
            'TodayDetailRouter.open(ctx, TodaySectionKind.notes, id: id)',
          ],
          'DuoyiAnniversaryWidget': [
            "uri.host == 'anniversary'",
            'TodayDetailRouter.open(ctx, TodaySectionKind.anniversaries, id: id)',
          ],
          'DuoyiDiaryWidget': [
            "uri.host == 'diary'",
            'TodayDetailRouter.open(ctx, TodaySectionKind.diary, id: id)',
          ],
        };

        expect(swift, contains('Link(destination: quickURL)'));
        expect(swift, contains('Link(destination: url)'));
        expect(swift, contains('navLink(entry.navTodo, "duoyi://todo")'));
        expect(swift, contains('navLink(entry.navHabit, "duoyi://habit")'));
        expect(
          swift,
          contains('navLink(entry.navCalendar, "duoyi://calendar")'),
        );
        expect(swift, contains('navLink(entry.navFocus, "duoyi://focus")'));
        final entryBlock = _swiftFunctionBlock(swift, 'entry(values');
        const navPayloadFields = {
          'navTodo': 'nav_todo',
          'navHabit': 'nav_habit',
          'navCalendar': 'nav_calendar',
          'navFocus': 'nav_focus',
        };
        for (final mapping in navPayloadFields.entries) {
          final rawName =
              'raw${mapping.key[0].toUpperCase()}${mapping.key.substring(1)}';
          expect(
            entryBlock,
            contains(
              'let $rawName = readString(defaults, key: "${mapping.value}"',
            ),
          );
          expect(
            entryBlock,
            contains('let ${mapping.key} = (locale == .en && $rawName =='),
          );
          expect(entryBlock, contains('${mapping.key}: ${mapping.key},'));
        }

        for (final kind in widgetKinds) {
          final configBlock = _swiftConfigBlock(swift, _configName(kind));
          expect(configBlock, contains('deepLink: "${deepLinksByKind[kind]}"'));
          expect(
            configBlock,
            contains('quickActionLink: "${quickLinksByKind[kind]}"'),
          );
        }
        expect(
          swift,
          contains('URLComponents(string: "duoyi://action/checkin_habit")'),
        );
        expect(swift, contains('duoyiPathSegmentAllowed'));
        expect(
          swift,
          contains(r'''allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")'''),
        );
        expect(swift, contains('duoyi://todo/\\(encodedId)'));
        expect(
          swift,
          contains('URLComponents(string: "duoyi://action/complete_todo")'),
        );
        expect(swift, contains('URLQueryItem(name: "id", value: todoId)'));
        expect(
          swift,
          contains('URLComponents(string: "duoyi://action/checkin_habit")'),
        );
        expect(swift, contains('readTodoRows'));
        expect(swift, contains('todo_top3_\\(index)_id'));
        expect(swift, contains('ForEach(visibleTodoRows)'));
        expect(swift, contains('Text("o")'));
        expect(swift, isNot(contains('Text("完成")')));
        expect(swift, isNot(contains('duoyi://action/start_focus')));

        final main = File('lib/main.dart').readAsStringSync();
        expect(main, contains('_homeWidgetEventsForToday'));
        expect(main, contains('_homeWidgetEventDeepLink'));
        expect(
          main,
          contains("'duoyi://goal/\${Uri.encodeComponent(goal.id)}'"),
        );
        expect(
          main,
          contains("'duoyi://course/\${Uri.encodeComponent(course.id)}'"),
        );
        expect(
          main,
          contains("'duoyi://note/\${Uri.encodeComponent(note.id)}'"),
        );
        expect(
          main,
          contains("'duoyi://diary/\${Uri.encodeComponent(entry.id)}'"),
        );
        expect(main, contains('todayEventSummary ='));
        expect(
          main,
          isNot(contains("todayEventSummary: top3.isEmpty ? '今日没有日程'")),
        );
        for (final kind in widgetKinds) {
          for (final snippet in handlingByKind[kind]!) {
            expect(main, contains(snippet), reason: kind);
          }
        }
        expect(main, contains("uri.host == 'focus'"));
        expect(
          main,
          contains('state.navigateTo(idx, allowHidden: true);'),
          reason:
              'WidgetKit footer links must keep hidden bottom-nav destinations reachable.',
        );
      },
    );

    test('Runner forwards WidgetKit and OAuth deep links into Flutter', () {
      expect(appDelegate, contains('final class DuoyiDeepLinkBridge'));
      expect(appDelegate, contains('FlutterMethodChannel('));
      expect(appDelegate, contains('name: channelName'));
      expect(appDelegate, contains('"duoyi/deep_links"'));
      expect(appDelegate, contains('case "takeInitialLink"'));
      expect(appDelegate, contains('case "takeInitialOAuthLink"'));
      expect(appDelegate, contains('case "takeInitialSharedText"'));
      expect(appDelegate, contains('channel?.invokeMethod("onLink"'));
      expect(appDelegate, contains('url.scheme == "duoyi"'));
      expect(appDelegate, contains('url.host == "oauth"'));
      expect(appDelegate, contains('launchOptions?[.url] as? URL'));
      expect(appDelegate, contains('open url: URL'));
      expect(appDelegate, contains('controller.binaryMessenger'));

      expect(sceneDelegate, contains('willConnectTo session'));
      expect(
        sceneDelegate,
        contains('connectionOptions.urlContexts.first?.url'),
      );
      expect(sceneDelegate, contains('openURLContexts URLContexts'));
      expect(sceneDelegate, contains('DuoyiDeepLinkBridge.shared.handle'));
      expect(sceneDelegate, contains('controller.binaryMessenger'));

      final deepLinkService = File(
        'lib/services/deep_link_service.dart',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();
      expect(deepLinkService, contains('takeInitialLink'));
      expect(deepLinkService, contains('_isDuoyiDeepLink(uri)'));
      expect(main, contains('DeepLinkService.takeInitialLink()'));
      expect(main, contains('DeepLinkService.takeInitialOAuthLink()'));
    });
  });
}

String _swiftConfigBlock(String swift, String configName) {
  final match = RegExp(
    'private let ${RegExp.escape(configName)} = DuoyiWidgetConfig\\((.*?)^\\)',
    multiLine: true,
    dotAll: true,
  ).firstMatch(swift);
  if (match == null) {
    throw StateError('Missing Swift widget config $configName');
  }
  return match.group(0)!;
}

String _swiftFunctionBlock(String swift, String functionName) {
  final start = swift.indexOf('private func $functionName');
  if (start < 0) {
    throw StateError('Missing Swift function $functionName');
  }
  final next = swift.indexOf('\n    private ', start + 1);
  final end = next < 0 ? swift.indexOf('\n}', start + 1) : next;
  if (end <= start) {
    throw StateError('Missing Swift function end for $functionName');
  }
  return swift.substring(start, end);
}

String _swiftPropertyBlock(String swift, String propertyName) {
  final start = swift.indexOf('private var $propertyName');
  if (start < 0) {
    throw StateError('Missing Swift property $propertyName');
  }
  final next = swift.indexOf('\n    private ', start + 1);
  final end = next < 0 ? swift.indexOf('\n}', start + 1) : next;
  if (end <= start) {
    throw StateError('Missing Swift property end for $propertyName');
  }
  return swift.substring(start, end);
}

String _configName(String kind) {
  return switch (kind) {
    'DuoyiTodoWidget' => 'todoConfig',
    'DuoyiFocusWidget' => 'focusConfig',
    'DuoyiHabitWidget' => 'habitConfig',
    'DuoyiCalendarWidget' => 'calendarConfig',
    'DuoyiScheduleWidget' => 'scheduleConfig',
    'DuoyiGoalWidget' => 'goalConfig',
    'DuoyiCourseWidget' => 'courseConfig',
    'DuoyiNoteWidget' => 'noteConfig',
    'DuoyiAnniversaryWidget' => 'anniversaryConfig',
    'DuoyiDiaryWidget' => 'diaryConfig',
    _ => throw ArgumentError.value(kind, 'kind'),
  };
}

String _serviceName(String kind) {
  return switch (kind) {
    'DuoyiTodoWidget' => 'TodoWidgetName',
    'DuoyiFocusWidget' => 'FocusWidgetName',
    'DuoyiHabitWidget' => 'HabitWidgetName',
    'DuoyiCalendarWidget' => 'CalendarWidgetName',
    'DuoyiScheduleWidget' => 'ScheduleWidgetName',
    'DuoyiGoalWidget' => 'GoalWidgetName',
    'DuoyiCourseWidget' => 'CourseWidgetName',
    'DuoyiNoteWidget' => 'NoteWidgetName',
    'DuoyiAnniversaryWidget' => 'AnniversaryWidgetName',
    'DuoyiDiaryWidget' => 'DiaryWidgetName',
    _ => throw ArgumentError.value(kind, 'kind'),
  };
}
