import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('iOS WidgetKit resources', () {
    final swift = File(
      'ios/DuoyiWidgets/DuoyiWidgets.swift',
    ).readAsStringSync();
    final captureSwift = File(
      'ios/DuoyiWidgets/DuoyiWidgetPublicationCapture.swift',
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

    // BEGIN IOS FOCUS ACCESSORY POLICY 2297 REGISTRATIONS
    test(
      'focus accessory families consume the canonical display through the real entry path',
      () {
        final result = _iosFocus2297Policy(swift);
        expect(result['entry'], isEmpty);
      },
    );

    test(
      'focus accessory admission preserves a complete clock and localized recovery semantics',
      () {
        final result = _iosFocus2297Policy(swift);
        expect(result['presentation'], isEmpty);
        // LIMITED nominal148 policy; this is never an actual inline-host fit oracle.
      },
    );

    test('focus accessory policy rejects bounded source counterexamples', () {
      expect(_iosFocus2297Policy(swift).values.expand((ids) => ids), isEmpty);
      const variants = <(String, String, String, String, String)>[
        (
          'C1 detached-accessory', 'accessoryContent',
          'accessoryFocusInlineView(focusDisplay)', 'Text(verbatim: "")',
          'inline-entry-call',
        ),
        (
          'C2 family-snapshot', 'circular-text-arm',
          'focusClock(display)\n                            .font(Font(clockFont))',
          'Text(accessoryShortText)\n                            .font(Font(clockFont))',
          'circular-text-clock',
        ),
        (
          'C3 display-authority', 'accessoryFocusDisplay',
          'let display = entry.focusTimer.display(at: entry.date)',
          'let display = entry.focusTimer.display(at: Date())',
          'display-authority',
        ),
        (
          'C4 sample-as-clock', 'accessoryFocusInlineView',
          'Text(verbatim: trailingStatus.isEmpty ? clock : "\\(clock) · \\(trailingStatus)")',
          'Text(verbatim: clockSample ?? "")',
          'inline-fixed-complete',
        ),
        (
          'C5 shortened-clock', 'accessoryFocusInlineView',
          'Text(verbatim: trailingStatus.isEmpty ? clock : "\\(clock) · \\(trailingStatus)")',
          'Text(verbatim: String(clock.prefix(3)))',
          'inline-fixed-complete',
        ),
        (
          'C6 admission-bypass', 'accessoryFitsInCircle',
          '(topWidth * topWidth + totalHeight * totalHeight) <= maxDiameterSq',
          'true',
          'circular-chord-fit',
        ),
        (
          'C7 wrong-metric', 'accessoryFocusRectangularBody',
          'width(sample, font: font, pixelScale: pixelScale)',
          'width(sample, font: statusFont, pixelScale: pixelScale)',
          'rectangular-clock-metric',
        ),
        (
          'C8 locale-override', 'accessoryFocusInlineView',
          '.accessibilityLabel(accessoryFocusAccessibilityText(display))\n            .environment(\\.locale, DuoyiFocusTimerState.timerClockLocale)',
          '.accessibilityLabel(accessoryFocusAccessibilityText(display))\n            .environment(\\.locale, entry.locale)',
          'inline-clock-locale',
        ),
        (
          'C9 cap-is-finished', 'accessoryFocusDirectionStatus',
          'return entry.locale == .en ? "Count-up elapsed · 24h cap reached" : "正计时已用 · 已达24小时上限"',
          'return entry.locale == .en ? "Finished · Countdown ended" : "正计时已用 · 已达24小时上限"',
          'cap-direction-truth',
        ),
        (
          'C10 hidden-live-child', 'accessoryFocusInlineView',
          '.accessibilityLabel(accessoryFocusAccessibilityText(display))',
          '.accessibilityHidden(true)',
          'inline-clock-ax',
        ),
        (
          'C11 action-or-refresh', 'accessoryFocusInlineView',
          'let inlineMaxWidth: Double = 148.0',
          'let inlineMaxWidth: Double = 148.0\n        WidgetCenter.shared.reloadAllTimelines()',
          'focus-side-effects',
        ),
        (
          'C12 decoy-disconnected', 'accessoryContent',
          'accessoryFocusInlineView(focusDisplay)',
          'Text(verbatim: "")\n                    // accessoryFocusInlineView(focusDisplay)\n                    let decoy = "accessoryFocusInlineView(focusDisplay)"',
          'inline-entry-call',
        ),
      ];
      for (final variant in variants) {
        final changed = _iosFocus2297Replace(
          swift, variant.$2, variant.$3, variant.$4,
        );
        final rejected = _iosFocus2297Policy(changed);
        expect(
          rejected.values.expand((ids) => ids),
          contains(variant.$5),
          reason: '${variant.$1} must fail its designated policy, not syntax.',
        );
      }
      final sanity = _iosFocus2297Replace(
        swift, 'accessoryContent', 'accessoryFocusInlineView(focusDisplay)',
        '// focusClock(entry.focusTimer.display(at: Date()))\n'
        '                    let decoy = "accessoryFocusInlineView(focusDisplay)"\n'
        '                    accessoryFocusInlineView(focusDisplay)',
      );
      expect(_iosFocus2297Policy(sanity), _iosFocus2297Policy(swift));
    });
    // END IOS FOCUS ACCESSORY POLICY 2297 REGISTRATIONS

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

    test(
      'invalid theme colors retain each role fallback and ARGB components',
      () {
        final theme = _swiftTypeBlock(swift, 'DuoyiWidgetTheme');
        const roles = {
          'primary': ('primary', '#FF0066D6'),
          'background': ('background', '#FFF6F7F9'),
          'surface': ('surface', '#FFFFFFFF'),
          'navBackground': ('nav_background', '#FFF1F3F6'),
          'border': ('border', '#000066D6'),
          'text': ('text', '#FF1F2933'),
          'mutedText': ('muted_text', '#FF667085'),
          'onPrimary': ('on_primary', '#FFFFFFFF'),
          'accentStart': ('accent_start', '#FF0066D6'),
          'accentEnd': ('accent_end', '#FF2F8F83'),
        };
        for (final entry in roles.entries) {
          expect(
            theme,
            contains(
              'self.${entry.key} = Self.read(values, '
              'key: "widget_theme_${entry.value.$1}", '
              'fallback: "${entry.value.$2}")',
            ),
          );
          expect(theme, contains('${entry.key}: color("${entry.value.$2}")'));
        }
        expect(theme, contains('color(values[key], fallback: fallback)'));
        expect(
          theme,
          contains(
            'DuoyiWidgetThemeColorCore.resolve(raw, fallback: fallback)',
          ),
        );
        expect(theme, contains('Double((value >> 24) & 0xFF) / 255.0'));
        expect(theme, contains('Double((value >> 16) & 0xFF) / 255.0'));
        expect(theme, contains('Double((value >> 8) & 0xFF) / 255.0'));
        expect(theme, contains('Double(value & 0xFF) / 255.0'));
        expect(
          theme,
          contains(
            'Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)',
          ),
        );
        expect(theme, isNot(contains('Color(red: 0.784')));
      },
    );

    test(
      'small todo uses a bound first-item root while larger families keep item links',
      () {
        final policy = _swiftPropertyBlock(swift, 'supportsItemLinks');
        expect(policy, contains('family == .systemMedium'));
        expect(policy, contains('family == .systemLarge'));
        expect(policy, contains('family == .systemExtraLarge'));
        expect(policy, contains('return false'));
        expect(
          _swiftFunctionBlock(swift, 'plannedHeaderView'),
          contains('if supportsItemLinks, let quickURL'),
        );
        expect(
          _swiftFunctionBlock(swift, 'plannedLinkedText'),
          contains('if supportsItemLinks, let url'),
        );
        expect(
          _swiftFunctionBlock(swift, 'plannedCalendarDayCell'),
          contains('if supportsItemLinks, let target'),
        );
        final todoRow = _swiftFunctionBlock(swift, 'plannedTodoRow');
        expect(todoRow, contains('if supportsItemLinks, let detailURL'));
        expect(
          todoRow,
          contains(
            'let hasCompletion = supportsItemLinks && (row.completeURL != nil)',
          ),
        );
        expect(
          todoRow,
          contains('if hasCompletion, let completeURL = row.completeURL'),
        );
        expect(todoRow, contains('Complete task:'));
        expect(todoRow, contains('完成待办：'));
        final rootURL = _swiftPropertyBlock(swift, 'widgetRootURL');
        expect(rootURL, contains('family == .systemSmall'));
        expect(rootURL, contains('entry.config.kind == "DuoyiTodoWidget"'));
        expect(rootURL, contains('entry.isDailyFresh'));
        expect(rootURL, contains('entry.todoRows.first'));
        expect(rootURL, contains('first.detailURL'));
        expect(rootURL, contains('URL(string: entry.config.deepLink)'));
        final todoRoot = _swiftCodeBlock(
          rootURL,
          'if entry.config.kind == "DuoyiTodoWidget"',
        );
        expect(todoRoot, isNot(contains('entry.primaryTarget')));
        final viewBody = _swiftPropertyBlock(
          _swiftTypeBlock(swift, 'DuoyiWidgetView'),
          'body',
        );
        _expectSourceInOrder(viewBody, [
          'if isAccessoryFamily {',
          'accessoryContent',
          '.widgetURL(widgetRootURL)',
          '} else if entry.config.kind == "DuoyiCalendarWidget" {',
          'calendarBody',
          '} else {',
          '.widgetURL(widgetRootURL)',
        ]);
        expect(
          _swiftPropertyBlock(swift, 'calendarBody'),
          contains('.widgetURL(URL(string: entry.config.deepLink))'),
        );
        expect(
          RegExp(r'case "systemSmall":\s+return 0\b').hasMatch(
            _swiftFunctionBlock(
              _swiftTypeBlock(swift, 'DuoyiWidgetTypographyLayoutCore'),
              'rows',
            ),
          ),
          isTrue,
        );
      },
    );

    test(
      'small goal binds its single displayed object to existing detail flow',
      () {
        final rootURL = _swiftPropertyBlock(swift, 'widgetRootURL');
        expect(rootURL, contains('entry.config.kind == "DuoyiGoalWidget"'));
        expect(rootURL, contains('entry.snapshot.actionURL(components)'));
        _expectSmallSingleObjectCap(swift, 'DuoyiGoalWidget');
        final config = _swiftConfigBlock(swift, 'goalConfig');
        expect(config, contains('primaryKey: "goal_highlight_1"'));
        expect(config, contains('deepLink: "duoyi://goal"'));
        // Target validation and identity are exercised against extracted real
        // Swift members by ios_widget_controls_cases.swift, not source tokens.
      },
    );

    test(
      'small anniversary binds its single displayed object to existing detail flow',
      () {
        final rootURL = _swiftPropertyBlock(swift, 'widgetRootURL');
        expect(
          rootURL,
          contains('entry.config.kind == "DuoyiAnniversaryWidget"'),
        );
        expect(rootURL, contains('entry.snapshot.actionURL(components)'));
        _expectSmallSingleObjectCap(swift, 'DuoyiAnniversaryWidget');
        final config = _swiftConfigBlock(swift, 'anniversaryConfig');
        expect(config, contains('primaryKey: "anniversary_highlight_1"'));
        expect(config, contains('deepLink: "duoyi://anniversary"'));
        // Target validation and identity are exercised against extracted real
        // Swift members by ios_widget_controls_cases.swift, not source tokens.
      },
    );

    test(
      'small course binds its single displayed object to existing detail flow',
      () {
        final rootURL = _swiftPropertyBlock(swift, 'widgetRootURL');
        expect(rootURL, contains('entry.config.kind == "DuoyiCourseWidget"'));
        expect(rootURL, contains('entry.snapshot.actionURL(components)'));
        _expectSmallSingleObjectCap(swift, 'DuoyiCourseWidget');
        final config = _swiftConfigBlock(swift, 'courseConfig');
        expect(config, contains('primaryKey: "course_highlight_1"'));
        expect(config, contains('deepLink: "duoyi://course"'));
        // Target validation and identity are exercised against extracted real
        // Swift members by ios_widget_controls_cases.swift, not source tokens.
      },
    );

    test(
      'small diary binds its single displayed object to existing detail flow',
      () {
        final rootURL = _swiftPropertyBlock(swift, 'widgetRootURL');
        expect(rootURL, contains('entry.config.kind == "DuoyiDiaryWidget"'));
        expect(rootURL, contains('entry.snapshot.actionURL(components)'));
        _expectSmallSingleObjectCap(swift, 'DuoyiDiaryWidget');
        final config = _swiftConfigBlock(swift, 'diaryConfig');
        expect(config, contains('primaryKey: "diary_highlight_1"'));
        expect(config, contains('deepLink: "duoyi://diary"'));
        // Target validation and identity are exercised against extracted real
        // Swift members by ios_widget_controls_cases.swift, not source tokens.
      },
    );

    test('small note binds the displayed primary detail to its snapshot', () {
      final rootURL = _swiftPropertyBlock(swift, 'widgetRootURL');
      _expectSourceInOrder(rootURL, [
        'family == .systemSmall',
        'entry.config.kind == "DuoyiNoteWidget"',
        'entry.isDailyFresh',
        'URLComponents(string: entry.primaryTarget)',
        'return entry.snapshot.actionURL(components) ?? moduleURL',
      ]);
      expect(
        _swiftFunctionBlock(swift, 'plannedHomeBody'),
        contains(
          'plannedLinkedText(cleanRow(entry.primary), target: entry.primaryTarget, font: primaryFont, isPrimary: true)',
        ),
        reason: 'The card target must identify its visible primary note.',
      );
      final config = _swiftConfigBlock(swift, 'noteConfig');
      expect(config, contains('primaryKey: "note_highlight_1"'));
      expect(config, contains('deepLink: "duoyi://note"'));
      _expectSourceInOrder(
        _swiftFunctionBlock(
          _swiftTypeBlock(swift, 'DuoyiWidgetTypographyLayoutCore'),
          'rows',
        ),
        [
          'if familyKind == "systemSmall" && [',
          '"DuoyiNoteWidget"',
          'return 0',
          'switch familyKind',
        ],
      );
      expect(rootURL, isNot(contains('UserDefaults')));
      expect(rootURL, isNot(contains('URL(string: entry.primaryTarget)')));
    });

    test(
      'small note rejects empty and invalid detail targets to its module',
      () {
        final rootURL = _swiftPropertyBlock(swift, 'widgetRootURL');
        final noteRoot = _swiftCodeBlock(
          rootURL,
          'if entry.config.kind == "DuoyiNoteWidget"',
        );
        expect(noteRoot, contains('let components = URLComponents('));
        expect(
          noteRoot,
          contains('components.scheme?.lowercased() == "duoyi"'),
        );
        expect(noteRoot, contains('components.host?.lowercased() == "note"'));
        for (final field in ['user', 'password', 'port', 'query', 'fragment']) {
          expect(noteRoot, contains('components.$field == nil'));
        }
        // Runtime source-extracted cases cover exact single-segment identities,
        // blank IDs and reserved characters without fixing a parsing algorithm.
        expect(noteRoot, contains('components.percentEncodedPath'));
        expect(noteRoot, contains('.removingPercentEncoding'));
        expect(
          noteRoot,
          contains('.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty'),
        );
        expect(rootURL, contains('return moduleURL'));
        final primary = _swiftFunctionBlock(swift, 'readPrimary');
        expect(
          primary,
          contains('itemTarget.isEmpty ? config.deepLink : itemTarget'),
        );
        expect(
          _swiftPropertyBlock(swift, 'supportsItemLinks'),
          contains('return false'),
          reason: 'Small Note retains one whole-card target.',
        );
      },
    );

    test(
      'focus rendering uses the timer display policy with bounded modern clocks',
      () {
        final content = _swiftFunctionBlock(swift, 'plannedHomeBody');
        expect(content, contains('entry.focusTimer.display(at: entry.date)'));
        expect(content, contains('Text(focusStatusLabel)'));
        final clock = _swiftFunctionBlock(swift, 'focusClock');
        expect(clock, contains('case .fixed(let clock):'));
        expect(clock, contains('Text(clock)'));
        expect(clock, contains('iOSApplicationExtension 16.0'));
        expect(
          clock,
          contains('Text(timerInterval: entry.date...end, countsDown: true)'),
        );
        expect(
          clock,
          contains('Text(timerInterval: start...cap, countsDown: false)'),
        );
        expect(clock, contains('Text(start, style: .timer)'));
        expect(clock, contains('Text(end, style: .timer)'));
      },
    );

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
      final home = _swiftFunctionBlock(swift, 'plannedHomeBody');
      expect(
        home,
        contains(
          'plannedLinkedText(cleanRow(entry.primary), target: entry.primaryTarget',
        ),
      );
      expect(
        home,
        contains('plannedLinkedText(cleanRow(row.title), target: row.target'),
      );
      expect(
        _swiftFunctionBlock(swift, 'plannedLinkedText'),
        contains('Link(destination: url)'),
      );
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
      expect(
        _swiftFunctionBlock(swift, 'entry', parameterPrefix: 'capture:'),
        contains(
          'let focusTimerLabel = localizedFocusTimerLabel(rawTimerLabel, locale: locale)',
        ),
      );
      expect(
        _swiftFunctionBlock(swift, 'focusClock'),
        contains('Text(end, style: .timer)'),
      );
      final metrics = _swiftTypeBlock(swift, 'DuoyiWidgetTypographyMetrics');
      final font = _swiftFunctionBlock(metrics, 'font');
      expect(
        font,
        contains(
          'UIFont.monospacedDigitSystemFont(ofSize: baseSize, weight: weight)',
        ),
      );
      final home = _swiftFunctionBlock(swift, 'plannedHomeBody');
      expect(home, contains('rounded: true, monospacedDigits: true'));
      expect(home, contains('.font(Font(focusClockFont))'));
      final digits = _swiftFunctionBlock(swift, 'duoyiMonospacedDigit');
      expect(
        digits,
        contains('if #available(iOSApplicationExtension 15.0, *)'),
      );
      expect(digits, contains('self.monospacedDigit()'));
      expect(digits, contains('} else {\n            self\n'));
      expect(
        captureSwift,
        contains('let refreshMinutes = focusTimerRunning ? 1 : 15'),
      );
      expect(swift, contains('focusTimerRunning: current.focusTimerRunning'));

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
      final snapshot = _swiftTypeBlock(swift, 'DuoyiWidgetSnapshot');
      final actionURL = _swiftFunctionBlock(
        snapshot,
        'actionURL',
        parameterPrefix: '_ components: URLComponents?, at date:',
      );
      final capture = _swiftFunctionBlock(swift, 'entry', parameterPrefix: '');
      final entry = _swiftFunctionBlock(
        swift,
        'entry',
        parameterPrefix: 'capture:',
      );
      final readTodoRows = _swiftFunctionBlock(swift, 'readTodoRows');
      final todoRow = _swiftTypeBlock(swift, 'DuoyiTodoRow');
      final quickURL = _swiftPropertyBlock(swift, 'quickURL');
      final pushStart = service.indexOf('static Future<bool> push({');
      final pushEnd = service.indexOf(
        'static Future<bool> _updateAllWidgets(',
        pushStart,
      );
      expect(pushStart, greaterThanOrEqualTo(0));
      expect(pushEnd, greaterThan(pushStart));
      final push = service.substring(pushStart, pushEnd);
      expect(push, contains('_updateAllWidgets(isCurrent: isCurrent)'));
      expect(
        service,
        contains('const maxConcurrentUpdates = 3;'),
        reason: 'iOS WidgetKit 刷新应限制并发，避免十个 family 同时冲击旧设备。',
      );
      expect(
        service,
        contains(
          'Future.wait([for (var i = 0; i < workerCount; i++) worker()])',
        ),
      );

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

      expect(capture, contains('let capture = publicationCapture()'));
      expect(
        RegExp(r'publicationCapture\(\)').allMatches(capture),
        hasLength(1),
      );
      final publicationCapture = _swiftFunctionBlock(
        swift,
        'publicationCapture',
      );
      expect(
        publicationCapture,
        contains('DuoyiWidgetPublicationCapture.capture('),
      );
      expect(
        publicationCapture,
        contains('DuoyiWidgetPublicationStore.shared.read()'),
      );
      expect(
        publicationCapture,
        contains('object(forKey: "widget_display_mode")'),
      );
      expect(swift, isNot(contains('dictionaryRepresentation()')));
      expect(swift, isNot(contains('string(forKey: "widget_locale")')));
      expect(capture, contains('return entry(capture: capture, at: Date())'));
      expect(entry, isNot(contains('UserDefaults')));
      expect(entry, isNot(contains('Date()')));
      expect(entry, contains('let defaults = capture.values'));
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
          'let mutates = isEntity || ["complete_todo", "checkin_habit", '
          '"start_pomodoro"].contains(action)',
        ),
      );
      expect(actionURL, contains('(action == "quick_todo" && hasQuickText)'));
      expect(
        actionURL,
        contains(
          'guard mutates || isDatedCalendar else { return components.url }',
        ),
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
          '"widget_account", "widget_delivery"])',
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
        _swiftFunctionBlock(swift, 'plannedLinkedText'),
        contains(
          'if supportsItemLinks, let url = entry.snapshot.actionURL('
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
      final timeline = _swiftFunctionBlock(swift, 'getTimeline');

      expect(
        RegExp(r'publicationCapture\(\)').allMatches(timeline),
        hasLength(1),
      );
      expect(timeline, contains('let capture = publicationCapture()'));
      expect(
        timeline,
        contains('let current = entry(capture: capture, at: now)'),
      );
      expect(
        timeline,
        contains(
          r'let entries = dates.map { entry(capture: capture, at: $0) }',
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
        contains('let nextRefresh = capture.timelineRefreshDate('),
      );
      expect(timeline, contains('now: now'));
      expect(
        timeline,
        contains('focusTimerRunning: current.focusTimerRunning'),
      );
      expect(timeline, contains('nextTransition: dates.dropFirst().first'));
      expect(
        captureSwift,
        contains('let refreshMinutes = focusTimerRunning ? 1 : 15'),
      );
      expect(
        captureSwift,
        contains('nextRefresh = min(nextRefresh, nextTransition)'),
      );
      expect(
        captureSwift,
        contains(
          'nextRefresh = min(nextRefresh, now.addingTimeInterval(busyReloadIntervalSeconds))',
        ),
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
      final accessoryPrimaryText = _swiftPropertyBlock(
        swift,
        'accessoryPrimaryText',
      );
      expect(
        accessoryPrimaryText,
        contains(
          'if #available(iOSApplicationExtension 16.0, *),\n'
          '               family == .accessoryInline',
        ),
      );
      expect(
        accessoryPrimaryText,
        contains('return calendarAccessoryDates.rectangular'),
      );
      expect(swift, contains('private var accessorySecondaryText: String?'));
      expect(swift, contains('private var accessorySymbol: String'));
      expect(swift, contains('formatMinutes'));
    });

    test(
      'planned calendar renders admitted weeks from original grid cells',
      () {
        final calendarContent = _swiftFunctionBlock(
          swift,
          'plannedCalendarBody',
        );
        final calendarCore = _swiftFunctionBlock(
          _swiftTypeBlock(swift, 'DuoyiWidgetTypographyLayoutCore'),
          'calendar',
        );
        _expectSourceInOrder(calendarCore, [
          'guard availableWidth >= 7.0 * maximumCellWidth',
          'guard availableHeight >= minFirstWeekHeight',
          'DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(',
          'let visibleWeeks = Array(weekRange)',
          'visibleWeeks: visibleWeeks',
        ]);

        _expectSourceInOrder(calendarContent, [
          'DuoyiWidgetDisplayCore.buildMonthGrid(',
          'DuoyiWidgetTypographyLayoutCore.calendar(',
          'DuoyiWidgetTypographyLayoutCore.rows(',
          'if let cPlan = calendarPlan, !cPlan.showsDateFallback',
          r'ForEach(cPlan.visibleWeeks, id: \.self) { week in',
          'let cell = grid.cells[week * 7 + col]',
          'plannedCalendarDayCell(',
        ]);
        expect(calendarContent, contains('anchorDate: entry.date'));
        expect(
          calendarContent,
          contains('firstDayOfWeek: entry.firstDayOfWeek'),
        );
        expect(calendarContent, contains('grid: grid,'));
        expect(calendarContent, contains('cell: cell,'));
        expect(calendarContent, contains('cellFont: dayFont,'));
        expect(calendarContent, contains('cellHeight: cellH'));
        expect(calendarContent, isNot(contains('budgetedVisibleWeekRange(')));
      },
    );

    test(
      'calendarDayCell binds only real dates and preserves label, hit area, and fallback',
      () {
        final calendarDayCell = _swiftFunctionBlock(
          swift,
          'plannedCalendarDayCell',
        );
        final realDayBranch = _swiftCodeBlock(
          calendarDayCell,
          'if cell.dayNumber > 0',
        );
        final blankCellBranch = _swiftElseBlock(
          calendarDayCell,
          'if cell.dayNumber > 0',
        );
        const targetMarker = 'if supportsItemLinks, let target = cell.target,';
        final targetBranch = _swiftCodeBlock(realDayBranch, targetMarker);
        final plainDayBranch = _swiftElseBlock(realDayBranch, targetMarker);
        final label = _swiftCodeBlock(realDayBranch, 'let dayLabel = Group');
        final todayLabel = _swiftCodeBlock(label, 'if cell.isToday');
        final ordinaryLabel = _swiftElseBlock(label, 'if cell.isToday');
        for (final dayLabel in [todayLabel, ordinaryLabel]) {
          expect(dayLabel, contains('.font(Font(cellFont))'));
          expect(dayLabel, contains('.accessibilityLabel(label)'));
          expect(
            dayLabel,
            contains(
              '.frame(width: CGFloat(cellHeight), height: CGFloat(cellHeight))',
            ),
          );
        }
        expect(
          todayLabel,
          contains('.foregroundColor(entry.theme.readableOnPrimary)'),
        );
        expect(ordinaryLabel, contains('.foregroundColor(entry.theme.text)'));

        _expectSourceInOrder(calendarDayCell, [
          'if cell.dayNumber > 0 {',
          'DuoyiWidgetDisplayCore.cellAccessibilityLabel(',
          'if supportsItemLinks, let target = cell.target,',
          'entry.snapshot.actionURL(URLComponents(string: target))',
          'Link(destination: url) {',
          '.buttonStyle(.plain)',
          '} else {',
          'dayLabel',
          '} else {',
          'Text("")',
        ]);
        expect(calendarDayCell, contains('year: grid.year'));
        expect(calendarDayCell, contains('month: grid.month'));
        expect(calendarDayCell, contains('day: cell.dayNumber'));
        expect(calendarDayCell, contains('isToday: cell.isToday'));
        expect(calendarDayCell, contains('isZh: entry.locale == .zh'));
        expect(
          calendarDayCell,
          contains('.foregroundColor(entry.theme.readableOnPrimary)'),
        );
        expect(calendarDayCell, contains('.foregroundColor(entry.theme.text)'));
        expect(
          calendarDayCell,
          contains('.accessibilityAddTraits(.isSelected)'),
        );
        _expectSourceInOrder(calendarDayCell, [
          '.frame(maxWidth: .infinity)',
          '.frame(height: CGFloat(cellHeight))',
          '.contentShape(Rectangle())',
          'if supportsItemLinks, let target = cell.target,',
        ]);
        expect(
          calendarDayCell,
          contains('.background(Circle().fill(entry.theme.primary))'),
        );
        expect(
          RegExp(r'\.background\(').allMatches(calendarDayCell),
          hasLength(1),
        );

        expect(
          plainDayBranch,
          matches(RegExp(r'^else\s*\{\s*dayLabel\s*\}$')),
          reason:
              'A missing target or stale snapshot URL must leave the real day as a plain label.',
        );
        _expectSourceInOrder(targetBranch, [
          'Link(destination: url) {',
          'dayLabel',
          '.buttonStyle(.plain)',
        ]);
        expect(targetBranch, isNot(contains('.background(')));
        expect(plainDayBranch, isNot(contains('Link(')));
        expect(blankCellBranch, contains('Text("")'));
        expect(blankCellBranch, contains('.accessibilityHidden(true)'));
        expect(blankCellBranch, isNot(contains('cell.target')));
        expect(blankCellBranch, isNot(contains('Link(')));
      },
    );

    test(
      'calendarBody keeps its section fallback and custom widget background',
      () {
        final calendarBody = _swiftPropertyBlock(swift, 'calendarBody');
        final calendarConfig = _swiftConfigBlock(swift, 'calendarConfig');
        final backgroundHelper = _swiftFunctionBlock(
          swift,
          'duoyiWidgetBackground',
        );
        final backgroundView = _swiftFunctionBlock(
          swift,
          'duoyiWidgetBackgroundView',
        );

        _expectSourceInOrder(calendarBody, [
          'GeometryReader { proxy in',
          'plannedCalendarBody(availableWidth: Double(proxy.size.width), availableHeight: Double(proxy.size.height))',
          '.duoyiWidgetBackground(entry.theme)',
          '.widgetURL(URL(string: entry.config.deepLink))',
        ]);
        expect(calendarConfig, contains('deepLink: "duoyi://calendar"'));
        expect(
          backgroundHelper,
          contains('self.containerBackground(for: .widget)'),
        );
        expect(backgroundHelper, contains('duoyiWidgetBackgroundView(theme)'));
        expect(
          backgroundHelper,
          contains('self.background(duoyiWidgetBackgroundView(theme))'),
        );
        expect(backgroundView, contains('ContainerRelativeShape()'));
        expect(
          backgroundView,
          contains('.strokeBorder(theme.border, lineWidth: theme.borderWidth)'),
        );
      },
    );

    test(
      'plain glass uses the opaque shared root without an accent alpha endpoint',
      () {
        final glassStyle = _swiftPropertyBlock(
          _swiftTypeBlock(swift, 'DuoyiWidgetTheme'),
          'isGlassStyle',
        );
        expect(glassStyle, contains('brandId == "liquidGlass" && isPlainCard'));
        final baseBackground = _swiftFunctionBlock(
          swift,
          'duoyiWidgetBaseBackground',
        );
        final glassBranch = _swiftCodeBlock(
          baseBackground,
          'if theme.isGlassStyle',
        );
        expect(glassBranch, contains('theme.background'));
        expect(glassBranch, isNot(contains('LinearGradient(')));
        expect(glassBranch, isNot(contains('.opacity(')));
        expect(baseBackground, contains('} else if !theme.isPlainCard {'));
      },
    );

    test('keeps WidgetKit iOS 14 availability and accessory text policy', () {
      final widgetTargetBlocks = RegExp(
        r'IPHONEOS_DEPLOYMENT_TARGET = 14\.0;',
      ).allMatches(project).length;
      expect(widgetTargetBlocks, greaterThanOrEqualTo(3));
      expect(swift, isNot(contains('.foregroundStyle(')));
      expect(
        swift,
        contains('.foregroundColor(entry.theme.readableMutedText)'),
      );
      expect(swift, contains('.foregroundColor(entry.theme.readablePrimary)'));
      final accessoryContent = _swiftPropertyBlock(swift, 'accessoryContent');
      expect(accessoryContent, contains('.lineLimit(1)'));
      expect(accessoryContent, contains('.truncationMode(.tail)'));
      expect(accessoryContent, contains('iOSApplicationExtension 16.0'));
      final todoRow = _swiftFunctionBlock(swift, 'plannedTodoRow');
      final linkedText = _swiftFunctionBlock(swift, 'plannedLinkedText');
      expect(
        todoRow,
        contains('primary ? entry.theme.text : entry.theme.readableMutedText'),
      );
      expect(
        linkedText,
        contains(
          'isPrimary ? entry.theme.text : entry.theme.readableMutedText',
        ),
      );
    });

    test(
      'scaled UIFont metrics measure complete text at actual display scale',
      () {
        final view = _swiftTypeBlock(swift, 'DuoyiWidgetView');
        expect(
          view,
          contains(r'@Environment(\.sizeCategory) private var sizeCategory'),
        );
        expect(
          view,
          contains(r'@Environment(\.displayScale) private var displayScale'),
        );
        final metrics = _swiftTypeBlock(swift, 'DuoyiWidgetTypographyMetrics');
        final categories = _swiftFunctionBlock(metrics, 'contentSizeCategory');
        for (final category in [
          'extraSmall',
          'small',
          'medium',
          'large',
          'extraLarge',
          'extraExtraLarge',
          'extraExtraExtraLarge',
          'accessibilityMedium',
          'accessibilityLarge',
          'accessibilityExtraLarge',
          'accessibilityExtraExtraLarge',
          'accessibilityExtraExtraExtraLarge',
        ]) {
          _expectSourceInOrder(categories, [
            'case .$category:',
            'return .$category',
          ]);
        }
        final category = _swiftPropertyBlock(view, 'uiCategory');
        expect(
          category,
          contains(
            'DuoyiWidgetTypographyMetrics.contentSizeCategory(sizeCategory)',
          ),
        );
        expect(
          _swiftPropertyBlock(view, 'pixelScale'),
          contains('displayScale'),
        );
        final font = _swiftFunctionBlock(metrics, 'font');
        _expectSourceInOrder(font, [
          'UIFont(descriptor: descriptor, size: baseSize)',
          'UITraitCollection(preferredContentSizeCategory: category)',
          'UIFontMetrics(forTextStyle: textStyle).scaledFont(for: baseFont, compatibleWith: traits)',
        ]);
        _expectSourceInOrder(_swiftFunctionBlock(metrics, 'lineHeight'), [
          'let raw = Double(font.lineHeight)',
          'raw.isFinite',
          'roundUp(raw, scale: pixelScale)',
        ]);
        final width = _swiftFunctionBlock(metrics, 'width');
        final wrapped = _swiftFunctionBlock(metrics, 'wrappedHeight');
        for (final member in [width, wrapped]) {
          expect(member, contains('[.font: font]'));
          expect(member, contains('(text as NSString)'));
          expect(member, contains('scale: pixelScale'));
        }
        expect(wrapped, contains('height: .greatestFiniteMagnitude'));
        expect(
          wrapped,
          contains('options: [.usesLineFragmentOrigin, .usesFontLeading]'),
        );
        expect(wrapped, isNot(contains('.prefix(')));
      },
    );

    test(
      'Home Screen renderers draw full text without tail truncation or shrinking',
      () {
        for (final name in [
          'plannedHeaderView',
          'plannedFooterView',
          'plannedNavLink',
          'plannedStandaloneFallbackView',
          'plannedQuickActionButton',
          'plannedTodoRow',
          'plannedLinkedText',
          'plannedHomeBody',
          'plannedCalendarBody',
          'plannedCalendarDayCell',
          'focusClock',
        ]) {
          final member = _swiftFunctionBlock(swift, name);
          for (final forbidden in [
            '.truncationMode(',
            '.minimumScaleFactor(',
            if (name != 'plannedFooterView' && name != 'plannedNavLink')
              '.lineLimit(',
          ]) {
            expect(
              member,
              isNot(contains(forbidden)),
              reason: '$name must draw its admitted complete text.',
            );
          }
        }
        for (final name in ['plannedTodoRow', 'plannedLinkedText']) {
          final member = _swiftFunctionBlock(swift, name);
          expect(
            member,
            contains(
              name == 'plannedTodoRow'
                  ? 'Text(cleanRow(row.title))'
                  : 'Text(title)',
            ),
          );
          expect(member, contains('.font(Font(font))'));
          expect(
            member,
            contains('.fixedSize(horizontal: false, vertical: true)'),
          );
        }
        expect(
          _swiftFunctionBlock(swift, 'plannedNavLink'),
          contains('Text(text)'),
        );
      },
    );

    test(
      'Home Screen passes full measurements to rows and renders original admitted positions',
      () {
        final body = _swiftPropertyBlock(
          _swiftTypeBlock(swift, 'DuoyiWidgetView'),
          'body',
        );
        expect(
          body,
          contains(
            'plannedHomeBody(availableWidth: Double(proxy.size.width), availableHeight: Double(proxy.size.height))',
          ),
        );
        final home = _swiftFunctionBlock(swift, 'plannedHomeBody');
        _expectSourceInOrder(home, [
          'DuoyiWidgetTypographyMetrics.font(',
          'measureHeader(availableWidth: availableWidth, fonts: headerFonts)',
          'cleanRow(first.title)',
          'wrappedHeight(clean, font: primaryFont, availableWidth: usableW, pixelScale: pixelScale)',
          'entry.todoRows.dropFirst().map { row in',
          'cleanRow(row.title)',
          'wrappedHeight(clean, font: secondaryFont, availableWidth: usableW, pixelScale: pixelScale)',
          'entry.rows.map { row in',
          'wrappedHeight(clean, font: secondaryFont, availableWidth: availableWidth, pixelScale: pixelScale)',
          'DuoyiWidgetTypographyLayoutCore.rows(',
          'headerHeight: headerH',
          'primaryHeight: primaryH',
          'secondaryHeights: secondaryH',
          'contentSpacing: contentGap',
          'secondarySpacing: secondaryGap',
          'fallbackHeight: fallbackHeight',
        ]);
        expect(home, contains('primaryKind: entry.config.kind'));
        expect(home, contains('availableWidth: availableWidth'));
        expect(home, contains('availableHeight: availableHeight'));
        expect(home, contains('if plan.showsPrimary'));
        _expectSourceInOrder(home, [
          'if let first = entry.todoRows.first',
          'plannedTodoRow(first, primary: true, primaryFont: primaryFont, secondaryFont: secondaryFont, completionFont: completionFont, completionActionSize: completionActionSize)',
          r'ForEach(plan.visibleSecondaryIndices, id: \.self)',
          'let row = Array(entry.todoRows.dropFirst())[idx]',
          'plannedTodoRow(row, primary: false, primaryFont: primaryFont, secondaryFont: secondaryFont, completionFont: completionFont, completionActionSize: completionActionSize)',
          'let row = entry.rows[idx]',
          'plannedLinkedText(cleanRow(row.title), target: row.target, font: secondaryFont, isPrimary: false)',
        ]);
        expect(
          home,
          contains(
            'plannedLinkedText(cleanRow(entry.primary), target: entry.primaryTarget, font: primaryFont, isPrimary: true)',
          ),
        );
        expect(home, isNot(contains('.sorted(')));
        expect(home, isNot(contains('.filter(')));
        final headerMeasure = _swiftFunctionBlock(swift, 'measureHeader');
        final headerDraw = _swiftFunctionBlock(swift, 'plannedHeaderView');
        final headerFonts = _swiftTypeBlock(swift, 'HeaderFonts');
        for (final role in {
          'title': 'titleFont',
          'count': 'countFont',
          'brand': 'brandFont',
          'quickAction': 'quickActionFont',
        }.entries) {
          expect(headerFonts, contains('let ${role.key}: UIFont'));
          expect(headerMeasure, contains('font: fonts.${role.key}'));
          expect(
            headerDraw,
            contains('let ${role.value} = Font(fonts.${role.key})'),
          );
        }
        for (final name in ['plannedHomeBody', 'plannedCalendarBody']) {
          final member = _swiftFunctionBlock(swift, name);
          final fontArguments = _swiftAssignedCallArguments(
            member,
            'headerFonts',
            'HeaderFonts',
          );
          for (final role in ['title', 'count', 'brand', 'quickAction']) {
            expect(
              fontArguments,
              matches(
                RegExp(
                  '$role:\\s*DuoyiWidgetTypographyMetrics\\.font\\([^)]*category:\\s*uiCategory',
                ),
              ),
            );
          }
          expect(
            member,
            contains(
              'measureHeader(availableWidth: availableWidth, fonts: headerFonts)',
            ),
          );
          expect(
            member,
            contains('plannedHeaderView(mode: headerMode, fonts: headerFonts)'),
          );
        }
        _expectSourceInOrder(headerMeasure, [
          'if totalWithBrand <= availableWidth',
          'if totalNoBrand <= availableWidth',
          'wrappedHeight(entry.config.title, font: fonts.title, availableWidth: titleUsableW, pixelScale: pixelScale)',
          'quickActionW <= availableWidth',
          'wrappedHeight(quickActionTitle, font: fonts.quickAction, availableWidth: quickUsableW, pixelScale: pixelScale)',
          'return (.stacked, totalStackedH)',
        ]);
        expect(headerMeasure, contains('quickTitleW + 12.0'));
        expect(
          headerMeasure,
          contains(
            'lineHeight(fonts.quickAction, pixelScale: pixelScale) + 5.0',
          ),
        );
        expect(headerDraw, contains('switch mode'));
        expect(headerDraw, contains('Text(entry.config.title)'));
        expect(headerDraw, contains('if showsBrand'));
      },
    );

    test(
      'all four complete footer labels determine admission and gated rendering',
      () {
        for (final name in ['plannedHomeBody', 'plannedCalendarBody']) {
          final member = _swiftFunctionBlock(swift, name);
          _expectSourceInOrder(member, [
            'let footerLabels = [entry.navTodo, entry.navHabit, entry.navCalendar, entry.navFocus]',
            r'footerLabels.map { DuoyiWidgetTypographyMetrics.width($0, font: footerFont, pixelScale: pixelScale) }',
            'lineHeight(footerFont, pixelScale: pixelScale) + 6.0',
            'footerLabelWidths: footerWidths',
            'footerHeight: footerH',
            'footerHorizontalPadding: 6.0',
            'footerSpacing: 8.0',
          ]);
          final footerGate = name == 'plannedHomeBody'
              ? 'if plan.showsFooter'
              : 'if rowPlan?.showsFooter == true';
          // Every footer call is inside its gate, after the one measured gap.
          final calls = RegExp(
            r'plannedFooterView\(footerFont: footerFont\)',
          ).allMatches(member).length;
          final gates = RegExp(
            '${RegExp.escape(footerGate)}\\s*\\{\\s*Spacer\\(\\)\\.frame\\(height: CGFloat\\(contentGap\\)\\)\\s*plannedFooterView\\(footerFont: footerFont\\)',
          ).allMatches(member).length;
          expect(calls, greaterThan(0));
          expect(gates, calls);
        }
        final footer = _swiftFunctionBlock(swift, 'plannedFooterView');
        expect(footer, contains('HStack(spacing: 8)'));
        expect(footer, contains('.padding(.vertical, 3)'));
        expect(footer, contains('.padding(.horizontal, 6)'));
        final nav = _swiftFunctionBlock(swift, 'plannedNavLink');
        expect(nav, contains('.font(Font(font))'));
        expect(
          nav,
          contains('.foregroundColor(entry.theme.readableMutedText)'),
        );
      },
    );

    test(
      'calendar measures the same fonts, complete cells and summary used for drawing',
      () {
        final calendar = _swiftFunctionBlock(swift, 'plannedCalendarBody');
        _expectSourceInOrder(calendar, [
          'lineHeight(dayFont, pixelScale: pixelScale)',
          r'DuoyiWidgetTypographyMetrics.width("\($0)", font: dayFont, pixelScale: pixelScale)',
          r'grid.weekdayHeaders.map { DuoyiWidgetTypographyMetrics.width($0, font: weekdayFont, pixelScale: pixelScale) }',
          'max(maxWeekdayW, daySquare)',
          'wrappedHeight(cleanSummaryText, font: summaryFont, availableWidth: availableWidth, pixelScale: pixelScale)',
          'availableHeight - headerH - contentGap',
          'DuoyiWidgetTypographyLayoutCore.calendar(',
          'availableHeight: calendarBodyAvailableH',
          'monthTitleHeight: monthTitleH',
          'weekdayHeaderHeight: weekdayHeaderH',
          'eventSummaryHeight: summaryH',
          'cellHeight: cellH',
          'maximumCellWidth: widestCell',
          'rowSpacing: rowSpacing',
          'contentSpacing: calendarContentSpacing',
          'DuoyiWidgetTypographyLayoutCore.rows(',
          'primaryHeight: calendarPlan?.usedHeight',
        ]);
        expect(calendar, contains('.font(Font(monthFont))'));
        expect(calendar, contains('.font(Font(weekdayFont))'));
        final summary = _swiftCodeBlock(calendar, 'if cPlan.showsEventSummary');
        expect(
          summary,
          contains(
            'plannedLinkedText(cleanSummaryText, target: entry.calendarEventTarget, font: summaryFont, isPrimary: false)',
          ),
        );
        expect(calendar, contains('if !entry.isDailyFresh { return true }'));
        expect(
          calendar,
          contains('if family == .systemSmall { return false }'),
        );
      },
    );

    test('fallback-only row budget draws its fallback before any full header', () {
      final home = _swiftFunctionBlock(swift, 'plannedHomeBody');
      final render = _swiftCodeBlock(
        home,
        'else if let plan = DuoyiWidgetTypographyLayoutCore.rows(',
      );
      final fallback = _swiftCodeBlock(render, 'if plan.usesFallback');
      expect(
        fallback,
        contains(
          'plannedStandaloneFallbackView(font: primaryFont, availableWidth: availableWidth, availableHeight: availableHeight, fits: plan.usedHeight > 0)',
        ),
      );
      for (final forbidden in [
        'plannedHeaderView(',
        'plannedFooterView(',
        'Spacer(',
      ]) {
        expect(fallback, isNot(contains(forbidden)));
      }
      _expectSourceInOrder(render, [
        'if plan.usesFallback',
        'plannedStandaloneFallbackView(font: primaryFont, availableWidth: availableWidth, availableHeight: availableHeight, fits: plan.usedHeight > 0)',
        'if plan.showsPrimary',
        'plannedHeaderView(mode: headerMode, fonts: headerFonts)',
      ]);
    });

    test(
      'fallback keeps the original validated target and hides a rejected visible label',
      () {
        final fallback = _swiftFunctionBlock(
          swift,
          'plannedStandaloneFallbackView',
        );
        _expectSourceInOrder(fallback, [
          'if family == .systemSmall',
          'return widgetRootURL',
          'entry.todoRows.first?.detailURL ?? widgetRootURL',
          'entry.snapshot.actionURL(URLComponents(string: entry.primaryTarget))',
          'if fits',
          'if supportsItemLinks, let url = destinationURL',
          'Link(destination: url)',
        ]);
        final visibleLabel = _swiftCodeBlock(fallback, 'if fits');
        expect(visibleLabel, contains('Text(labelText)'));
        expect(visibleLabel, contains('.font(Font(font))'));
        expect(
          visibleLabel,
          contains('VStack(alignment: .leading, spacing: 0)'),
        );
        expect(
          visibleLabel,
          contains('.accessibilityLabel(accessibleDescription)'),
        );
        expect(
          fallback,
          contains('Content cannot fit at current text size. Open in app'),
        );
        expect(fallback, contains('当前字体大小无法完整显示内容，在应用中打开'));
        final hiddenLabel = _swiftElseBlock(fallback, 'if fits');
        expect(hiddenLabel, isNot(contains('Text(')));
        expect(hiddenLabel, isNot(contains('Link(')));
        expect(hiddenLabel, contains('Color.clear'));
        expect(
          hiddenLabel,
          contains('.accessibilityLabel(accessibleDescription)'),
        );
      },
    );

    test(
      'calendar date fallback does not draw an unbudgeted header or footer',
      () {
        final calendar = _swiftFunctionBlock(swift, 'plannedCalendarBody');
        final fallback = _swiftCodeBlock(
          calendar,
          'else if rowPlan == nil || rowPlan?.usesFallback == true',
        );
        _expectSourceInOrder(
          _swiftCallArguments(fallback, 'plannedStandaloneFallbackView'),
          [
            'font: primaryFont',
            'availableWidth: availableWidth',
            'availableHeight: availableHeight',
            'fits: (rowPlan?.usedHeight ?? 0) > 0',
            'staleHint: staleHint',
          ],
        );
        for (final forbidden in [
          'plannedHeaderView(',
          'plannedFooterView(',
          'Spacer(',
        ]) {
          expect(
            fallback,
            isNot(contains(forbidden)),
            reason:
                'A rejected outer RowPlan counts only its standalone fallback.',
          );
        }
        // A date-only CalendarPlan can retain a header/footer after the outer
        // RowPlan has admitted their complete composition. Its fallback receives
        // the inner body budget rather than the full widget rectangle.
        _expectSourceInOrder(calendar, [
          'DuoyiWidgetTypographyLayoutCore.rows(',
          'headerHeight: headerH',
          'primaryHeight: calendarPlan?.usedHeight',
          'contentSpacing: contentGap',
          'else if rowPlan == nil || rowPlan?.usesFallback == true',
          'else if let cPlan = calendarPlan, !cPlan.showsDateFallback',
        ]);
        final admittedDate = _swiftElseBlock(
          calendar,
          'if let cPlan = calendarPlan, !cPlan.showsDateFallback',
        );
        _expectSourceInOrder(admittedDate, [
          'VStack(alignment: .leading, spacing: 0)',
          'plannedHeaderView(mode: headerMode, fonts: headerFonts)',
          'Spacer().frame(height: CGFloat(contentGap))',
          'plannedStandaloneFallbackView(',
          'availableHeight: calendarBodyAvailableH',
          'fits: (calendarPlan?.usedHeight ?? 0) > 0',
          'staleHint: staleHint',
          'if rowPlan?.showsFooter == true',
          'Spacer().frame(height: CGFloat(contentGap))',
          'plannedFooterView(footerFont: footerFont)',
        ]);
      },
    );

    test(
      'measured content gaps are not duplicated by vertical Spacer children',
      () {
        for (final name in ['plannedHomeBody', 'plannedCalendarBody']) {
          final member = _swiftFunctionBlock(swift, name);
          _expectNoExtraStackSpacer(member, 'VStack', r'CGFloat\(contentGap\)');
          final gate = name == 'plannedHomeBody'
              ? 'if plan.showsPrimary'
              : 'if let cPlan = calendarPlan, !cPlan.showsDateFallback';
          final admitted = _swiftCodeBlock(member, gate);
          _expectSourceInOrder(admitted, [
            'VStack(alignment: .leading, spacing: 0)',
            'plannedHeaderView(mode: headerMode, fonts: headerFonts)',
            'Spacer().frame(height: CGFloat(contentGap))',
            'VStack(alignment: .leading, spacing: 0)',
          ]);
          expect(member, contains('contentSpacing: contentGap'));
        }
        final home = _swiftFunctionBlock(swift, 'plannedHomeBody');
        final primary = _swiftCodeBlock(home, 'if plan.showsPrimary');
        final gapAndIndex = RegExp(
          r'ForEach\(plan\.visibleSecondaryIndices, id: \\\.self\) \{ idx in\s*Spacer\(\)\.frame\(height: CGFloat\(secondaryGap\)\)',
        );
        expect(gapAndIndex.allMatches(primary), hasLength(3));
        expect(home, contains('secondarySpacing: secondaryGap'));
        final calendar = _swiftFunctionBlock(swift, 'plannedCalendarBody');
        final grid = _swiftCodeBlock(
          calendar,
          'if let cPlan = calendarPlan, !cPlan.showsDateFallback',
        );
        _expectSourceInOrder(grid, [
          'Text(grid.monthTitle)',
          'Spacer().frame(height: CGFloat(calendarContentSpacing))',
          'Text(grid.weekdayHeaders[col])',
          'Spacer().frame(height: CGFloat(calendarContentSpacing))',
          'VStack(spacing: CGFloat(rowSpacing))',
        ]);
        _expectSourceInOrder(
          _swiftCodeBlock(grid, 'if cPlan.showsEventSummary'),
          [
            'Spacer().frame(height: CGFloat(calendarContentSpacing))',
            'plannedLinkedText(cleanSummaryText',
          ],
        );
        expect(calendar, contains('contentSpacing: calendarContentSpacing'));
        expect(calendar, contains('rowSpacing: rowSpacing'));
      },
    );

    test('Home geometry rejection uses valid ViewBuilder control flow', () {
      for (final name in ['plannedHomeBody', 'plannedCalendarBody']) {
        final member = _swiftFunctionBlock(swift, name);
        expect(member, contains('availableWidth.isFinite'));
        expect(member, contains('availableHeight.isFinite'));
        expect(member, contains('pixelScale.isFinite'));
        expect(
          _swiftDirectCode(member),
          isNot(matches(RegExp(r'\bguard\b'))),
          reason:
              '$name uses @ViewBuilder; a top-level guard whose else only produces a View cannot exit or build the rejected branch.',
        );
        _expectSourceInOrder(member, [
          'let isValidGeometry = availableWidth.isFinite && availableWidth > 0 &&',
          'availableHeight.isFinite && availableHeight > 0 &&',
          'pixelScale.isFinite && pixelScale > 0',
          'if !isValidGeometry',
        ]);
        final rejected = _swiftCodeBlock(member, 'if !isValidGeometry');
        _expectSourceInOrder(
          _swiftCallArguments(rejected, 'plannedStandaloneFallbackView'),
          [
            'font: primaryFont',
            'availableWidth: 0',
            'availableHeight: 0',
            'fits: false',
          ],
        );
        final admitted = _swiftElseBlock(member, 'if !isValidGeometry');
        expect(
          admitted,
          contains(
            'measureHeader(availableWidth: availableWidth, fonts: headerFonts)',
          ),
        );
        expect(admitted, contains('DuoyiWidgetTypographyLayoutCore.rows('));
        expect(
          _swiftDirectCode(admitted),
          isNot(matches(RegExp(r'\bguard\b'))),
        );
        for (final invalidWork in [
          'measureHeader(',
          'DuoyiWidgetTypographyLayoutCore.rows(',
          'DuoyiWidgetTypographyLayoutCore.calendar(',
          'plannedHeaderView(',
          'plannedFooterView(',
        ]) {
          expect(rejected, isNot(contains(invalidWork)));
          expect(
            _swiftDirectCode(member),
            isNot(contains(invalidWork)),
            reason:
                '$name must keep measurement/planning/rendering inside the admitted geometry branch.',
          );
        }
      }
    });

    test(
      'todo completion uses explicit symbol bounds and exactly the measured gap',
      () {
        final row = _swiftFunctionBlock(swift, 'plannedTodoRow');
        _expectNoExtraStackSpacer(row, 'HStack', '6');
        expect(row, contains('return HStack(spacing: 0)'));
        final completion = _swiftCodeBlock(
          row,
          'if hasCompletion, let completeURL = row.completeURL',
        );
        _expectSourceInOrder(completion, [
          'Spacer().frame(width: 6.0)',
          'Link(destination: completeURL)',
        ]);
        final label = _swiftCodeBlock(row, 'Link(destination: completeURL)');
        expect(label, contains('Image(systemName: "checkmark.circle")'));
        expect(label, contains('.font(Font(completionFont))'));
        expect(
          label,
          contains(
            '.frame(width: completionActionSize.width, height: completionActionSize.height)',
          ),
        );
        expect(label, contains('.contentShape(Rectangle())'));
        final symbol = _swiftFunctionBlock(
          _swiftTypeBlock(swift, 'DuoyiWidgetTypographyMetrics'),
          'symbolActionSize',
        );
        _expectSourceInOrder(symbol, [
          'UIImage.SymbolConfiguration(font: font)',
          'UIImage(systemName: "checkmark.circle", withConfiguration: config)',
          'roundUp(Double(rawSize.width), scale: pixelScale)',
          'roundUp(Double(rawSize.height), scale: pixelScale)',
          'CGSize(width: max(w, 18.0), height: max(h, 18.0))',
        ]);
        final home = _swiftFunctionBlock(swift, 'plannedHomeBody');
        _expectSourceInOrder(home, [
          'DuoyiWidgetTypographyMetrics.symbolActionSize(font: completionFont, pixelScale: pixelScale)',
          'let completionActionWidth = Double(completionActionSize.width)',
          'let completionActionHeight = Double(completionActionSize.height)',
          'let completionGap = 6.0',
        ]);
        expect(
          RegExp(
            r'availableWidth - completionActionWidth - completionGap',
          ).allMatches(home),
          hasLength(2),
        );
        expect(
          RegExp(
            r'max\(textH, hasCompletion \? completionActionHeight : 0\.0\)',
          ).allMatches(home),
          hasLength(2),
        );
        expect(
          RegExp(
            r'plannedTodoRow\([^\n]*completionActionSize: completionActionSize\)',
          ).allMatches(home),
          hasLength(2),
        );
        expect(
          home,
          isNot(contains('availableWidth - completionLineH - completionGap')),
          reason:
              'UIFont line height alone does not measure an SF Symbol width.',
        );
      },
    );

    test('header does not add unmeasured Spacer gaps around required labels', () {
      final header = _swiftFunctionBlock(swift, 'plannedHeaderView');
      _expectNoExtraStackSpacer(header, 'HStack', '6');
      final masked = _swiftMaskedSource(header);
      expect(
        RegExp(r'\bHStack\(spacing: 0\)').allMatches(masked),
        hasLength(3),
      );
      expect(RegExp(r'\bHStack\s*\(').allMatches(masked), hasLength(3));
      expect(header, contains('let gap: CGFloat = 6.0'));
      expect(header, contains('Spacer().frame(width: gap)'));
      expect(header, contains('Spacer().frame(height: 6.0)'));
      final measure = _swiftFunctionBlock(swift, 'measureHeader');
      expect(measure, contains('let gap = 6.0'));
      expect(
        measure,
        contains(
          'let leftW = dotWidth + gap + titleW + (hasCount ? gap + countW : 0.0)',
        ),
      );
      expect(
        measure,
        contains(
          'let rightWithBrandW = brandW + (hasQuickAction ? gap + quickActionW : 0.0)',
        ),
      );
      expect(
        measure,
        contains(
          'let totalWithBrand = leftW + (rightWithBrandW > 0 ? gap + rightWithBrandW : 0.0)',
        ),
      );
      expect(
        measure,
        contains(
          'let totalNoBrand = leftW + (rightNoBrandW > 0 ? gap + rightNoBrandW : 0.0)',
        ),
      );
      expect(measure, contains('let totalStackedH = row1H + 6.0 + row2H'));
      final quick = _swiftFunctionBlock(swift, 'plannedQuickActionButton');
      expect(quick, contains('.font(font)'));
      expect(quick, contains('.padding(.horizontal, 6)'));
      expect(quick, contains('.padding(.vertical, 2.5)'));
    });

    test('calendar day square includes measured two-digit glyph width', () {
      final calendar = _swiftFunctionBlock(swift, 'plannedCalendarBody');
      _expectSourceInOrder(calendar, [
        'let dayLineH = DuoyiWidgetTypographyMetrics.lineHeight(dayFont, pixelScale: pixelScale)',
        r'let maxDayW = (1...31).map { DuoyiWidgetTypographyMetrics.width("\($0)", font: dayFont, pixelScale: pixelScale) }.max()',
        'let daySquare = max(family == .systemSmall ? 13.0 : 15.0, dayLineH, maxDayW)',
        'let cellH = daySquare',
        'let widestCell = max(maxWeekdayW, daySquare)',
        'cellHeight: cellH',
        'maximumCellWidth: widestCell',
        'plannedCalendarDayCell(',
        'cellFont: dayFont',
        'cellHeight: cellH',
      ]);
      expect(
        calendar,
        isNot(
          contains(
            'let cellH = max(family == .systemSmall ? 13.0 : 15.0, dayLineH)',
          ),
        ),
        reason:
            'The rendered day square must cover both actual glyph width and line height.',
      );
    });

    test('calendar summary cleans its visible text before measuring it', () {
      final calendar = _swiftFunctionBlock(swift, 'plannedCalendarBody');
      final raw = _swiftCodeBlock(calendar, 'let rawSummaryText: String =');
      expect(raw, contains('entry.calendarEventSummary'));
      _expectSourceInOrder(calendar, [
        'let cleanSummaryText = cleanRow(rawSummaryText)',
        'wrappedHeight(cleanSummaryText, font: summaryFont, availableWidth: availableWidth, pixelScale: pixelScale)',
        'eventSummaryHeight: summaryH',
        'if cPlan.showsEventSummary',
        'plannedLinkedText(cleanSummaryText, target: entry.calendarEventTarget, font: summaryFont, isPrimary: false)',
      ]);
      final linked = _swiftFunctionBlock(swift, 'plannedLinkedText');
      expect(linked, contains('Text(title)'));
      expect(linked, isNot(contains('cleanRow(')));
      expect(calendar, contains('let staleHint = !entry.isDailyFresh'));
      expect(calendar, contains('.accessibilityHint(staleHint)'));
      expect(
        _swiftCodeBlock(calendar, 'if cPlan.showsEventSummary'),
        isNot(contains('staleHint')),
      );
    });

    test('UIKit metric adapter rejects nonfinite scale and text width', () {
      final metrics = _swiftTypeBlock(swift, 'DuoyiWidgetTypographyMetrics');
      expect(
        _swiftFunctionBlock(metrics, 'roundUp'),
        contains('scale.isFinite'),
      );
      expect(
        _swiftFunctionBlock(metrics, 'roundUp'),
        contains('points.isFinite'),
      );
      expect(
        _swiftFunctionBlock(metrics, 'wrappedHeight'),
        contains('availableWidth.isFinite'),
      );
      expect(
        _swiftFunctionBlock(metrics, 'wrappedHeight'),
        contains('pixelScale.isFinite'),
      );
      expect(
        _swiftFunctionBlock(metrics, 'wrappedHeight'),
        contains('h.isFinite'),
      );
      expect(_swiftFunctionBlock(metrics, 'width'), contains('w.isFinite'));
      final scale = _swiftPropertyBlock(
        _swiftTypeBlock(swift, 'DuoyiWidgetView'),
        'pixelScale',
      );
      _expectSourceInOrder(scale, [
        'let s = Double(displayScale)',
        's.isFinite && s > 0',
        '? s : 2.0',
      ]);
      _expectSourceInOrder(
        _swiftFunctionBlock(metrics, 'contentSizeCategory'),
        [
          '@unknown default:',
          'UITraitCollection.current.preferredContentSizeCategory',
          'current != .unspecified ? current : .large',
        ],
      );
    });

    test(
      'wrapped month title measures full text instead of assuming one line',
      () {
        final calendar = _swiftFunctionBlock(swift, 'plannedCalendarBody');
        expect(
          calendar,
          matches(
            RegExp(
              r'wrappedHeight\(\s*grid\.monthTitle,\s*font:\s*monthFont,\s*availableWidth:\s*availableWidth,\s*pixelScale:\s*pixelScale\)',
            ),
          ),
          reason: 'Text(grid.monthTitle) wraps at the same admitted width.',
        );
        _expectSourceInOrder(calendar, [
          'wrappedHeight(grid.monthTitle',
          'monthTitleHeight: monthTitleH',
          'Text(grid.monthTitle)',
          '.font(Font(monthFont))',
        ]);
      },
    );

    test('live focus clock admission does not use a fixed sample width', () {
      final home = _swiftFunctionBlock(swift, 'plannedHomeBody');
      _expectSourceInOrder(home, [
        'entry.focusTimer.conservativeClockSample(at: entry.date, locale: DuoyiFocusTimerState.timerClockLocale)',
        'width(clockSample, font: focusClockFont, pixelScale: pixelScale)',
        'guard clockW <= availableWidth',
        'lineHeight(focusClockFont, pixelScale: pixelScale)',
        'wrappedHeight(focusStatusLabel, font: focusStatusFont, availableWidth: availableWidth, pixelScale: pixelScale)',
        'return clockH + 4.0 + statusH',
        'primaryHeight: primaryH',
        'focusClock(entry.focusTimer.display(at: entry.date))',
        '.font(Font(focusClockFont))',
        'Spacer().frame(height: 4.0)',
        'Text(focusStatusLabel)',
        '.font(Font(focusStatusFont))',
      ]);
      final timer = _swiftTypeBlock(swift, 'DuoyiFocusTimerState');
      final sample = _swiftFunctionBlock(timer, 'conservativeClockSample');
      _expectSourceInOrder(sample, [
        'switch display(at: date)',
        'case .fallback:',
        'return nil',
        'case .fixed(let clock):',
        'return clock',
        'case .countdown(let end):',
        'end.timeIntervalSince(date)',
        'min(Int64(totalSeconds)',
        'let hours = maxSec / 3600',
        'case .countUp:',
      ]);
      expect(
        sample,
        contains(
          'let maxSec = min(Int64(totalSeconds), max(0, Int64(ceil(remaining))))',
        ),
      );
      expect(
        sample,
        contains('return hours > 0 ? "\\(hours):59:59" : "59:59"'),
      );
      expect(sample, matches(RegExp(r'case \.countUp:\s*return "24:59:59"')));
      expect(timer, contains('countUpCapSeconds: Int64 = 86_400'));
      expect(
        home,
        contains('focusClock(entry.focusTimer.display(at: entry.date))'),
      );
      expect(home, contains('.font(Font(focusClockFont))'));
      expect(
        home,
        contains(
          'wrappedHeight(focusStatusLabel, font: focusStatusFont, availableWidth: availableWidth, pixelScale: pixelScale)',
        ),
      );
      expect(
        home,
        isNot(matches(RegExp(r'width\(\s*"99:59:59"'))),
        reason:
            'Fixed and live timer displays need their full actual supported clock envelope.',
      );
    });

    test('live timer samples have authority for the actual renderer locale', () {
      final view = _swiftTypeBlock(swift, 'DuoyiWidgetView');
      final home = _swiftFunctionBlock(view, 'plannedHomeBody');
      final clock = _swiftFunctionBlock(view, 'focusClock');
      final timer = _swiftTypeBlock(swift, 'DuoyiFocusTimerState');
      expect(
        _swiftAssignedCallArguments(timer, 'timerClockLocale', 'Locale'),
        contains('identifier: "en_US_POSIX"'),
      );
      final sample = _swiftFunctionBlock(
        timer,
        'conservativeClockSample',
        parameterPrefix: 'at date: Date, locale:',
      );
      expect(sample, contains('locale: Locale = timerClockLocale'));
      final rejection = _swiftCodeBlock(
        sample,
        'guard date.timeIntervalSince1970.isFinite,',
      );
      _expectSourceInOrder(rejection, [
        'date <= Date.distantFuture',
        'date >= Date.distantPast',
        'Self.supportsNumericClock(locale: locale)',
        'return nil',
      ]);
      final support = _swiftFunctionBlock(timer, 'supportsNumericClock');
      _expectSourceInOrder(support, [
        'locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()',
        'id == "en-us-posix"',
        'return true',
        'return false',
      ]);
      _expectSourceInOrder(
        _swiftCallArguments(home, 'entry.focusTimer.conservativeClockSample'),
        ['at: entry.date', 'locale: DuoyiFocusTimerState.timerClockLocale'],
      );
      const binding =
          r'.environment(\.locale, DuoyiFocusTimerState.timerClockLocale)';
      for (final text in [
        'Text(clock)',
        'Text(timerInterval: entry.date...end, countsDown: true)',
        'Text(end, style: .timer)',
        'Text(timerInterval: start...cap, countsDown: false)',
        'Text(start, style: .timer)',
      ]) {
        expect(
          _swiftMaskedSource(clock),
          matches(
            RegExp('${RegExp.escape(text)}\\s*${RegExp.escape(binding)}'),
          ),
          reason:
              'Each actual fixed/live Text must receive the same locale used by measurement.',
        );
      }
      expect(
        RegExp(RegExp.escape(binding)).allMatches(_swiftMaskedSource(clock)),
        hasLength(5),
      );
      expect(
        _swiftPropertyBlock(view, 'focusStatusLabel'),
        contains('entry.locale == .en'),
      );
      expect(home, contains('Text(focusStatusLabel)'));
      expect(home, contains('.font(Font(focusStatusFont))'));
    });

    test('stale calendar context survives every fallback accessibility path', () {
      final calendar = _swiftFunctionBlock(swift, 'plannedCalendarBody');
      final helper = _swiftFunctionBlock(
        swift,
        'plannedStandaloneFallbackView',
      );
      expect(calendar, contains('let staleHint = !entry.isDailyFresh'));
      expect(calendar, contains('今日数据待刷新'));
      expect(calendar, contains('Today’s data pending refresh'));
      expect(helper, contains('staleHint: String = ""'));
      final description = _swiftCodeBlock(
        helper,
        'let accessibleDescription: String =',
      );
      expect(
        description,
        contains('guard !staleHint.isEmpty else { return baseDescription }'),
      );
      expect(description, contains(r'"\(staleHint). \(baseDescription)"'));
      expect(description, contains(r'"\(staleHint)，\(baseDescription)"'));
      for (final branch in [
        _swiftCodeBlock(helper, 'if fits'),
        _swiftElseBlock(helper, 'if fits'),
      ]) {
        expect(branch, contains('.accessibilityLabel(accessibleDescription)'));
        expect(
          branch,
          contains('.accessibilityHint(staleHint)'),
          reason:
              'Visible and invisible fallback containers must expose the stale state.',
        );
      }
      for (final branch in [
        _swiftCodeBlock(calendar, 'if !isValidGeometry'),
        _swiftCodeBlock(calendar, 'if case .overflow = headerMode'),
        _swiftCodeBlock(
          calendar,
          'else if rowPlan == nil || rowPlan?.usesFallback == true',
        ),
        _swiftElseBlock(
          calendar,
          'if let cPlan = calendarPlan, !cPlan.showsDateFallback',
        ),
      ]) {
        expect(
          _swiftCallArguments(branch, 'plannedStandaloneFallbackView'),
          contains('staleHint: staleHint'),
          reason:
              'Each actual fallback call must carry pending-refresh state, including rejected geometry.',
        );
      }
      expect(
        RegExp(
          r'plannedStandaloneFallbackView\(',
        ).allMatches(_swiftMaskedSource(calendar)),
        hasLength(4),
      );
    });

    test('Flutter side enables iOS home_widget updates', () {
      expect(service, contains('PlatformInfo.isAndroid || PlatformInfo.isIOS'));
      expect(service, contains('HomeWidget.setAppGroupId(_appGroupId)'));
      expect(service, contains('HomeWidget.initiallyLaunchedFromHomeWidget()'));
      expect(service, contains('HomeWidget.widgetClicked'));
    });

    test('exposes WidgetKit deep links for quick actions and footer navigation', () {
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
          '_navigateWidgetSection(state, ctx, 1);',
          'TodayDetailRouter.open(ctx, TodaySectionKind.todos, id: id)',
          "action == 'quick_todo'",
          "action == 'complete_todo'",
        ],
        'DuoyiFocusWidget': [
          "action == 'start_pomodoro'",
          '_navigateWidgetSection(state, ctx, 4);',
          'pomodoro.startIfIdle()',
          'WidgetActionNotice.focusRunning',
        ],
        'DuoyiHabitWidget': [
          "uri.host == 'habit'",
          '_navigateWidgetSection(state, ctx, 2);',
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
          '_pushHiddenWidgetFallbackRoute(ctx, const GoalScreen(), access)',
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

      expect(
        _swiftFunctionBlock(swift, 'plannedHeaderView'),
        contains(
          'plannedQuickActionButton(font: quickActionFont, quickURL: quickURL)',
        ),
      );
      expect(
        _swiftFunctionBlock(swift, 'plannedQuickActionButton'),
        contains('Link(destination: quickURL)'),
      );
      expect(
        _swiftFunctionBlock(swift, 'plannedNavLink'),
        contains('Link(destination: url)'),
      );
      final footer = _swiftFunctionBlock(swift, 'plannedFooterView');
      for (final destination in {
        'Todo': 'todo',
        'Habit': 'habit',
        'Calendar': 'calendar',
        'Focus': 'focus',
      }.entries) {
        expect(
          footer,
          contains(
            'plannedNavLink(entry.nav${destination.key}, "duoyi://${destination.value}", font: footerFont)',
          ),
        );
      }
      final entryBlock = _swiftFunctionBlock(
        swift,
        'entry',
        parameterPrefix: 'capture:',
      );
      const navPayloadFields = {
        'navTodo': 'nav_todo',
        'navHabit': 'nav_habit',
        'navCalendar': 'nav_calendar',
        'navFocus': 'nav_focus',
      };
      for (final mapping in navPayloadFields.entries) {
        final labelBlock = entryBlock.substring(
          entryBlock.indexOf('let ${mapping.key} ='),
          entryBlock.indexOf(
            '\n        )',
            entryBlock.indexOf('let ${mapping.key} ='),
          ),
        );
        expect(labelBlock, contains('localizedNavigationLabel('));
        expect(
          labelBlock,
          contains('readString(defaults, key: "${mapping.value}"'),
        );
        expect(labelBlock, contains('locale: locale'));
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
      final home = _swiftFunctionBlock(swift, 'plannedHomeBody');
      _expectSourceInOrder(home, [
        r'ForEach(plan.visibleSecondaryIndices, id: \.self)',
        'let row = Array(entry.todoRows.dropFirst())[idx]',
        'plannedTodoRow(row, primary: false',
      ]);
      expect(
        _swiftFunctionBlock(swift, 'plannedTodoRow'),
        contains('Image(systemName: "checkmark.circle")'),
      );
      expect(swift, isNot(contains('Text("完成")')));
      expect(swift, isNot(contains('duoyi://action/start_focus')));

      final main = File('lib/main.dart').readAsStringSync();
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
        contains('_navigateWidgetSection(state, ctx, idx);'),
        reason:
            'WidgetKit footer links must keep hidden bottom-nav destinations reachable.',
      );
      final sectionNavigation = main.substring(
        main.indexOf('void _navigateWidgetSection('),
        main.indexOf('void _routeHydratedWidgetUri('),
      );
      expect(
        sectionNavigation,
        contains('state.navigateTo(index, allowHidden: true);'),
      );
      expect(sectionNavigation, contains('context != null && context.mounted'));
      expect(
        sectionNavigation,
        contains('_widgetCalendarRoutes.showSection(Navigator.of(context));'),
      );
    });

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
        contains('for context in connectionOptions.urlContexts'),
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
  final masked = _swiftMaskedSource(swift);
  final match = _uniqueSwiftMatch(
    masked,
    RegExp(
      '^[ \\t]*private[ \\t]+let[ \\t]+${RegExp.escape(configName)}\\b[ \\t]*=[ \\t]*DuoyiWidgetConfig[ \\t]*\\(',
      multiLine: true,
    ),
    'widget config $configName',
  );
  final opening = masked.indexOf('(', match.start);
  return swift.substring(match.start, _swiftDelimiterEnd(swift, opening));
}

String _swiftAssignedCallArguments(
  String member,
  String variable,
  String callee,
) {
  final masked = _swiftMaskedSource(member);
  final match = _uniqueSwiftMatch(
    masked,
    RegExp(
      '\\blet\\s+${RegExp.escape(variable)}\\s*=\\s*${RegExp.escape(callee)}\\s*\\(',
    ),
    '$callee arguments assigned to $variable',
  );
  final opening = match.end - 1;
  final end = _swiftDelimiterEnd(member, opening);
  return member.substring(opening + 1, end - 1);
}

String _swiftCallArguments(String member, String callee) {
  final masked = _swiftMaskedSource(member);
  final match = _uniqueSwiftMatch(
    masked,
    RegExp('\\b${RegExp.escape(callee)}\\s*\\('),
    'call to $callee',
  );
  final opening = match.end - 1;
  return member.substring(opening + 1, _swiftDelimiterEnd(member, opening) - 1);
}

void _expectSmallSingleObjectCap(String swift, String kind) {
  final rows = _swiftFunctionBlock(
    _swiftTypeBlock(swift, 'DuoyiWidgetTypographyLayoutCore'),
    'rows',
  );
  _expectSourceInOrder(rows, [
    'if familyKind == "systemSmall" && [',
    '"$kind"',
    '].contains(primaryKind)',
    'return 0',
  ]);
}

String _swiftFunctionBlock(
  String swift,
  String functionName, {
  String? parameterPrefix,
}) {
  final parameters = parameterPrefix == null
      ? r'\('
      : parameterPrefix.isEmpty
      ? r'\(\s*\)'
      : '\\(\\s*${RegExp.escape(parameterPrefix)}';
  return _swiftDeclarationBlock(
    swift,
    'func',
    functionName,
    '(?=[ \\t]*$parameters)',
  );
}

String _swiftPropertyBlock(String swift, String propertyName) =>
    _swiftDeclarationBlock(swift, 'var', propertyName, r'(?=[ \t]*[:{])');

String _swiftTypeBlock(String swift, String typeName) => _swiftDeclarationBlock(
  swift,
  '(?:struct|enum|class)',
  typeName,
  r'(?=[ \t]*[:{<])',
);

String _swiftDeclarationBlock(
  String swift,
  String kind,
  String name,
  String suffix,
) {
  final masked = _swiftMaskedSource(swift);
  final match = _uniqueSwiftMatch(
    masked,
    RegExp(
      '^[ \\t]*(?:(?:private|fileprivate|public|internal|static|final|override|mutating|nonmutating)[ \\t]+)*$kind[ \\t]+${RegExp.escape(name)}$suffix',
      multiLine: true,
    ),
    '$kind $name',
  );
  var afterSignature = match.end;
  if (kind == 'func') {
    afterSignature = _swiftDelimiterEnd(swift, masked.indexOf('(', match.end));
  }
  final opening = masked.indexOf('{', afterSignature);
  if (opening < 0 ||
      RegExp(
        r'\b(?:func|var|let|struct|enum|class)\b',
      ).hasMatch(masked.substring(afterSignature, opening))) {
    throw StateError('Missing bounded Swift body for $kind $name');
  }
  return swift.substring(match.start, _swiftDelimiterEnd(swift, opening));
}

RegExpMatch _uniqueSwiftMatch(
  String masked,
  RegExp pattern,
  String description,
) {
  final matches = pattern.allMatches(masked).toList();
  if (matches.length != 1) {
    throw StateError(
      'Expected one Swift $description; found ${matches.length}',
    );
  }
  return matches.single;
}

String _swiftCodeBlock(String swift, String marker) {
  final bounds = _swiftCodeBlockBounds(swift, marker);
  return swift.substring(bounds.$1, bounds.$2);
}

(int, int) _swiftCodeBlockBounds(String swift, String marker) {
  final masked = _swiftMaskedSource(swift);
  final starts = RegExp(RegExp.escape(marker))
      .allMatches(swift)
      .where((match) => masked[match.start].trim().isNotEmpty)
      .toList();
  if (starts.length != 1) {
    throw StateError(
      'Expected one Swift code block $marker; found ${starts.length}',
    );
  }
  final opening = masked.indexOf('{', starts.single.end);
  if (opening < 0) throw StateError('Missing Swift code block body $marker');
  return (starts.single.start, _swiftDelimiterEnd(swift, opening));
}

String _swiftElseBlock(String swift, String ifMarker) {
  final afterIf = _swiftCodeBlockBounds(swift, ifMarker).$2;
  final masked = _swiftMaskedSource(swift);
  final match = RegExp(r'^\s*else\s*\{').firstMatch(masked.substring(afterIf));
  if (match == null) {
    throw StateError('Missing direct Swift else for $ifMarker');
  }
  final start = masked.indexOf('else', afterIf);
  final opening = masked.indexOf('{', start);
  return swift.substring(start, _swiftDelimiterEnd(swift, opening));
}

void _expectNoExtraStackSpacer(
  String swift,
  String stackName,
  String spacingPattern,
) {
  final masked = _swiftMaskedSource(swift);
  final stacks = RegExp(
    '\\b${RegExp.escape(stackName)}\\s*\\([^{}]*?\\bspacing\\s*:\\s*$spacingPattern\\s*\\)',
  ).allMatches(masked);
  for (final stack in stacks) {
    final opening = masked.indexOf('{', stack.end);
    if (opening < 0 || masked.substring(stack.end, opening).trim().isNotEmpty) {
      throw StateError('Missing bounded Swift $stackName body');
    }
    final end = _swiftDelimiterEnd(swift, opening);
    // Only direct children add this stack's gaps. Ignore nested child bodies,
    // where a horizontal or independently budgeted Spacer can be legitimate.
    final direct = masked.substring(opening + 1, end - 1).codeUnits.toList();
    var depth = 0;
    for (var index = opening + 1; index < end - 1; index++) {
      final character = masked[index];
      if (character == '{') depth++;
      if (depth > 0 && character != '\n' && character != '\r') {
        direct[index - opening - 1] = 32;
      }
      if (character == '}') depth--;
    }
    expect(
      String.fromCharCodes(direct),
      isNot(matches(RegExp(r'\bSpacer\s*\('))),
      reason:
          '$stackName inserts a gap on both sides of Spacer beyond the measured content spacing.',
    );
  }
}

String _swiftDirectCode(String swift) {
  final masked = _swiftMaskedSource(swift);
  final opening = masked.indexOf('{');
  final end = _swiftDelimiterEnd(swift, opening);
  final direct = masked.codeUnits.toList();
  var depth = 0;
  for (var index = 0; index < direct.length; index++) {
    final character = masked[index];
    if (index > opening && index < end - 1 && character == '{') depth++;
    final outsideBody = index <= opening || index >= end - 1;
    if ((outsideBody || depth > 0) && character != '\n' && character != '\r') {
      direct[index] = 32;
    }
    if (index > opening && index < end - 1 && character == '}') depth--;
  }
  return String.fromCharCodes(direct);
}

// Keep indices while excluding comments/literals from declaration matching.
// Delimiters handle nested Swift comments and interpolated/raw/multiline strings.
String _swiftMaskedSource(String swift) {
  final masked = swift.codeUnits.toList();
  for (var index = 0; index < swift.length;) {
    final end = _swiftNonCodeEnd(swift, index);
    if (end == index) {
      index++;
      continue;
    }
    for (var cursor = index; cursor < end; cursor++) {
      if (masked[cursor] != 10 && masked[cursor] != 13) masked[cursor] = 32;
    }
    index = end;
  }
  return String.fromCharCodes(masked);
}

int _swiftNonCodeEnd(String swift, int start) {
  if (swift.startsWith('//', start)) {
    final end = swift.indexOf('\n', start + 2);
    return end < 0 ? swift.length : end;
  }
  if (swift.startsWith('/*', start)) {
    var depth = 1;
    var cursor = start + 2;
    while (cursor < swift.length && depth > 0) {
      if (swift.startsWith('/*', cursor)) {
        depth++;
        cursor += 2;
      } else if (swift.startsWith('*/', cursor)) {
        depth--;
        cursor += 2;
      } else {
        cursor++;
      }
    }
    if (depth != 0) throw StateError('Unterminated Swift comment at $start');
    return cursor;
  }
  var quote = start;
  while (quote < swift.length && swift[quote] == '#') {
    quote++;
  }
  if (quote >= swift.length || swift[quote] != '"') return start;
  final hashes = List.filled(quote - start, '#').join();
  final quotes = swift.startsWith('"""', quote) ? '"""' : '"';
  final terminator = '$quotes$hashes';
  final escape = '\\$hashes';
  var cursor = quote + quotes.length;
  while (cursor < swift.length) {
    if (swift.startsWith(terminator, cursor)) return cursor + terminator.length;
    if (swift.startsWith(escape, cursor)) {
      cursor += escape.length;
      if (cursor < swift.length && swift[cursor] == '(') {
        cursor = _swiftDelimiterEnd(swift, cursor);
      } else {
        cursor++;
      }
    } else {
      cursor++;
    }
  }
  throw StateError('Unterminated Swift string at $start');
}

int _swiftDelimiterEnd(String swift, int opening) {
  const pairs = {'(': ')', '[': ']', '{': '}'};
  if (opening < 0 ||
      opening >= swift.length ||
      !pairs.containsKey(swift[opening])) {
    throw StateError('Missing Swift opening delimiter at $opening');
  }
  final stack = <String>[pairs[swift[opening]]!];
  var cursor = opening + 1;
  while (cursor < swift.length) {
    final nonCodeEnd = _swiftNonCodeEnd(swift, cursor);
    if (nonCodeEnd != cursor) {
      cursor = nonCodeEnd;
      continue;
    }
    final character = swift[cursor];
    if (pairs.containsKey(character)) {
      stack.add(pairs[character]!);
    } else if (pairs.values.contains(character)) {
      if (stack.last != character) {
        throw StateError('Mismatched Swift delimiter at $cursor');
      }
      stack.removeLast();
      if (stack.isEmpty) return cursor + 1;
    }
    cursor++;
  }
  throw StateError('Unterminated Swift delimiter at $opening');
}

void _expectSourceInOrder(String source, List<String> fragments) {
  var previousIndex = -1;
  for (final fragment in fragments) {
    final index = source.indexOf(fragment, previousIndex + 1);
    expect(
      index,
      greaterThan(previousIndex),
      reason: 'Expected source fragment in order: $fragment',
    );
    previousIndex = index;
  }
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

// BEGIN IOS FOCUS ACCESSORY POLICY 2297 HELPERS
// Finite source-policy controls for frozen Swift a815e896... and review2281.
// No model simulation and no Apple host fit/VoiceOver/runtime acceptance.
const _iosFocus2297Properties = <String>[
  'accessoryContent', 'accessoryFocusDisplay', 'accessoryFocusSFSymbol',
  'accessoryFocusDirectionStatus', 'accessoryFocusIsBuiltInLabel',
  'accessoryFocusRectangularStatusText', 'accessoryFocusShortStatus',
  'accessoryFocusCompactCue', 'accessoryFocusCircularStatusText',
  'accessoryFocusRecoveryTitle', 'accessoryFocusRecoveryCompactTitle',
  'accessoryFocusRecoveryHint', 'accessoryFocusAccessibleDescriptionPrefix',
  'isAccessoryFamily', 'widgetRootURL', 'focusStatusLabel',
];
const _iosFocus2297Functions = <String>[
  'accessoryFocusInlineView', 'accessoryFocusRectangularBody',
  'accessoryFocusCircularBody', 'accessoryFocusAccessibilityText',
  'accessoryMeasuredSymbolSize', 'accessoryFitsInCircle', 'focusClock',
];

String _iosFocus2297Member(String swift, String name) {
  final view = _swiftTypeBlock(swift, 'DuoyiWidgetView');
  if (_iosFocus2297Properties.contains(name)) {
    return _swiftPropertyBlock(view, name);
  }
  if (_iosFocus2297Functions.contains(name)) {
    return _swiftFunctionBlock(view, name);
  }
  throw StateError('2297 unbound member: $name');
}

// Reuses the original masked, balanced extractor. Only direct switch cases
// delimit each family/clock arm; nested cases cannot impersonate a caller.
String _iosFocus2297Case(String switchBlock, String label) {
  final direct = _swiftDirectCode(switchBlock);
  final cases = RegExp(r'^[ \t]*(?:case\b[^\n]*:|default:)', multiLine: true)
      .allMatches(direct).toList();
  final selected = cases.where((m) => m.group(0)!.trim() == label).toList();
  if (selected.length != 1) {
    throw StateError('2297 bounded switch case missing/ambiguous: $label');
  }
  final index = cases.indexOf(selected.single);
  final end = index + 1 < cases.length ? cases[index + 1].start
      : _swiftDelimiterEnd(switchBlock, _swiftMaskedSource(switchBlock).indexOf('{')) - 1;
  return switchBlock.substring(selected.single.end, end);
}

// Exact frozen-revision fragments must begin in executable source, never in
// a comment/string decoy. Literal contents remain part of the expected policy.
List<RegExpMatch> _iosFocus2297Active(String source, String fragment) {
  final masked = _swiftMaskedSource(source);
  return RegExp(RegExp.escape(fragment)).allMatches(source)
      .where((m) => masked[m.start].trim().isNotEmpty).toList();
}

String _iosFocus2297Replace(
  String swift, String memberName, String before, String after,
) {
  final member = memberName == 'circular-text-arm'
      ? _iosFocus2297Case(_swiftCodeBlock(_swiftCodeBlock(
          _iosFocus2297Member(swift, 'accessoryFocusCircularBody'),
          'if let clockLayout = admittedClockLayout'), 'switch clockLayout'),
          'case .textAndClock(let clockFont):')
      : _iosFocus2297Member(swift, memberName);
  final anchors = _iosFocus2297Active(member, before);
  if (anchors.length != 1) {
    throw StateError('2297 counterexample needs one active anchor: $memberName');
  }
  final copies = RegExp(RegExp.escape(member)).allMatches(swift).toList();
  if (copies.length != 1) throw StateError('2297 member source is not unique');
  final start = copies.single.start + anchors.single.start;
  return swift.replaceRange(start, start + before.length, after);
}

Map<String, Set<String>> _iosFocus2297Policy(String swift) {
  // Structural extraction failures deliberately throw, rather than counting
  // malformed syntax or an unrelated parser error as a rejected policy case.
  final members = <String, String>{
    for (final name in [..._iosFocus2297Properties, ..._iosFocus2297Functions])
      name: _iosFocus2297Member(swift, name),
  };
  final result = <String, Set<String>>{
    'entry': <String>{}, 'presentation': <String>{},
  };
  void require(String group, String id, String source, List<String> fragments) {
    if (fragments.any((f) => _iosFocus2297Active(source, f).isEmpty)) {
      result[group]!.add(id);
    }
  }
  void call(String group, String id, String source, String callee, String args) {
    final masked = _swiftMaskedSource(source);
    final found = RegExp(r'\b' + RegExp.escape(callee) + r'\s*\(')
        .allMatches(masked).toList();
    if (found.length != 1) {
      result[group]!.add(id);
      return;
    }
    final actual = _swiftCallArguments(source, callee)
        .replaceAll(RegExp(r'\s+'), '');
    if (actual != args.replaceAll(RegExp(r'\s+'), '')) {
      result[group]!.add(id);
    }
  }
  const entry = 'entry';
  const presentation = 'presentation';
  final view = _swiftTypeBlock(swift, 'DuoyiWidgetView');
  final body = _swiftPropertyBlock(view, 'body');
  final root = _swiftCodeBlock(body, 'if isAccessoryFamily');
  require(entry, 'accessory-root', root, [
    'accessoryContent', '.widgetURL(widgetRootURL)',
  ]);
  final rootCode = _swiftDirectCode(root);
  if (!RegExp(r'\baccessoryContent\b').hasMatch(rootCode)) {
    result[entry]!.add('accessory-root');
  }
  require(entry, 'focus-module-root', members['widgetRootURL']!, [
    'let moduleURL = URL(string: entry.config.deepLink)',
  ]);
  require(entry, 'focus-module-root', _swiftConfigBlock(swift, 'focusConfig'), [
    'deepLink: "duoyi://focus"',
  ]);
  require(entry, 'family-availability', members['isAccessoryFamily']!, [
    'if #available(iOSApplicationExtension 16.0, *)',
    'case .accessoryInline, .accessoryCircular, .accessoryRectangular:',
    'return true', 'return false',
  ]);
  final content = members['accessoryContent']!;
  require(entry, 'family-availability', content, [
    'if #available(iOSApplicationExtension 16.0, *)',
  ]);
  final familySwitch = _swiftCodeBlock(content, 'switch family');
  final familyBranches = <String, String>{
    for (final family in ['Inline', 'Circular', 'Rectangular'])
      family: _iosFocus2297Case(familySwitch, 'case .accessory$family:'),
  };
  for (final branch in familyBranches.entries) {
    final focus = _swiftCodeBlock(branch.value, 'if let focusDisplay = accessoryFocusDisplay');
    final family = branch.key.toLowerCase();
    if (branch.key == 'Inline') {
      call(entry, 'inline-entry-call', focus, 'accessoryFocusInlineView', 'focusDisplay');
      if (!RegExp(r'^\s*accessoryFocusInlineView\s*\(\s*focusDisplay\s*\)',
          multiLine: true).hasMatch(_swiftDirectCode(focus))) {
        result[entry]!.add('inline-entry-call');
      }
    } else {
      final geometry = _swiftCodeBlock(focus, 'GeometryReader');
      call(entry, '$family-entry-call', geometry,
        'accessoryFocus${branch.key}Body',
        'display: focusDisplay, availableWidth: Double(proxy.size.width), '
        'availableHeight: Double(proxy.size.height)');
      require(entry, '$family-actual-geometry', geometry, [
        'GeometryReader { proxy in',
      ]);
    }
  }
  require(entry, 'display-authority', members['accessoryFocusDisplay']!, [
    'guard entry.config.kind == "DuoyiFocusWidget" else { return nil }',
    'let display = entry.focusTimer.display(at: entry.date)',
    'return display == .fallback ? nil : display',
  ]);
  call(entry, 'display-authority', members['accessoryFocusDisplay']!,
    'entry.focusTimer.display', 'at: entry.date');

  final inline = members['accessoryFocusInlineView']!;
  final rectangular = members['accessoryFocusRectangularBody']!;
  final circular = members['accessoryFocusCircularBody']!;
  final inlineClock = _swiftCodeBlock(inline,
    'if fitsFullClockAndStatus || fitsCompactClockAndCue || fitsClockOnly');
  final inlineSwitch = _swiftCodeBlock(inlineClock, 'switch display');
  final fixed = _iosFocus2297Case(inlineSwitch, 'case .fixed(let clock):');
  final countdown = _iosFocus2297Case(inlineSwitch, 'case .countdown(let end):');
  final countUp = _iosFocus2297Case(inlineSwitch, 'case .countUp(let start, let cap):');
  require(entry, 'inline-fixed-complete', fixed, [
    r'Text(verbatim: trailingStatus.isEmpty ? clock : "\(clock) · \(trailingStatus)")',
  ]);
  require(entry, 'inline-countdown-canonical', countdown, [
    'Text(timerInterval: entry.date...end, countsDown: true)',
    r'Text("\(Text(timerInterval: entry.date...end, countsDown: true)) · \(trailingStatus)")',
  ]);
  require(entry, 'inline-countup-canonical', countUp, [
    'Text(timerInterval: start...cap, countsDown: false)',
    r'Text("\(Text(timerInterval: start...cap, countsDown: false)) · \(trailingStatus)")',
  ]);
  final rectClock = _swiftCodeBlock(rectangular, 'if let clockFont = selectedClockFont');
  call(entry, 'rectangular-clock', rectClock, 'focusClock', 'display');
  final circleClock = _swiftCodeBlock(circular, 'if let clockLayout = admittedClockLayout');
  final circleSwitch = _swiftCodeBlock(circleClock, 'switch clockLayout');
  final circleText = _iosFocus2297Case(circleSwitch, 'case .textAndClock(let clockFont):');
  final circleSymbol = _iosFocus2297Case(circleSwitch, 'case .symbolAndClock(let clockFont):');
  call(entry, 'circular-text-clock', circleText, 'focusClock', 'display');
  call(entry, 'circular-symbol-clock', circleSymbol, 'focusClock', 'display');

  // New renderer/display helpers may not introduce a second timer authority,
  // publication channel or interactive action. Old provider/other-kind code
  // and the shared pre-iOS16 .timer arms are outside this local prohibition.
  for (final name in [
    ..._iosFocus2297Functions.where((n) => n != 'focusClock'),
    ..._iosFocus2297Properties.where((n) => n.startsWith('accessoryFocus')),
  ]) {
    if (RegExp(
      r'\b(?:UserDefaults|Date|Timer|TimelineView|Link|Button)\s*[\.(]'
      r'|\b(?:reloadAllTimelines|reloadTimelines|resolve|widgetURL)\s*\(',
    ).hasMatch(_swiftMaskedSource(members[name]!))) {
      result[entry]!.add('focus-side-effects');
    }
  }
  for (final numeric in [fixed, countdown, countUp, rectClock, circleText, circleSymbol]) {
    if (RegExp(r'\b(?:accessoryShortText|accessoryPrimaryText|formatMinutes|focusTimerRemainingSeconds)\b'
        r'|\b(?:prefix|minimumScaleFactor)\s*\('
        r'|\bentry\.primary\b').hasMatch(_swiftMaskedSource(numeric))) {
      result[entry]!.add('complete-numeric-path');
    }
  }

  const sampleArgs = 'at: entry.date, locale: DuoyiFocusTimerState.timerClockLocale';
  for (final renderer in [inline, rectangular, circular]) {
    call(presentation, 'sample-authority', renderer,
      'entry.focusTimer.conservativeClockSample', sampleArgs);
  }
  final timer = _swiftTypeBlock(swift, 'DuoyiFocusTimerState');
  require(presentation, 'numeric-posix', _swiftAssignedCallArguments(
    timer, 'timerClockLocale', 'Locale'), ['identifier: "en_US_POSIX"']);

  final inlineFont = _swiftAssignedCallArguments(inline, 'inlineFont',
    'DuoyiWidgetTypographyMetrics.font');
  require(presentation, 'inline-font', 'font($inlineFont)', [
    'baseSize: 12.0', 'weight: .semibold', 'textStyle: .caption2',
    'category: uiCategory', 'rounded: false', 'monospacedDigits: true',
  ]);
  require(presentation, 'inline-nominal148', inline, [
    'let inlineMaxWidth: Double = 148.0',
  ]);
  for (final gate in ['fitsFullClockAndStatus', 'fitsCompactClockAndCue', 'fitsClockOnly']) {
    final block = _swiftCodeBlock(inline, 'let $gate: Bool =');
    require(presentation, 'inline-complete-sample-fit', block, [
      'guard let sample = clockSample else { return false }',
      'font: inlineFont, pixelScale: pixelScale',
      'return w.isFinite && w > 0 && w <= inlineMaxWidth',
    ]);
  }
  require(presentation, 'inline-complete-sample-fit',
    _swiftCodeBlock(inline, 'let fitsClockOnly: Bool ='), [
      'width(sample, font: inlineFont, pixelScale: pixelScale)',
    ]);
  call(presentation, 'inline-complete-sample-fit',
    _swiftCodeBlock(inline, 'let fitsFullClockAndStatus: Bool ='),
    'DuoyiWidgetTypographyMetrics.width',
    r'"\(sample) · \(fullPrefix)", font: inlineFont, pixelScale: pixelScale');
  call(presentation, 'inline-complete-sample-fit',
    _swiftCodeBlock(inline, 'let fitsCompactClockAndCue: Bool ='),
    'DuoyiWidgetTypographyMetrics.width',
    r'"\(sample) · \(compactCue)", font: inlineFont, pixelScale: pixelScale');
  final recoverySelector = _swiftCodeBlock(inline, 'let recoveryLabel: String? =');
  require(presentation, 'inline-admitted-or-empty', recoverySelector, [
    'fullRecoveryLabel,', 'accessoryFocusRecoveryTitle,',
    'compactRecoveryLabel,', 'accessoryFocusRecoveryCompactTitle',
    'width(candidate, font: inlineFont, pixelScale: pixelScale)',
    'if w.isFinite && w > 0 && w <= inlineMaxWidth',
    'return candidate', 'return nil',
  ]);
  final inlineRecovery = _swiftCodeBlock(inline, 'else if let admittedRecovery = recoveryLabel');
  final inlineEmpty = _swiftElseBlock(inline, 'else if let admittedRecovery = recoveryLabel');
  require(presentation, 'inline-admitted-or-empty', inlineRecovery, [
    'Text(verbatim: admittedRecovery)', '.font(Font(inlineFont))',
  ]);
  require(presentation, 'inline-admitted-or-empty', inlineEmpty, [
    'Text(verbatim: "")', '.accessibilityElement(children: .ignore)',
  ]);
  require(presentation, 'inline-drawn-font', inlineClock, ['.font(Font(inlineFont))']);

  require(presentation, 'rectangular-header-status-metric', rectangular, [
    'width(entry.config.title, font: headerFont, pixelScale: pixelScale)',
    'lineHeight(headerFont, pixelScale: pixelScale)',
    'accessoryMeasuredSymbolSize(name: accessoryFocusSFSymbol, font: headerSymbolFont)',
    'guard isValidGeometry, let s = headerSymbolSize else { return false }',
    '(Double(s.width) + 4.0 + headerTitleW) <= availableWidth',
    'lineHeight(statusFont, pixelScale: pixelScale)',
  ]);
  require(presentation, 'rectangular-recovery-fit',
    _swiftCodeBlock(rectangular, 'let recoveryCandidates:'), [
      'guard isValidGeometry else { return [] }',
      'for baseSize in [12.0, 11.0, 10.0] as [CGFloat]',
      'baseSize: baseSize', 'textStyle: .caption2', 'category: uiCategory',
      'candidates.append((f, recoveryFullText))',
      'candidates.append((f, accessoryFocusRecoveryTitle))',
      'candidates.append((f, accessoryFocusRecoveryCompactTitle))',
    ]);
  final rectAdmission = _swiftCodeBlock(rectangular, 'let selectedClockFont: UIFont? =');
  require(presentation, 'rectangular-geometry', rectangular, [
    'let isValidGeometry = availableWidth.isFinite && availableHeight.isFinite &&',
    'availableWidth > 0 && availableHeight > 0',
  ]);
  require(presentation, 'rectangular-clock-metric', rectAdmission, [
    'guard isValidGeometry,', 'let sample = clockSample,',
    'headerTitleW <= availableWidth', 'headerH > 0,', 'statusH > 0',
    'for baseSize in [16.0, 14.0, 12.0, 11.0] as [CGFloat]',
    'baseSize: baseSize', 'textStyle: .subheadline', 'category: uiCategory',
    'rounded: true', 'monospacedDigits: true',
    'width(sample, font: font, pixelScale: pixelScale)',
    'lineHeight(font, pixelScale: pixelScale)',
    'let totalH = headerH + rowSpacing + clockH + rowSpacing + statusH',
    'clockW <= availableWidth', 'totalH <= availableHeight', 'return font', 'return nil',
  ]);
  require(presentation, 'rectangular-drawn-font', rectClock, [
    'focusClock(display)', '.font(Font(clockFont))',
    'Text(verbatim: entry.config.title)', '.font(Font(headerFont))',
    'Text(verbatim: accessoryFocusRectangularStatusText)', '.font(Font(statusFont))',
  ]);
  final rectRecovery = _swiftCodeBlock(rectangular, 'let admittedHeaderAndRecovery:');
  require(presentation, 'rectangular-recovery-fit', rectRecovery, [
    'guard isValidGeometry else { return nil }',
    'width(candidate.text, font: candidate.font, pixelScale: pixelScale)',
    'lineHeight(candidate.font, pixelScale: pixelScale)',
    'w > 0, h > 0, w <= availableWidth',
    '(headerH + 2.0 + h) <= availableHeight', 'if h <= availableHeight',
    'return (true, candidate.font, candidate.text)',
    'return (false, candidate.font, candidate.text)', 'return nil',
  ]);
  final rectSymbolGate = _swiftCodeBlock(rectangular, 'let admittedSymbolRecovery:');
  require(presentation, 'rectangular-recovery-fit', rectSymbolGate, [
    'guard isValidGeometry else { return nil }',
    'accessoryMeasuredSymbolSize(name: accessoryFocusSFSymbol, font: f)',
    'Double(size.width) <= availableWidth', 'Double(size.height) <= availableHeight',
    'return (f, size)', 'return nil',
  ]);
  final rectRecoveryDraw = _swiftCodeBlock(rectangular, 'else if let recovery = admittedHeaderAndRecovery');
  final rectSymbolDraw = _swiftCodeBlock(rectangular, 'else if let symbolRecovery = admittedSymbolRecovery');
  final rectEmpty = _swiftElseBlock(rectangular, 'else if let symbolRecovery = admittedSymbolRecovery');
  require(presentation, 'rectangular-recovery-draw', rectRecoveryDraw, [
    'if recovery.headerFits', 'Text(verbatim: recovery.text)', '.font(Font(recovery.font))',
  ]);
  require(presentation, 'rectangular-recovery-draw', rectSymbolDraw, [
    'Image(systemName: accessoryFocusSFSymbol)', '.font(Font(symbolRecovery.font))',
  ]);
  require(presentation, 'rectangular-recovery-draw', rectEmpty, ['Color.clear']);

  require(presentation, 'circular-geometry', circular, [
    'let diameter = min(availableWidth, availableHeight)',
    'let isValidGeometry = availableWidth.isFinite && availableHeight.isFinite && diameter > 0',
  ]);
  require(presentation, 'circular-chord-fit', members['accessoryFitsInCircle']!, [
    'guard diameter.isFinite, inset.isFinite,',
    'topWidth.isFinite, bottomWidth.isFinite, totalHeight.isFinite,',
    'diameter > 2.0 * inset',
    'topWidth >= 0, bottomWidth >= 0, totalHeight > 0',
    'let safeDiameter = diameter - 2.0 * inset',
    '(topWidth * topWidth + totalHeight * totalHeight) <= maxDiameterSq',
    '(bottomWidth * bottomWidth + totalHeight * totalHeight) <= maxDiameterSq',
  ]);
  require(presentation, 'circular-status-metric', circular, [
    'let statusText = accessoryFocusCircularStatusText',
    'width(statusText, font: statusFont, pixelScale: pixelScale)',
    'lineHeight(statusFont, pixelScale: pixelScale)',
    'accessoryMeasuredSymbolSize(name: accessoryFocusSFSymbol, font: statusFont)',
  ]);
  require(presentation, 'circular-status-metric', circleText, [
    'Text(verbatim: statusText)', '.font(Font(statusFont))',
  ]);
  require(presentation, 'circular-status-metric', circleSymbol, [
    'Image(systemName: accessoryFocusSFSymbol)', '.font(Font(statusFont))',
  ]);
  final circleAdmission = _swiftCodeBlock(circular, 'let admittedClockLayout:');
  require(presentation, 'circular-clock-metric', circleAdmission, [
    'guard isValidGeometry, let sample = clockSample else { return nil }',
    'for baseSize in [12.0, 11.0, 10.0, 9.5, 9.0] as [CGFloat]',
    'baseSize: baseSize', 'textStyle: .caption2', 'category: uiCategory',
    'rounded: true', 'monospacedDigits: true',
    'width(sample, font: clockFont, pixelScale: pixelScale)',
    'lineHeight(clockFont, pixelScale: pixelScale)',
    'topWidth: statusW', 'bottomWidth: clockW',
    'totalHeight: statusH + clockSpacing + clockH',
    'topWidth: Double(symSize.width)',
    'totalHeight: Double(symSize.height) + clockSpacing + clockH',
    'return .textAndClock(clockFont: clockFont)',
    'return .symbolAndClock(clockFont: clockFont)', 'return nil',
  ]);
  // Both alternative stacks have their own bounded chord admission.
  final circleFitCalls = RegExp(r'\bSelf\.accessoryFitsInCircle\s*\(')
      .allMatches(_swiftMaskedSource(circleAdmission)).toList();
  if (circleFitCalls.length != 2) result[presentation]!.add('circular-clock-metric');
  for (final arm in [circleText, circleSymbol]) {
    require(presentation, 'circular-drawn-font', arm, [
      'focusClock(display)', '.font(Font(clockFont))',
    ]);
  }
  for (final gate in ['admittedCompositeRecovery', 'admittedTextOnlyRecovery', 'admittedSymbolOnlyRecovery']) {
    final block = _swiftCodeBlock(circular, 'let $gate:');
    require(presentation, 'circular-recovery-fit', block, [
      'guard isValidGeometry', 'Self.accessoryFitsInCircle(', 'diameter: diameter', 'return nil',
    ]);
  }
  require(presentation, 'circular-recovery-fit',
    _swiftCodeBlock(circular, 'let admittedCompositeRecovery:'), [
      'width(candidate, font: recoveryFont, pixelScale: pixelScale)',
      'lineHeight(recoveryFont, pixelScale: pixelScale)',
      'topWidth: Double(symSize.width)', 'bottomWidth: textW',
      'totalHeight: Double(symSize.height) + 1.5 + textH',
    ]);
  require(presentation, 'circular-recovery-fit',
    _swiftCodeBlock(circular, 'let admittedTextOnlyRecovery:'), [
      'topWidth: textW', 'totalHeight: textH',
    ]);
  require(presentation, 'circular-recovery-fit',
    _swiftCodeBlock(circular, 'let admittedSymbolOnlyRecovery:'), [
      'accessoryMeasuredSymbolSize(name: accessoryFocusSFSymbol, font: f)',
      'topWidth: Double(symSize.width)', 'totalHeight: Double(symSize.height)',
    ]);
  final circleRecovery = _swiftElseBlock(circular, 'if let clockLayout = admittedClockLayout');
  require(presentation, 'circular-recovery-draw', circleRecovery, [
    'if let recoveryText = admittedCompositeRecovery',
    'else if let recoveryText = admittedTextOnlyRecovery',
    'Text(verbatim: recoveryText)', '.font(Font(recoveryFont))',
    'else if let symbolFont = admittedSymbolOnlyRecovery', '.font(Font(symbolFont))',
    'Color.clear',
  ]);
  require(presentation, 'symbol-measurement', members['accessoryMeasuredSymbolSize']!, [
    'UIImage.SymbolConfiguration(font: font)',
    'UIImage(systemName: name, withConfiguration: config)',
    'roundUp(Double(image.size.width), scale: pixelScale)',
    'roundUp(Double(image.size.height), scale: pixelScale)',
    'guard w.isFinite, h.isFinite, w > 0, h > 0',
  ]);

  const numericLocale = r'.environment(\.locale, DuoyiFocusTimerState.timerClockLocale)';
  for (final branch in <(String, String, bool)>[
    ('inline-clock', inlineClock, false),
    ('inline-recovery', inlineRecovery, true),
    ('inline-empty', inlineEmpty, true),
    ('rectangular-clock', rectClock, false),
    ('rectangular-recovery', rectRecoveryDraw, true),
    ('rectangular-symbol', rectSymbolDraw, true),
    ('rectangular-empty', rectEmpty, true),
    ('circular-clock', circleClock, false),
    ('circular-recovery', circleRecovery, true),
  ]) {
    call(presentation, '${branch.$1}-ax', branch.$2,
      'accessoryFocusAccessibilityText', branch.$3
        ? 'display, recoveryNote: accessoryFocusRecoveryTitle' : 'display');
    require(presentation, '${branch.$1}-ax', branch.$2, [
      '.accessibilityLabel(accessoryFocusAccessibilityText(',
      if (branch.$3) '.accessibilityHint(accessoryFocusRecoveryHint)',
    ]);
    require(presentation, '${branch.$1}-locale', branch.$2, [numericLocale]);
    if (_swiftMaskedSource(branch.$2).contains('.accessibilityHidden(true)') &&
        !branch.$1.startsWith('rectangular')) {
      result[presentation]!.add('${branch.$1}-ax');
    }
  }
  final ax = members['accessoryFocusAccessibilityText']!;
  require(presentation, 'canonical-ax-time', ax, [
    'let status = accessoryFocusAccessibleDescriptionPrefix',
    'let suffix = recoveryNote.map',
    r'return Text(verbatim: "\(status) \(clock)\(suffix)")',
    r'return Text("\(status) \(Text(timerInterval: entry.date...end, countsDown: true))\(suffix)")',
    r'return Text("\(status) \(Text(timerInterval: start...cap, countsDown: false))\(suffix)")',
  ]);
  require(presentation, 'canonical-ax-label',
    members['accessoryFocusAccessibleDescriptionPrefix']!, [
      'private var accessoryFocusAccessibleDescriptionPrefix: String {\n'
      r'        "\(entry.config.title) · \(accessoryFocusDirectionStatus) · \(entry.focusTimerLabel)"',
    ]);
  require(presentation, 'cap-direction-truth', members['accessoryFocusDirectionStatus']!, [
    'switch entry.focusTimer.phase', 'case .runningCountdown:', 'case .runningCountUp:',
    'case .pausedCountdown:', 'case .pausedCountUp:', 'case .ended:',
    'if entry.focusTimer.isAtCountUpCap',
    'return entry.locale == .en ? "Count-up elapsed · 24h cap reached" : "正计时已用 · 已达24小时上限"',
    'return entry.locale == .en ? "Paused · Saved elapsed · 24h cap" : "已暂停 · 已保存已用 · 24小时上限"',
    'return entry.locale == .en ? "Finished · Countdown ended" : "已结束 · 倒计时结束"',
  ]);
  for (final name in [
    'accessoryFocusRecoveryTitle', 'accessoryFocusRecoveryCompactTitle',
    'accessoryFocusRecoveryHint', 'accessoryFocusShortStatus',
    'accessoryFocusCompactCue', 'accessoryFocusRectangularStatusText',
  ]) {
    require(presentation, 'localized-recovery-status', members[name]!, ['entry.locale == .en']);
  }
  require(presentation, 'localized-open-copy', members['accessoryFocusRecoveryTitle']!, [
    'entry.locale == .en ? "Open in app" : "在应用中打开"',
  ]);
  require(presentation, 'localized-open-copy', members['accessoryFocusRecoveryHint']!, [
    '? "Clock cannot fit at current text size. Open Duoyi to view full focus timer."',
  ]);
  return result;
}
// END IOS FOCUS ACCESSORY POLICY 2297 HELPERS
