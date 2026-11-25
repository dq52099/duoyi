// Preparation only: these widget cases have not been executed.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/location_reminder_storage.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/quick_capture_template_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/backup_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/webdav_backup_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/app_access_layer.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../support/backup_continuous_capture_178.dart';
import '../test_support/recording_reminder_scheduler.dart';

const _mappedTitle = 'Mapped chooser task';
const _fallbackTitle = 'Automatic fallback task';
const _mappingColumn = 'source_caption';
const _coverText = 'Source chooser covering route';
const _fileContents = '''
[{"type":"task","title":"Automatic fallback task","source_caption":"Mapped chooser task"}]
''';

class _FileSelector extends FileSelectorPlatform {
  int opens = 0;
  List<XTypeGroup>? acceptedGroups;
  Completer<void>? _gate;
  bool heldOpenStarted = false;

  void holdNextOpen() {
    if (_gate != null) throw StateError('A file selection is already held');
    _gate = Completer<void>();
    heldOpenStarted = false;
  }

  void release() {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    opens++;
    acceptedGroups = acceptedTypeGroups;
    final gate = _gate;
    if (gate != null) {
      heldOpenStarted = true;
      await gate.future;
      if (identical(_gate, gate)) _gate = null;
    }
    return XFile.fromData(
      Uint8List.fromList(utf8.encode(_fileContents)),
      name: 'synthetic-source-chooser.json',
      mimeType: 'application/json',
    );
  }
}

class _RecordingStore extends InMemorySharedPreferencesStore {
  _RecordingStore(super.data) : super.withData();

  final businessMutations = <String>[];

  bool _themeKey(String key) {
    final clean = key.startsWith('flutter.') ? key.substring(8) : key;
    return const {
      'active_brand',
      'theme_switch_count',
      'theme_shop_state',
      'theme_unlocked_brands',
    }.contains(clean);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (!_themeKey(key)) businessMutations.add('set:$key');
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (!_themeKey(key)) businessMutations.add('remove:$key');
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    businessMutations.add('clear');
    return super.clear();
  }
}

class _RecordingTodos extends TodoProvider {
  int importCalls = 0;
  final receivedTitles = <List<String>>[];

  @override
  Future<TodoImportSummary> importTodos(Iterable<TodoItem> imported) {
    importCalls++;
    final incoming = imported.toList(growable: false);
    receivedTitles.add([for (final todo in incoming) todo.title]);
    return super.importTodos(incoming);
  }
}

class _Scenario {
  final AppLocale locale;
  final Size size;
  const _Scenario(this.locale, this.size);

  String get name =>
      '${locale.name}-${size.width.toInt()}x${size.height.toInt()}-scale200';
  AppLocale get otherLocale =>
      locale == AppLocale.zh ? AppLocale.en : AppLocale.zh;
}

const _scenarios = <_Scenario>[
  _Scenario(AppLocale.zh, Size(320, 844)),
  _Scenario(AppLocale.en, Size(320, 844)),
  _Scenario(AppLocale.zh, Size(568, 320)),
  _Scenario(AppLocale.en, Size(568, 320)),
];

Directory? _captureBatch;
final _capturedNames = <String>{};

String _workspaceEvidenceRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (FileSystemEntity.typeSync(
          path.join(directory.path, '.git'),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      return path.join(directory.path, 'evidence');
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Cannot locate workspace evidence root for optional capture',
      );
    }
    directory = parent;
  }
}

void _requireRealDirectories(String target, {bool createMissing = false}) {
  final absolute = path.normalize(path.absolute(target));
  var current = path.rootPrefix(absolute);
  for (final segment in path.split(absolute).skip(1)) {
    current = path.join(current, segment);
    var type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StateError('Optional capture refuses symlink directory: $current');
    }
    if (type == FileSystemEntityType.notFound && createMissing) {
      Directory(current).createSync();
      type = FileSystemEntity.typeSync(current, followLinks: false);
    }
    if (type != FileSystemEntityType.directory) {
      throw StateError('Optional capture requires a real directory: $current');
    }
  }
}

// Adapts the accepted backup/ICS capture flow: one unconditional pump, the
// actual viewport boundary, toImage/PNG and a durable state sidecar. Local
// directory admission adds symlink checks and a fresh batch; shared helpers
// currently do not enforce these stricter output ownership requirements.
Future<void> _capture(
  WidgetTester tester,
  _Harness harness,
  _Scenario scenario,
  String phase,
) async {
  await tester.pump();
  final supplied = Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  final continuous = Platform.environment['DUOYI_BACKUP_CONTINUOUS_DIR'];
  if ((supplied == null || supplied.trim().isEmpty) &&
      (continuous == null || continuous.trim().isEmpty)) {
    return;
  }
  if (Platform.environment['DUOYI_RESOURCE_GUARD_RUN_ID']?.isNotEmpty != true) {
    throw StateError(
      'Optional screenshot output requires the project resource guard',
    );
  }
  final evidence = path.normalize(path.absolute(_workspaceEvidenceRoot()));
  final output = supplied == null || supplied.trim().isEmpty
      ? null
      : path.normalize(path.absolute(supplied));
  if (output != null && !path.isWithin(evidence, output)) {
    throw StateError(
      'Screenshot output must be a named directory under workspace evidence/',
    );
  }
  if (!const {
    'chooser-default',
    'chooser-glass',
    'mapping-default',
    'mapping-glass',
    'preview-default',
    'preview-glass',
    'result-glass',
    'result-default',
  }.contains(phase)) {
    throw StateError('Unexpected screenshot phase: $phase');
  }
  final name = '${scenario.name}-$phase';
  if (!_capturedNames.add(name)) {
    throw StateError('Duplicate screenshot state: $name');
  }
  final boundary = harness.captureKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary || !boundary.attached) {
    throw StateError(
      'Screenshot requires the real mounted viewport repaint boundary',
    );
  }
  final media = MediaQuery.of(harness.captureKey.currentContext!);
  final policy = find.descendant(
    of: _dialog(DataSettingsUiCopy.importPreviewTitle),
    matching: find.byType(CheckboxListTile),
  );
  final state = <String, Object?>{
    'case': scenario.name,
    'phase': phase,
    'brand': harness.theme.brand.id,
    'locale': I18n.current.name,
    'textScale': media.textScaler.scale(12) / 12,
    'viewport': [media.size.width, media.size.height],
    'fileSelections': harness.selector.opens,
    'sourceLabel': DataSettingsUiCopy.sourceTickTick,
    'mappingSummary': _mappingSummary(),
    'policyConfirmed': policy.evaluate().isEmpty
        ? null
        : tester.widget<CheckboxListTile>(policy).value,
    'importCalls': harness.todos.importCalls,
    'todoTitles': [for (final todo in harness.todos.todos) todo.title],
    'businessMutations': List<String>.of(harness.store.businessMutations),
  };
  await captureBackupDialogContinuously(
    tester,
    harness.captureKey,
    scenario.name,
    phase,
    state,
  );
  if (output == null) return;
  await tester.runAsync(() async {
    _requireRealDirectories(output, createMissing: true);
    final batch = _captureBatch ??= Directory(
      output,
    ).createTempSync('backup-source-chooser-67-');
    if (!path.isWithin(output, batch.path)) {
      throw StateError('Capture batch output changed');
    }
    _requireRealDirectories(batch.path);
    final png = File(path.join(batch.path, '$name.png'));
    final sidecar = File(path.join(batch.path, '$name.json'));
    for (final file in [png, sidecar]) {
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Screenshot artifact already exists: ${file.path}');
      }
    }
    final picture = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Screenshot PNG encoding returned no data');
      }
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      // Check again after asynchronous rendering; preserve any existing output.
      _requireRealDirectories(batch.path);
      for (final file in [png, sidecar]) {
        if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw StateError('Screenshot destination changed: ${file.path}');
        }
      }
      await png.writeAsBytes(bytes, flush: true);
      await sidecar.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          ...state,
          'png': png.path,
          'pngSha256': sha256.convert(bytes).toString(),
          'capturePixelRatio': 1,
          'pngSize': [picture.width, picture.height],
        }),
        flush: true,
      );
    } finally {
      picture.dispose();
    }
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  expect(tester.takeException(), isNull);
}

Finder _dialog(String title) => find.byWidgetPredicate(
  (widget) =>
      widget is AppDialog &&
      widget.title is Text &&
      (widget.title as Text).data == title,
);

Finder _chooser() =>
    _dialog(DataSettingsUiCopy.importCompetitorFileSourceTitle);

Finder _mapping() => _dialog(DataSettingsUiCopy.advancedFieldMapping);

Finder _dialogButton(Finder dialog, Type type, String label) =>
    find.descendant(of: dialog, matching: find.widgetWithText(type, label));

Finder _sourceField() => find.descendant(
  of: _chooser(),
  matching: find.byWidgetPredicate((widget) => widget is AppDropdownField),
);

Finder _mappingTitleInput() => find.descendant(
  of: _mapping(),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText ==
            DataSettingsUiCopy.fieldTargetLabel('title'),
  ),
);

String _mappingSummary() =>
    '${DataSettingsUiCopy.fieldTargetLabel('title')} <- $_mappingColumn';

Future<void> _tap(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await _settle(tester);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _selectTickTick(WidgetTester tester) async {
  await _tap(tester, _sourceField());
  // Use the production anchored menu, including its keyboard/route guards.
  await _tap(
    tester,
    find.text(DataSettingsUiCopy.sourceTickTick).hitTestable(),
  );
  expect(
    find.descendant(
      of: _chooser(),
      matching: find.text(DataSettingsUiCopy.hintTickTick),
    ),
    findsOneWidget,
  );
}

Future<void> _openMapping(WidgetTester tester) async {
  await _tap(
    tester,
    _dialogButton(
      _chooser(),
      OutlinedButton,
      DataSettingsUiCopy.advancedFieldMapping,
    ),
  );
  expect(_mapping(), findsOneWidget);
}

Future<void> _saveTitleMapping(WidgetTester tester) async {
  await _openMapping(tester);
  await tester.ensureVisible(_mappingTitleInput());
  await tester.enterText(_mappingTitleInput(), _mappingColumn);
  await _tap(
    tester,
    _dialogButton(_mapping(), FilledButton, I18n.tr('action.save')),
  );
  expect(
    find.descendant(of: _chooser(), matching: find.text(_mappingSummary())),
    findsOneWidget,
  );
}

void _expectChooserTheme(WidgetTester tester, AppBrand brand) {
  final dialog = _chooser();
  expect(dialog, findsOneWidget);
  final context = tester.element(dialog);
  final theme = Theme.of(context);
  expect(theme.colorScheme.primary, brand.theme.colorScheme.primary);
  expect(theme.colorScheme.surface, brand.theme.colorScheme.surface);
  expect(theme.colorScheme.onSurface, brand.theme.colorScheme.onSurface);
  expect(appSurfaceStyleOf(context), brand.theme.extension<AppSurfaceStyle>());
  expect(MediaQuery.textScalerOf(context).scale(12), 24);

  // Check inherited colors inside real controls, not just the parent app theme.
  final field = _sourceField();
  expect(
    Theme.of(tester.element(field)).colorScheme.primary,
    brand.theme.colorScheme.primary,
  );
  expect(
    appSurfaceStyleOf(tester.element(field)),
    brand.theme.extension<AppSurfaceStyle>(),
  );
  final hint = find.descendant(
    of: dialog,
    matching: find.text(DataSettingsUiCopy.hintTickTick),
  );
  expect(
    tester.widget<Text>(hint).style?.color,
    brand.theme.colorScheme.onSurface.withValues(alpha: 0.62),
  );
  final confirm = _dialogButton(
    dialog,
    FilledButton,
    DataSettingsUiCopy.importCompetitorFileSourceAction,
  );
  expect(
    Theme.of(tester.element(confirm)).colorScheme.primary,
    brand.theme.colorScheme.primary,
  );
  expect(
    find.descendant(
      of: dialog,
      matching: find.text(DataSettingsUiCopy.sourceTickTick),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(of: dialog, matching: find.text(_mappingSummary())),
    findsOneWidget,
  );
}

void _expectImportFlowTheme75(
  WidgetTester tester,
  Finder dialog,
  AppBrand brand,
  List<Finder> controls,
) {
  expect(dialog, findsOneWidget);
  for (final target in [dialog, ...controls]) {
    expect(target, findsOneWidget);
    final context = tester.element(target);
    final colors = Theme.of(context).colorScheme;
    expect(colors.primary, brand.theme.colorScheme.primary);
    expect(colors.surface, brand.theme.colorScheme.surface);
    expect(colors.onSurface, brand.theme.colorScheme.onSurface);
    expect(
      appSurfaceStyleOf(context),
      brand.theme.extension<AppSurfaceStyle>(),
    );
    expect(MediaQuery.textScalerOf(context).scale(12), 24);
    expect(
      Localizations.localeOf(context).languageCode,
      I18n.current == AppLocale.en ? 'en' : 'zh',
    );
  }
}

class _Harness {
  final theme = ThemeProvider();
  final reminderScheduler = RecordingReminderScheduler();
  late final todos = _RecordingTodos()..scheduler = reminderScheduler;
  late final replacementTodos = _RecordingTodos()
    ..scheduler = reminderScheduler;
  final habits = HabitProvider();
  final pomodoro = PomodoroProvider();
  final notes = NoteProvider();
  final anniversaries = AnniversaryProvider();
  final diary = DiaryProvider();
  final goals = GoalProvider();
  final courses = CourseProvider();
  final users = UserProvider();
  final timeAudit = TimeAuditProvider();
  final achievements = AchievementProvider();
  final shares = ShareProvider();
  final calendar = CalendarProvider();
  final countdowns = CountdownProvider();
  final locationReminders = LocationReminderProvider();
  final preferences = PreferencesProvider();
  final quickCaptureTemplates = QuickCaptureTemplateProvider();
  final useReplacement = ValueNotifier<bool>(false);
  final navigatorKey = GlobalKey<NavigatorState>();
  final captureKey = GlobalKey(debugLabel: 'backup-source-chooser-capture');
  final selector = _FileSelector();
  late _RecordingStore store;
  int clipboardWrites = 0;

  Widget get app => ValueListenableBuilder<bool>(
    valueListenable: useReplacement,
    builder: (context, replace, _) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<TodoProvider>.value(
          value: replace ? replacementTodos : todos,
        ),
        ChangeNotifierProvider<HabitProvider>.value(value: habits),
        ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
        ChangeNotifierProvider<NoteProvider>.value(value: notes),
        ChangeNotifierProvider<AnniversaryProvider>.value(value: anniversaries),
        ChangeNotifierProvider<DiaryProvider>.value(value: diary),
        ChangeNotifierProvider<GoalProvider>.value(value: goals),
        ChangeNotifierProvider<CourseProvider>.value(value: courses),
        ChangeNotifierProvider<UserProvider>.value(value: users),
        ChangeNotifierProvider<TimeAuditProvider>.value(value: timeAudit),
        ChangeNotifierProvider<AchievementProvider>.value(value: achievements),
        ChangeNotifierProvider<ShareProvider>.value(value: shares),
        ChangeNotifierProvider<CalendarProvider>.value(value: calendar),
        ChangeNotifierProvider<CountdownProvider>.value(value: countdowns),
        ChangeNotifierProvider<LocationReminderProvider>.value(
          value: locationReminders,
        ),
        ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        ChangeNotifierProvider<QuickCaptureTemplateProvider>.value(
          value: quickCaptureTemplates,
        ),
      ],
      child: AnimatedBuilder(
        animation: Listenable.merge([theme, I18n.localeListenable]),
        builder: (context, _) => MaterialApp(
          navigatorKey: navigatorKey,
          locale: Locale(I18n.current == AppLocale.en ? 'en' : 'zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theme.brand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: RepaintBoundary(key: captureKey, child: child!),
          ),
          home: const BrandRouteSurface(
            remountOnLocaleChange: false,
            child: BackupScreen(initialMode: BackupEntryMode.restore),
          ),
        ),
      ),
    ),
  );

  Future<void> startFileSelection(WidgetTester tester) async {
    final button = find.widgetWithText(
      OutlinedButton,
      DataSettingsUiCopy.importProductivityFileButton,
    );
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
    await _tap(tester, button);
    expect(selector.opens, 1);
    expect(selector.acceptedGroups!.single.extensions, ['json', 'csv', 'txt']);
    expectNoImport();
  }

  Future<void> openChooser(WidgetTester tester) async {
    await startFileSelection(tester);
    expect(_chooser(), findsOneWidget);
    expect(
      find.descendant(
        of: _chooser(),
        matching: find.text(DataSettingsUiCopy.hintZhijianTime),
      ),
      findsOneWidget,
    );
    expect(
      find.byType(TextField),
      findsNothing,
      reason:
          'This is the real file-source chooser, not the paste-import dialog.',
    );
    expectNoImport();
  }

  Future<void> switchBrand(WidgetTester tester, String id) async {
    await tester.runAsync(() async {
      expect(await theme.setBrand(id), isTrue);
    });
    await _settle(tester);
    expect(theme.brand.id, id);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('active_brand'), id);
    expectNoImport();
  }

  void expectNoImport() {
    expect(todos.importCalls, 0);
    expect(replacementTodos.importCalls, 0);
    expect(todos.todos, isEmpty);
    expect(replacementTodos.todos, isEmpty);
    expect(anniversaries.items, isEmpty);
    expect(countdowns.items, isEmpty);
    expect(store.businessMutations, isEmpty);
    expect(clipboardWrites, 0);
  }

  Future<void> expectOneMappedImport() async {
    expect(todos.importCalls, 1);
    expect(todos.receivedTitles, [
      [_mappedTitle],
    ]);
    expect(todos.todos.single.title, _mappedTitle);
    expect(replacementTodos.importCalls, 0);
    expect(replacementTodos.todos, isEmpty);
    expect(anniversaries.items, isEmpty);
    expect(countdowns.items, isEmpty);
    expect(
      store.businessMutations.where((item) => item == 'set:flutter.todos'),
      hasLength(1),
    );
    expect(
      store.businessMutations.where(
        (item) => item == 'clear' || item.startsWith('remove:'),
      ),
      isEmpty,
    );
    expect(clipboardWrites, 0);
    final preferences = await SharedPreferences.getInstance();
    final saved = jsonDecode(preferences.getString('todos')!) as List<dynamic>;
    expect(saved, hasLength(1));
    expect((saved.single as Map<String, dynamic>)['title'], _mappedTitle);
  }

  void dispose() {
    useReplacement.dispose();
    for (final notifier in <ChangeNotifier>[
      theme,
      todos,
      replacementTodos,
      habits,
      pomodoro,
      notes,
      anniversaries,
      diary,
      goals,
      courses,
      users,
      timeAudit,
      achievements,
      shares,
      calendar,
      countdowns,
      locationReminders,
      preferences,
      quickCaptureTemplates,
    ]) {
      notifier.dispose();
    }
  }
}

Future<void> _withHarness(
  WidgetTester tester,
  Future<void> Function(_Harness harness) body, {
  _Scenario scenario = const _Scenario(AppLocale.zh, Size(320, 844)),
  bool confirmedImport = false,
}) async {
  final oldLocale = I18n.current;
  final oldTimeZoneReader = LocalTimezoneResolver.debugSystemTimeZoneReader;
  final oldSelector = FileSelectorPlatform.instance;
  final oldStore = SharedPreferencesStorePlatform.instance;
  final initial = <String, Object>{
    'active_brand': 'defaultBrand',
    'theme_shop_state': jsonEncode({
      'activeBrand': 'defaultBrand',
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
  };
  SharedPreferences.setMockInitialValues(initial);
  final harness = _Harness();
  harness.store = _RecordingStore({
    for (final entry in initial.entries) 'flutter.${entry.key}': entry.value,
  });
  SharedPreferencesStorePlatform.instance = harness.store;
  FileSelectorPlatform.instance = harness.selector;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') harness.clipboardWrites++;
        return null;
      });
  try {
    I18n.setLocale(scenario.locale);
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    await tester.runAsync(loadWeeklyReviewScreenshotFonts);
    await harness.theme.loadFromStorage();
    expect(harness.theme.brand.id, 'defaultBrand');
    expect(harness.theme.isBrandUnlocked('liquidGlass'), isTrue);
    tester.view.physicalSize = scenario.size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(harness.app);
    await _settle(tester);
    harness.expectNoImport();
    await body(harness);
    await _settle(tester);
    if (confirmedImport) {
      await harness.expectOneMappedImport();
    } else {
      harness.expectNoImport();
    }
  } finally {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      // Resolve a held picker only after the originating widget is unmounted.
      harness.selector.release();
      await _settle(tester);
    } finally {
      harness.dispose();
      tester.view.reset();
      I18n.setLocale(oldLocale);
      LocalTimezoneResolver.debugSystemTimeZoneReader = oldTimeZoneReader;
      FileSelectorPlatform.instance = oldSelector;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = oldStore;
    }
  }
}

Future<void> _cover(WidgetTester tester, _Harness harness) async {
  unawaited(
    harness.navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text(_coverText))),
      ),
    ),
  );
  await _settle(tester);
  expect(find.text(_coverText), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await WebDavBackupService.loadConfig();
  });

  for (final scenario in _scenarios) {
    testWidgets(
      'file source chooser retains live theme, locale, mapping and cancel ${scenario.name}',
      (tester) async {
        await _withHarness(tester, (harness) async {
          await harness.openChooser(tester);
          final screen = find.byType(BackupScreen);
          final screenState = tester.state(screen);
          final screenRoute = ModalRoute.of(tester.element(screen));
          final chooserElement = tester.element(_chooser());
          final chooserRoute = ModalRoute.of(chooserElement);
          await _selectTickTick(tester);
          await _saveTitleMapping(tester);
          final sourceState = tester.state(
            find.descendant(
              of: _sourceField(),
              matching: find.byWidgetPredicate((widget) => widget is FormField),
            ),
          );

          void expectRetained(AppBrand brand) {
            _expectChooserTheme(tester, brand);
            expect(tester.element(_chooser()), same(chooserElement));
            expect(
              ModalRoute.of(tester.element(_chooser())),
              same(chooserRoute),
            );
            expect(tester.state(screen), same(screenState));
            expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
            expect(
              tester.state(
                find.descendant(
                  of: _sourceField(),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is FormField,
                  ),
                ),
              ),
              same(sourceState),
            );
            expect(harness.selector.opens, 1);
            harness.expectNoImport();
          }

          expectRetained(AppBrands.defaultBrand);
          await _capture(tester, harness, scenario, 'chooser-default');
          // Brand changes alone must refresh the still-mounted dialog.
          await harness.switchBrand(tester, 'liquidGlass');
          expectRetained(AppBrands.liquidGlass);
          I18n.setLocale(scenario.otherLocale);
          await _settle(tester);
          expectRetained(AppBrands.liquidGlass);
          await _capture(tester, harness, scenario, 'chooser-glass');
          await harness.switchBrand(tester, 'defaultBrand');
          expectRetained(AppBrands.defaultBrand);
          I18n.setLocale(scenario.locale);
          await _settle(tester);
          expectRetained(AppBrands.defaultBrand);

          await _openMapping(tester);
          final input = _mappingTitleInput();
          final controller = tester.widget<TextField>(input).controller!;
          expect(controller.text, _mappingColumn);
          const selection = TextSelection(baseOffset: 1, extentOffset: 6);
          controller.selection = selection;
          await tester.pump();
          await _capture(tester, harness, scenario, 'mapping-default');
          final mappingRoute = ModalRoute.of(tester.element(_mapping()));
          await harness.switchBrand(tester, 'liquidGlass');
          I18n.setLocale(scenario.otherLocale);
          await _settle(tester);
          expect(
            tester.widget<TextField>(_mappingTitleInput()).controller,
            same(controller),
          );
          expect(controller.text, _mappingColumn);
          expect(controller.selection, selection);
          expect(ModalRoute.of(tester.element(_mapping())), same(mappingRoute));
          expect(
            Theme.of(tester.element(_mapping())).colorScheme.primary,
            AppBrands.liquidGlass.theme.colorScheme.primary,
          );
          await _capture(tester, harness, scenario, 'mapping-glass');
          await _tap(
            tester,
            _dialogButton(_mapping(), TextButton, I18n.tr('action.cancel')),
          );
          expectRetained(AppBrands.liquidGlass);
          await _tap(
            tester,
            _dialogButton(_chooser(), TextButton, I18n.tr('action.cancel')),
          );
          expect(find.byType(AppDialog), findsNothing);
          expect(tester.state(screen), same(screenState));
          expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
          expect(
            find.text(DataSettingsUiCopy.importPreviewTitle),
            findsNothing,
          );
        }, scenario: scenario);
      },
    );
  }

  for (final scenario in _scenarios) {
    testWidgets(
      'file preview and result retain live theme, locale, policy and single import ${scenario.name}',
      (tester) async {
        await _withHarness(
          tester,
          (harness) async {
            final generation = AccountLocalDataCleaner.accountDataGeneration;
            final screen = find.byType(BackupScreen);
            final screenState = tester.state(screen);
            final screenRoute = ModalRoute.of(tester.element(screen));

            Future<Finder> openMappedPreview(int expectedSelections) async {
              if (expectedSelections == 1) {
                await harness.openChooser(tester);
              } else {
                // A second real file-button action follows the cancelled preview.
                // Keep the original harness's exact one-selection assertion intact.
                expect(expectedSelections, 2);
                await _tap(
                  tester,
                  find.widgetWithText(
                    OutlinedButton,
                    DataSettingsUiCopy.importProductivityFileButton,
                  ),
                );
                expect(harness.selector.opens, 2);
                expect(harness.selector.acceptedGroups!.single.extensions, [
                  'json',
                  'csv',
                  'txt',
                ]);
                expect(_chooser(), findsOneWidget);
                expect(
                  find.descendant(
                    of: _chooser(),
                    matching: find.text(DataSettingsUiCopy.hintZhijianTime),
                  ),
                  findsOneWidget,
                );
                expect(find.byType(TextField), findsNothing);
                harness.expectNoImport();
              }
              await _selectTickTick(tester);
              await _saveTitleMapping(tester);
              await _tap(
                tester,
                _dialogButton(
                  _chooser(),
                  FilledButton,
                  DataSettingsUiCopy.importCompetitorFileSourceAction,
                ),
              );
              expect(harness.selector.opens, expectedSelections);
              expect(_chooser(), findsNothing);
              final initialPreview = _dialog(
                DataSettingsUiCopy.importPreviewTitle,
              );
              expect(initialPreview, findsOneWidget);
              harness.expectNoImport();
              final previewElement = tester.element(initialPreview);
              return find.byElementPredicate(
                (element) => identical(element, previewElement),
              );
            }

            final preview = await openMappedPreview(1);
            final previewElement = tester.element(preview);
            final previewRoute = ModalRoute.of(previewElement);
            final policy = find.descendant(
              of: preview,
              matching: find.byType(CheckboxListTile),
            );
            final policyElement = tester.element(policy);

            void expectPreviewRetained(AppBrand brand, bool confirmed) {
              final confirm = _dialogButton(
                preview,
                FilledButton,
                DataSettingsUiCopy.confirmImport,
              );
              final cancel = _dialogButton(
                preview,
                TextButton,
                I18n.tr('action.cancel'),
              );
              final mappingText = find.descendant(
                of: preview,
                matching: find.text(
                  DataSettingsUiCopy.importPreviewMapping(_mappingSummary()),
                ),
              );
              _expectImportFlowTheme75(tester, preview, brand, [
                policy,
                confirm,
                cancel,
                mappingText,
              ]);
              expect(tester.element(preview), same(previewElement));
              expect(
                ModalRoute.of(tester.element(preview)),
                same(previewRoute),
              );
              expect(previewRoute!.isCurrent, isTrue);
              expect(tester.element(policy), same(policyElement));
              expect(tester.widget<CheckboxListTile>(policy).value, confirmed);
              expect(
                find.descendant(
                  of: policy,
                  matching: find.text(
                    DataSettingsUiCopy.confirmImportPolicyCheckbox,
                  ),
                ),
                findsOneWidget,
              );
              expect(
                tester.widget<FilledButton>(confirm).onPressed,
                confirmed ? isNotNull : isNull,
              );
              expect(
                find.descendant(
                  of: preview,
                  matching: find.text(
                    DataSettingsUiCopy.importPreviewSource(
                      DataSettingsUiCopy.sourceTickTick,
                      'JSON',
                    ),
                  ),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: preview,
                  matching: find.textContaining(_mappedTitle),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: preview,
                  matching: find.textContaining(_fallbackTitle),
                ),
                findsNothing,
              );
              expect(
                tester.widget<Text>(mappingText).style?.color,
                Theme.of(tester.element(preview)).textTheme.bodySmall?.color,
              );
              expect(tester.state(screen), same(screenState));
              expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
              expect(
                tester.element(screen).read<TodoProvider>(),
                same(harness.todos),
              );
              expect(AccountLocalDataCleaner.accountDataGeneration, generation);
              expect(harness.selector.opens, 1);
              harness.expectNoImport();
            }

            expectPreviewRetained(AppBrands.defaultBrand, false);
            await _capture(tester, harness, scenario, 'preview-default');
            await harness.switchBrand(tester, 'liquidGlass');
            expectPreviewRetained(AppBrands.liquidGlass, false);
            I18n.setLocale(scenario.otherLocale);
            await _settle(tester);
            expectPreviewRetained(AppBrands.liquidGlass, false);
            await harness.switchBrand(tester, 'defaultBrand');
            expectPreviewRetained(AppBrands.defaultBrand, false);
            I18n.setLocale(scenario.locale);
            await _settle(tester);
            expectPreviewRetained(AppBrands.defaultBrand, false);
            await _tap(tester, policy);
            expectPreviewRetained(AppBrands.defaultBrand, true);
            await harness.switchBrand(tester, 'liquidGlass');
            expectPreviewRetained(AppBrands.liquidGlass, true);
            I18n.setLocale(scenario.otherLocale);
            await _settle(tester);
            expectPreviewRetained(AppBrands.liquidGlass, true);
            await _capture(tester, harness, scenario, 'preview-glass');
            await _tap(
              tester,
              _dialogButton(preview, TextButton, I18n.tr('action.cancel')),
            );
            expect(find.byType(AppDialog), findsNothing);
            expect(find.byType(SnackBar), findsNothing);
            expect(tester.state(screen), same(screenState));
            expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
            harness.expectNoImport();

            final confirmedPreview = await openMappedPreview(2);
            expect(
              ModalRoute.of(tester.element(confirmedPreview)),
              isNot(same(previewRoute)),
            );
            final confirmedPolicy = find.descendant(
              of: confirmedPreview,
              matching: find.byType(CheckboxListTile),
            );
            final confirm = _dialogButton(
              confirmedPreview,
              FilledButton,
              DataSettingsUiCopy.confirmImport,
            );
            _expectImportFlowTheme75(
              tester,
              confirmedPreview,
              AppBrands.liquidGlass,
              [confirmedPolicy, confirm],
            );
            expect(
              tester.widget<CheckboxListTile>(confirmedPolicy).value,
              isFalse,
            );
            expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
            expect(
              find.descendant(
                of: confirmedPreview,
                matching: find.text(
                  DataSettingsUiCopy.importPreviewSource(
                    DataSettingsUiCopy.sourceTickTick,
                    'JSON',
                  ),
                ),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: confirmedPreview,
                matching: find.text(
                  DataSettingsUiCopy.importPreviewMapping(_mappingSummary()),
                ),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: confirmedPreview,
                matching: find.textContaining(_mappedTitle),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: confirmedPreview,
                matching: find.textContaining(_fallbackTitle),
              ),
              findsNothing,
            );
            await _tap(tester, confirmedPolicy);
            expect(
              tester.widget<CheckboxListTile>(confirmedPolicy).value,
              isTrue,
            );
            expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
            harness.expectNoImport();
            await _tap(tester, confirm);
            final initialResult = _dialog(
              DataSettingsUiCopy.importCompletedTitle,
            );
            for (
              var frame = 0;
              frame < 100 && initialResult.evaluate().isEmpty;
              frame++
            ) {
              await tester.pump(const Duration(milliseconds: 20));
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
            }
            await _settle(tester);
            expect(initialResult, findsOneWidget);
            expect(confirmedPreview, findsNothing);
            await harness.expectOneMappedImport();
            final resultElement = tester.element(initialResult);
            final result = find.byElementPredicate(
              (element) => identical(element, resultElement),
            );
            final resultRoute = ModalRoute.of(resultElement);
            final importedData = harness.todos.todos.single.toJson();
            final preferences = await SharedPreferences.getInstance();
            final persistedTodos = preferences.getString('todos');
            final businessMutations = List<String>.of(
              harness.store.businessMutations,
            );

            Future<void> expectResultRetained(AppBrand brand) async {
              final gotIt = _dialogButton(
                result,
                FilledButton,
                DataSettingsUiCopy.gotIt,
              );
              final undo = _dialogButton(
                result,
                TextButton,
                DataSettingsUiCopy.undoImport,
              );
              _expectImportFlowTheme75(tester, result, brand, [gotIt, undo]);
              expect(tester.element(result), same(resultElement));
              expect(ModalRoute.of(tester.element(result)), same(resultRoute));
              expect(resultRoute!.isCurrent, isTrue);
              expect(
                find.descendant(
                  of: result,
                  matching: find.text(
                    '${DataSettingsUiCopy.sourceTickTick} · JSON',
                  ),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: result,
                  matching: find.text(DataSettingsUiCopy.moduleTodo),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: result,
                  matching: find.text(DataSettingsUiCopy.itemCount(1)),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: result,
                  matching: find.text(DataSettingsUiCopy.skippedSummary(0, 0)),
                ),
                findsOneWidget,
              );
              expect(find.byType(CheckboxListTile), findsNothing);
              expect(tester.state(screen), same(screenState));
              expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
              expect(
                tester.element(screen).read<TodoProvider>(),
                same(harness.todos),
              );
              expect(AccountLocalDataCleaner.accountDataGeneration, generation);
              expect(harness.selector.opens, 2);
              await harness.expectOneMappedImport();
              expect(harness.todos.todos.single.toJson(), importedData);
              expect(preferences.getString('todos'), persistedTodos);
              expect(harness.store.businessMutations, businessMutations);
            }

            Future<void> switchResultBrand(String id) async {
              // Post-import switches keep all original zero-import helpers intact.
              await tester.runAsync(() async {
                expect(await harness.theme.setBrand(id), isTrue);
              });
              await _settle(tester);
              expect(harness.theme.brand.id, id);
              expect(preferences.getString('active_brand'), id);
              await harness.expectOneMappedImport();
            }

            await expectResultRetained(AppBrands.liquidGlass);
            await _capture(tester, harness, scenario, 'result-glass');
            await switchResultBrand('defaultBrand');
            await expectResultRetained(AppBrands.defaultBrand);
            I18n.setLocale(scenario.locale);
            await _settle(tester);
            await expectResultRetained(AppBrands.defaultBrand);
            await _capture(tester, harness, scenario, 'result-default');
            await switchResultBrand('liquidGlass');
            await expectResultRetained(AppBrands.liquidGlass);
            I18n.setLocale(scenario.otherLocale);
            await _settle(tester);
            await expectResultRetained(AppBrands.liquidGlass);
            await switchResultBrand('defaultBrand');
            await expectResultRetained(AppBrands.defaultBrand);
            I18n.setLocale(scenario.locale);
            await _settle(tester);
            await expectResultRetained(AppBrands.defaultBrand);
            await _tap(
              tester,
              _dialogButton(result, FilledButton, DataSettingsUiCopy.gotIt),
            );
            expect(find.byType(AppDialog), findsNothing);
            expect(
              find.descendant(
                of: find.byType(SnackBar),
                matching: find.text(
                  DataSettingsUiCopy.importSuccessBanner(
                    DataSettingsUiCopy.sourceTickTick,
                    1,
                    0,
                    '',
                  ),
                ),
              ),
              findsOneWidget,
            );
            await harness.expectOneMappedImport();
            expect(harness.todos.todos.single.toJson(), importedData);
            expect(preferences.getString('todos'), persistedTodos);
            expect(harness.store.businessMutations, businessMutations);
          },
          scenario: scenario,
          confirmedImport: true,
        );
      },
    );
  }

  testWidgets(
    'file source chooser passes selected source and mapped title to real preview without importing',
    (tester) async {
      await _withHarness(tester, (harness) async {
        await harness.openChooser(tester);
        await _selectTickTick(tester);
        await _saveTitleMapping(tester);
        await harness.switchBrand(tester, 'liquidGlass');
        I18n.setLocale(AppLocale.en);
        await _settle(tester);
        _expectChooserTheme(tester, AppBrands.liquidGlass);
        final route = ModalRoute.of(tester.element(_chooser()));
        await _tap(
          tester,
          _dialogButton(
            _chooser(),
            FilledButton,
            DataSettingsUiCopy.importCompetitorFileSourceAction,
          ),
        );
        final preview = _dialog(DataSettingsUiCopy.importPreviewTitle);
        expect(preview, findsOneWidget);
        expect(ModalRoute.of(tester.element(preview)), isNot(same(route)));
        expect(
          find.descendant(
            of: preview,
            matching: find.textContaining('TickTick'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: preview,
            matching: find.textContaining(_mappingSummary()),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: preview,
            matching: find.textContaining(_mappedTitle),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: preview,
            matching: find.textContaining(_fallbackTitle),
          ),
          findsNothing,
          reason:
              'Saved title mapping must reach the production parser, not only the chooser summary.',
        );
        harness.expectNoImport();
        await _tap(
          tester,
          _dialogButton(preview, TextButton, I18n.tr('action.cancel')),
        );
        expect(find.byType(AppDialog), findsNothing);
        expect(find.byType(BackupScreen), findsOneWidget);
      });
    },
  );

  testWidgets(
    'cancelled mapping edits preserve previous mapping and selected file source',
    (tester) async {
      await _withHarness(tester, (harness) async {
        await harness.openChooser(tester);
        await _selectTickTick(tester);
        await _saveTitleMapping(tester);
        await _openMapping(tester);
        await tester.enterText(_mappingTitleInput(), 'discarded_column');
        await _tap(
          tester,
          _dialogButton(_mapping(), TextButton, I18n.tr('action.cancel')),
        );
        expect(
          find.descendant(
            of: _chooser(),
            matching: find.text(_mappingSummary()),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('discarded_column'), findsNothing);
        await _openMapping(tester);
        expect(
          tester.widget<TextField>(_mappingTitleInput()).controller!.text,
          _mappingColumn,
        );
        await _tap(
          tester,
          _dialogButton(_mapping(), TextButton, I18n.tr('action.cancel')),
        );
        expect(
          find.descendant(
            of: _chooser(),
            matching: find.text(DataSettingsUiCopy.hintTickTick),
          ),
          findsOneWidget,
        );
        await _tap(
          tester,
          _dialogButton(_chooser(), TextButton, I18n.tr('action.cancel')),
        );
      });
    },
  );

  testWidgets(
    'confirmed file preview imports mapped title into original provider with TickTick feedback',
    (tester) async {
      await _withHarness(tester, (harness) async {
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        final screen = find.byType(BackupScreen);
        final screenState = tester.state(screen);
        expect(
          tester.element(screen).read<TodoProvider>(),
          same(harness.todos),
        );
        await harness.openChooser(tester);
        await _selectTickTick(tester);
        await _saveTitleMapping(tester);
        await _tap(
          tester,
          _dialogButton(
            _chooser(),
            FilledButton,
            DataSettingsUiCopy.importCompetitorFileSourceAction,
          ),
        );
        final preview = _dialog(DataSettingsUiCopy.importPreviewTitle);
        expect(preview, findsOneWidget);
        expect(
          find.descendant(
            of: preview,
            matching: find.text(
              DataSettingsUiCopy.importPreviewSource(
                DataSettingsUiCopy.sourceTickTick,
                'JSON',
              ),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: preview,
            matching: find.text(
              DataSettingsUiCopy.importPreviewMapping(_mappingSummary()),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: preview,
            matching: find.textContaining(_mappedTitle),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: preview,
            matching: find.textContaining(_fallbackTitle),
          ),
          findsNothing,
        );
        final confirm = _dialogButton(
          preview,
          FilledButton,
          DataSettingsUiCopy.confirmImport,
        );
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        harness.expectNoImport();
        final policy = find.descendant(
          of: preview,
          matching: find.widgetWithText(
            CheckboxListTile,
            DataSettingsUiCopy.confirmImportPolicyCheckbox,
          ),
        );
        expect(tester.widget<CheckboxListTile>(policy).value, isFalse);
        await _tap(tester, policy);
        expect(tester.widget<CheckboxListTile>(policy).value, isTrue);
        expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
        harness.expectNoImport();
        await _tap(tester, confirm);
        final completed = _dialog(DataSettingsUiCopy.importCompletedTitle);
        for (
          var frame = 0;
          frame < 100 && completed.evaluate().isEmpty;
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await _settle(tester);
        expect(completed, findsOneWidget);
        expect(preview, findsNothing);
        expect(
          find.descendant(
            of: completed,
            matching: find.text('${DataSettingsUiCopy.sourceTickTick} · JSON'),
          ),
          findsOneWidget,
        );
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        expect(tester.state(screen), same(screenState));
        expect(
          tester.element(screen).read<TodoProvider>(),
          same(harness.todos),
        );
        await harness.expectOneMappedImport();
        await _tap(
          tester,
          _dialogButton(completed, FilledButton, DataSettingsUiCopy.gotIt),
        );
        expect(find.byType(AppDialog), findsNothing);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(
              DataSettingsUiCopy.importSuccessBanner(
                DataSettingsUiCopy.sourceTickTick,
                1,
                0,
                '',
              ),
            ),
          ),
          findsOneWidget,
        );
        await harness.expectOneMappedImport();
      }, confirmedImport: true);
    },
  );

  testWidgets(
    'provider-only replacement rejects retained chooser continue without account invalidation',
    (tester) async {
      await _withHarness(tester, (harness) async {
        await harness.openChooser(tester);
        final screen = find.byType(BackupScreen);
        final screenState = tester.state(screen);
        final screenRoute = ModalRoute.of(tester.element(screen));
        final chooserRoute = ModalRoute.of(tester.element(_chooser()));
        final callback = tester
            .widget<FilledButton>(
              _dialogButton(
                _chooser(),
                FilledButton,
                DataSettingsUiCopy.importCompetitorFileSourceAction,
              ),
            )
            .onPressed!;
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        harness.useReplacement.value = true;
        await _settle(tester);
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        expect(tester.state(screen), same(screenState));
        expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
        expect(
          tester.element(screen).read<TodoProvider>(),
          same(harness.replacementTodos),
        );
        expect(ModalRoute.of(tester.element(_chooser())), same(chooserRoute));
        callback();
        await _settle(tester);
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        expect(ModalRoute.of(tester.element(_chooser())), same(chooserRoute));
        expect(chooserRoute!.isCurrent, isTrue);
        expect(_mapping(), findsNothing);
        expect(find.text(DataSettingsUiCopy.importPreviewTitle), findsNothing);
        expect(
          find.text(DataSettingsUiCopy.importCompletedTitle),
          findsNothing,
        );
        expect(find.byType(SnackBar), findsNothing);
        harness.expectNoImport();
      });
    },
  );

  testWidgets(
    'held file picker return after originating route replacement has no effects',
    (tester) async {
      await _withHarness(tester, (harness) async {
        final screen = find.byType(BackupScreen);
        final screenState = tester.state(screen);
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        harness.selector.holdNextOpen();
        await harness.startFileSelection(tester);
        expect(harness.selector.heldOpenStarted, isTrue);
        expect(find.byType(AppDialog), findsNothing);
        unawaited(
          harness.navigatorKey.currentState!.pushReplacement<void, void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Center(child: Text(_coverText))),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text(_coverText), findsOneWidget);
        expect(find.byType(BackupScreen, skipOffstage: false), findsNothing);
        expect(screenState.mounted, isFalse);
        harness.selector.release();
        await _settle(tester);
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        expect(harness.selector.opens, 1);
        expect(find.text(_coverText), findsOneWidget);
        expect(find.byType(AppDialog, skipOffstage: false), findsNothing);
        expect(find.text(DataSettingsUiCopy.importPreviewTitle), findsNothing);
        expect(
          find.text(DataSettingsUiCopy.importCompletedTitle),
          findsNothing,
        );
        expect(find.byType(SnackBar), findsNothing);
        harness.expectNoImport();
      });
    },
  );

  testWidgets(
    'held file picker return after provider-only replacement has no effects',
    (tester) async {
      await _withHarness(tester, (harness) async {
        final screen = find.byType(BackupScreen);
        final screenState = tester.state(screen);
        final screenRoute = ModalRoute.of(tester.element(screen));
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        harness.selector.holdNextOpen();
        await harness.startFileSelection(tester);
        expect(harness.selector.heldOpenStarted, isTrue);
        expect(find.byType(AppDialog), findsNothing);
        harness.useReplacement.value = true;
        await _settle(tester);
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        expect(tester.state(screen), same(screenState));
        expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
        expect(
          tester.element(screen).read<TodoProvider>(),
          same(harness.replacementTodos),
        );
        harness.selector.release();
        await _settle(tester);
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        expect(tester.state(screen), same(screenState));
        expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
        expect(screenRoute!.isCurrent, isTrue);
        expect(harness.selector.opens, 1);
        expect(find.byType(AppDialog, skipOffstage: false), findsNothing);
        expect(find.text(DataSettingsUiCopy.importPreviewTitle), findsNothing);
        expect(
          find.text(DataSettingsUiCopy.importCompletedTitle),
          findsNothing,
        );
        expect(find.byType(SnackBar), findsNothing);
        harness.expectNoImport();
      });
    },
  );

  testWidgets(
    'retained source continue and cancel cannot pop a covering route',
    (tester) async {
      await _withHarness(tester, (harness) async {
        await harness.openChooser(tester);
        final route = ModalRoute.of(tester.element(_chooser()));
        final continueCallback = tester
            .widget<FilledButton>(
              _dialogButton(
                _chooser(),
                FilledButton,
                DataSettingsUiCopy.importCompetitorFileSourceAction,
              ),
            )
            .onPressed!;
        final cancelCallback = tester
            .widget<TextButton>(
              _dialogButton(_chooser(), TextButton, I18n.tr('action.cancel')),
            )
            .onPressed!;
        for (final callback in [continueCallback, cancelCallback]) {
          await _cover(tester, harness);
          callback();
          await _settle(tester);
          expect(find.text(_coverText), findsOneWidget);
          harness.expectNoImport();
          harness.navigatorKey.currentState!.pop();
          await _settle(tester);
          expect(ModalRoute.of(tester.element(_chooser())), same(route));
        }
        await _tap(
          tester,
          _dialogButton(_chooser(), TextButton, I18n.tr('action.cancel')),
        );
      });
    },
  );

  testWidgets(
    'disposed chooser callbacks cannot close another route or reopen mapping',
    (tester) async {
      await _withHarness(tester, (harness) async {
        await harness.openChooser(tester);
        final continueCallback = tester
            .widget<FilledButton>(
              _dialogButton(
                _chooser(),
                FilledButton,
                DataSettingsUiCopy.importCompetitorFileSourceAction,
              ),
            )
            .onPressed!;
        final cancelCallback = tester
            .widget<TextButton>(
              _dialogButton(_chooser(), TextButton, I18n.tr('action.cancel')),
            )
            .onPressed!;
        final mappingCallback = tester
            .widget<OutlinedButton>(
              _dialogButton(
                _chooser(),
                OutlinedButton,
                DataSettingsUiCopy.advancedFieldMapping,
              ),
            )
            .onPressed!;
        await _tap(
          tester,
          _dialogButton(_chooser(), TextButton, I18n.tr('action.cancel')),
        );
        await _cover(tester, harness);
        continueCallback();
        cancelCallback();
        mappingCallback();
        await _settle(tester);
        expect(find.text(_coverText), findsOneWidget);
        expect(find.byType(AppDialog), findsNothing);
      });
    },
  );

  testWidgets(
    'mapping result after chooser removal cannot update a disposed chooser',
    (tester) async {
      await _withHarness(tester, (harness) async {
        await harness.openChooser(tester);
        final chooserRoute = ModalRoute.of(tester.element(_chooser()))!;
        await _openMapping(tester);
        await tester.enterText(_mappingTitleInput(), _mappingColumn);
        // Removing only the originating route leaves the real editor mounted.
        harness.navigatorKey.currentState!.removeRoute(chooserRoute);
        await _settle(tester);
        expect(_mapping(), findsOneWidget);
        await _tap(
          tester,
          _dialogButton(_mapping(), FilledButton, I18n.tr('action.save')),
        );
        expect(find.byType(AppDialog), findsNothing);
        expect(find.byType(BackupScreen), findsOneWidget);
        expect(find.text(DataSettingsUiCopy.importPreviewTitle), findsNothing);
      });
    },
  );

  testWidgets(
    'obsolete source callback after account invalidation cannot preview or import into replacement provider',
    (tester) async {
      await _withHarness(tester, (harness) async {
        await harness.openChooser(tester);
        final screenState = tester.state(find.byType(BackupScreen));
        final callback = tester
            .widget<FilledButton>(
              _dialogButton(
                _chooser(),
                FilledButton,
                DataSettingsUiCopy.importCompetitorFileSourceAction,
              ),
            )
            .onPressed!;
        final originalGeneration =
            AccountLocalDataCleaner.accountDataGeneration;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        harness.useReplacement.value = true;
        await _settle(tester);
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          greaterThan(originalGeneration),
        );
        expect(tester.state(find.byType(BackupScreen)), same(screenState));
        expect(
          tester.element(find.byType(BackupScreen)).read<TodoProvider>(),
          same(harness.replacementTodos),
        );
        callback();
        await _settle(tester);
        expect(find.text(DataSettingsUiCopy.importPreviewTitle), findsNothing);
        expect(
          find.text(DataSettingsUiCopy.importCompletedTitle),
          findsNothing,
        );
        harness.expectNoImport();
      });
    },
  );
  _originTests101();
  _originTests109();
  _originTests115();
}

// Revision 101 adds a separate harness so the original 18 cases, their
// assertions and their optional screenshot batch remain unchanged.
const _originAccount101 = AuthState(
  userId: 'backup-origin-101',
  username: 'backup-origin-101',
  token: 'synthetic-backup-origin-101',
);

class _OriginStore101 extends _RecordingStore {
  _OriginStore101(super.data);

  Completer<void>? _readGate;
  bool heldReadStarted = false;
  int reads = 0;

  void holdNextRead() {
    if (_readGate != null) {
      throw StateError('A preference read is already held');
    }
    _readGate = Completer<void>();
    heldReadStarted = false;
  }

  void releaseRead() {
    final gate = _readGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    final gate = _readGate;
    if (gate != null) {
      heldReadStarted = true;
      await gate.future;
      if (identical(_readGate, gate)) _readGate = null;
    }
    return super.getAll();
  }
}

class _OriginTodos101 extends _RecordingTodos {
  int publicLoads = 0;
  int externalUpdates = 0;
  int queuedOperationEntries = 0;

  @override
  Future<void> loadFromStorage({bool force = false}) {
    publicLoads++;
    return super.loadFromStorage(force: force);
  }

  @override
  Future<T> runExternalStorageUpdate<T>(
    Future<T> Function() operation, {
    int? expectedAccountDataGeneration,
  }) {
    externalUpdates++;
    return super.runExternalStorageUpdate<T>(() {
      queuedOperationEntries++;
      return operation();
    }, expectedAccountDataGeneration: expectedAccountDataGeneration);
  }
}

class _OriginHarness101 {
  _OriginHarness101(this.store) {
    todos.scheduler = base.reminderScheduler;
    replacementTodos.scheduler = base.reminderScheduler;
    auth = AuthProvider(
      initialState: _originAccount101,
      client: ApiClient(
        baseUrl: 'https://backup-origin.example.test',
        token: _originAccount101.token,
        httpClient: MockClient(respond),
      ),
    );
    update = AppUpdateService(
      repo: 'synthetic/backup-origin',
      currentVersion: '1.0.0',
      currentVersionCode: 10000,
      backendBaseUrl: 'https://backup-origin.example.test',
      httpClient: MockClient(respond),
    );
    lock.addListener(_syncAccess);
    update.addListener(_syncAccess);
  }

  final base = _Harness();
  final _OriginStore101 store;
  final todos = _OriginTodos101();
  final replacementTodos = _OriginTodos101();
  final lock = AppLockProvider();
  final routes = AppAccessRouteGate();
  late final AuthProvider auth;
  late final AppUpdateService update;
  final requests = <String>[];
  bool forceUpdate = false;
  Completer<void>? _snapshotGate;
  Future<void>? _snapshotLane;
  Future<void>? queuedLoad;
  bool snapshotLaneStarted = false;
  int clipboardWrites = 0;

  Future<http.Response> respond(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    final Map<String, Object?> data;
    switch (request.url.path) {
      case '/api/auth/login':
        // Same token deliberately avoids AuthProvider's account cleanup path.
        // The real login still advances sessionGeneration and replaces client.
        data = _originAccount101.toJson();
        break;
      case '/api/config':
        data = {
          'api_contract_version': ApiClient.requiredApiContractVersion,
          'required_routes_hash': ApiClient.requiredApiContractRoutesHash,
          'config': <String, Object?>{},
        };
        break;
      case '/api/mobile/apps/duoyi/update':
        data = {
          'api_contract_version': ApiClient.requiredApiContractVersion,
          'required_routes_hash': ApiClient.requiredApiContractRoutesHash,
          'available': forceUpdate,
          'latest_version_name': forceUpdate ? '2.0.0' : '1.0.0',
          'latest_version_code': forceUpdate ? 20000 : 10000,
          'minimum_supported_version': forceUpdate ? '2.0.0' : '1.0.0',
          'minimum_supported_version_code': forceUpdate ? 20000 : 10000,
          'force_update_required': forceUpdate,
          'force_update': forceUpdate,
          'release_notes': 'Synthetic backup-origin policy',
          'download_url':
              'https://backup-origin.example.test/duoyi-${forceUpdate ? '2.0.0' : '1.0.0'}.apk',
        };
        break;
      default:
        throw StateError('Unexpected synthetic HTTP request: ${request.url}');
    }
    return http.Response(
      jsonEncode(data),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }

  void _syncAccess() => routes.setBlocked(lock.isLocked || update.mustUpdate);

  Widget get app => ValueListenableBuilder<bool>(
    valueListenable: base.useReplacement,
    builder: (context, replace, _) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: base.theme),
        ChangeNotifierProvider<TodoProvider>.value(
          value: replace ? replacementTodos : todos,
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AppLockProvider>.value(value: lock),
        ChangeNotifierProvider<AppUpdateService>.value(value: update),
        Provider<AppAccessRouteGate>.value(value: routes),
        ChangeNotifierProvider<HabitProvider>.value(value: base.habits),
        ChangeNotifierProvider<PomodoroProvider>.value(value: base.pomodoro),
        ChangeNotifierProvider<NoteProvider>.value(value: base.notes),
        ChangeNotifierProvider<AnniversaryProvider>.value(
          value: base.anniversaries,
        ),
        ChangeNotifierProvider<DiaryProvider>.value(value: base.diary),
        ChangeNotifierProvider<GoalProvider>.value(value: base.goals),
        ChangeNotifierProvider<CourseProvider>.value(value: base.courses),
        ChangeNotifierProvider<UserProvider>.value(value: base.users),
        ChangeNotifierProvider<TimeAuditProvider>.value(value: base.timeAudit),
        ChangeNotifierProvider<AchievementProvider>.value(
          value: base.achievements,
        ),
        ChangeNotifierProvider<ShareProvider>.value(value: base.shares),
        ChangeNotifierProvider<CalendarProvider>.value(value: base.calendar),
        ChangeNotifierProvider<CountdownProvider>.value(value: base.countdowns),
        ChangeNotifierProvider<LocationReminderProvider>.value(
          value: base.locationReminders,
        ),
        ChangeNotifierProvider<PreferencesProvider>.value(
          value: base.preferences,
        ),
        ChangeNotifierProvider<QuickCaptureTemplateProvider>.value(
          value: base.quickCaptureTemplates,
        ),
      ],
      child: AnimatedBuilder(
        animation: Listenable.merge([
          base.theme,
          I18n.localeListenable,
          lock,
          update,
        ]),
        builder: (context, _) => MaterialApp(
          navigatorKey: base.navigatorKey,
          navigatorObservers: [routes],
          locale: Locale(I18n.current == AppLocale.en ? 'en' : 'zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: base.theme.brand.theme,
          builder: (context, child) => AppAccessLayer(
            locked: lock.isLocked,
            mustUpdate: update.mustUpdate,
            routes: routes,
            lockOverlay: const Center(child: Text('Origin 101 locked')),
            updateOverlay: const Center(
              child: Text('Origin 101 update required'),
            ),
            child: child!,
          ),
          home: const BrandRouteSurface(
            remountOnLocaleChange: false,
            child: BackupScreen(initialMode: BackupEntryMode.restore),
          ),
        ),
      ),
    ),
  );

  Future<void> holdSnapshotLane(WidgetTester tester) async {
    if (_snapshotGate != null) throw StateError('Snapshot lane already held');
    final gate = _snapshotGate = Completer<void>();
    snapshotLaneStarted = false;
    _snapshotLane = LocationReminderStorage.run<void>(() async {
      snapshotLaneStarted = true;
      await gate.future;
    });
    await _until101(tester, () => snapshotLaneStarted);
  }

  void releaseSnapshot() {
    final gate = _snapshotGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void expectNoImport({bool allowSessionWrites = false}) {
    expect(todos.importCalls, 0);
    expect(replacementTodos.importCalls, 0);
    expect(todos.todos, isEmpty);
    expect(replacementTodos.todos, isEmpty);
    expect(base.anniversaries.items, isEmpty);
    expect(base.countdowns.items, isEmpty);
    expect(
      store.businessMutations.where(
        (mutation) =>
            !allowSessionWrites ||
            (mutation != 'set:flutter.auth_state' &&
                mutation !=
                    'set:flutter.${AccountLocalDataCleaner.accountDataOwnerKey}'),
      ),
      isEmpty,
    );
    expect(clipboardWrites, 0);
  }

  void dispose() {
    lock.removeListener(_syncAccess);
    update.removeListener(_syncAccess);
    routes.dispose();
    auth.dispose();
    lock.dispose();
    update.dispose();
    todos.dispose();
    replacementTodos.dispose();
    base.dispose();
  }
}

// Pump a bounded number of frames without draining an intentionally held queue
// or waiting for the busy spinner to stop. Normal settling follows release.
Future<void> _frames101(WidgetTester tester, {int count = 8}) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> _until101(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 100 && !ready(); frame++) {
    await _frames101(tester, count: 1);
  }
  expect(
    ready(),
    isTrue,
    reason: 'Real asynchronous flow did not reach its gate',
  );
}

Future<void> _withOrigin101(
  WidgetTester tester,
  Future<void> Function(_OriginHarness101 harness) body,
) async {
  final oldLocale = I18n.current;
  final oldTimeZoneReader = LocalTimezoneResolver.debugSystemTimeZoneReader;
  final oldSelector = FileSelectorPlatform.instance;
  final oldStore = SharedPreferencesStorePlatform.instance;
  final initial = <String, Object>{
    'active_brand': 'defaultBrand',
    'theme_shop_state': jsonEncode({
      'activeBrand': 'defaultBrand',
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    'auth_state': jsonEncode(_originAccount101.toJson()),
    AccountLocalDataCleaner.accountDataOwnerKey:
        'id:${_originAccount101.userId}',
  };
  SharedPreferences.setMockInitialValues(initial);
  final harness = _OriginHarness101(
    _OriginStore101({
      for (final entry in initial.entries) 'flutter.${entry.key}': entry.value,
    }),
  );
  SharedPreferencesStorePlatform.instance = harness.store;
  FileSelectorPlatform.instance = harness.base.selector;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') harness.clipboardWrites++;
        return null;
      });
  await http.runWithClient(() async {
    try {
      I18n.setLocale(AppLocale.en);
      LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
          'Asia/Shanghai';
      await tester.runAsync(loadWeeklyReviewScreenshotFonts);
      await harness.base.theme.loadFromStorage();
      await harness.lock.loadFromStorage();
      expect(await harness.lock.setPin('123456'), isTrue);
      expect(harness.lock.isLocked, isFalse);
      await AccountPreferenceWrites.drain();
      // Exclude only real PIN setup, before any UI workflow starts.
      harness.store.businessMutations.clear();
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(harness.app);
      await _settle(tester);
      harness.expectNoImport();
      expect(harness.routes.registeredRouteCount, 1);
      await body(harness);
      await _settle(tester);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.base.selector.release();
        harness.releaseSnapshot();
        harness.store.releaseRead();
        await _frames101(tester);
        await harness._snapshotLane;
        await harness.queuedLoad;
        await _settle(tester);
      } finally {
        harness.dispose();
        tester.view.reset();
        I18n.setLocale(oldLocale);
        LocalTimezoneResolver.debugSystemTimeZoneReader = oldTimeZoneReader;
        FileSelectorPlatform.instance = oldSelector;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    }
  }, () => MockClient(harness.respond));
}

Finder _fileButton101() => find.widgetWithText(
  OutlinedButton,
  DataSettingsUiCopy.importProductivityFileButton,
);

Future<void> _openFile101(
  WidgetTester tester,
  _OriginHarness101 harness,
) async {
  await tester.scrollUntilVisible(
    _fileButton101(),
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await _tap(tester, _fileButton101());
}

Future<void> _filePreview101(
  WidgetTester tester,
  _OriginHarness101 harness,
) async {
  await _openFile101(tester, harness);
  expect(_chooser(), findsOneWidget);
  await _selectTickTick(tester);
  await _saveTitleMapping(tester);
  await _tap(
    tester,
    _dialogButton(
      _chooser(),
      FilledButton,
      DataSettingsUiCopy.importCompetitorFileSourceAction,
    ),
  );
  _expectMappedPreview101();
}

void _expectMappedPreview101() {
  final preview = _dialog(DataSettingsUiCopy.importPreviewTitle);
  expect(preview, findsOneWidget);
  expect(
    find.descendant(of: preview, matching: find.textContaining(_mappedTitle)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: preview, matching: find.textContaining(_fallbackTitle)),
    findsNothing,
  );
  expect(
    find.descendant(
      of: preview,
      matching: find.textContaining(_mappingSummary()),
    ),
    findsOneWidget,
  );
}

Future<void> _tasksPreview101(WidgetTester tester) async {
  final button = find.widgetWithText(
    OutlinedButton,
    DataSettingsUiCopy.importTasksFromOtherAppsButton,
  );
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await _tap(tester, button);
  final paste = _dialog(DataSettingsUiCopy.competitorImportDialogTitle(true));
  expect(paste, findsOneWidget);
  final source = find.descendant(
    of: paste,
    matching: find.byWidgetPredicate((widget) => widget is AppDropdownField),
  );
  await _tap(tester, source);
  await _tap(
    tester,
    find.text(DataSettingsUiCopy.sourceTickTick).hitTestable(),
  );
  await _tap(
    tester,
    _dialogButton(
      paste,
      OutlinedButton,
      DataSettingsUiCopy.advancedFieldMapping,
    ),
  );
  await tester.ensureVisible(_mappingTitleInput());
  await tester.enterText(_mappingTitleInput(), _mappingColumn);
  await _tap(
    tester,
    _dialogButton(_mapping(), FilledButton, I18n.tr('action.save')),
  );
  expect(
    find.descendant(of: paste, matching: find.text(_mappingSummary())),
    findsOneWidget,
  );
  final input = find.descendant(of: paste, matching: find.byType(TextField));
  await tester.ensureVisible(input);
  await tester.enterText(input, _fileContents);
  await _tap(
    tester,
    _dialogButton(
      paste,
      FilledButton,
      DataSettingsUiCopy.competitorImportPreviewAction(true),
    ),
  );
  _expectMappedPreview101();
}

Future<Finder> _enableConfirm101(WidgetTester tester) async {
  final preview = _dialog(DataSettingsUiCopy.importPreviewTitle);
  final confirm = _dialogButton(
    preview,
    FilledButton,
    DataSettingsUiCopy.confirmImport,
  );
  expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
  await _tap(
    tester,
    find.descendant(
      of: preview,
      matching: find.widgetWithText(
        CheckboxListTile,
        DataSettingsUiCopy.confirmImportPolicyCheckbox,
      ),
    ),
  );
  expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  await tester.ensureVisible(confirm);
  await _settle(tester);
  return confirm;
}

Future<void> _beginHeldSnapshot101(
  WidgetTester tester,
  _OriginHarness101 harness,
) async {
  final confirm = await _enableConfirm101(tester);
  await harness.holdSnapshotLane(tester);
  await tester.tap(confirm);
  await _until101(
    tester,
    () =>
        _dialog(DataSettingsUiCopy.importPreviewTitle).evaluate().isEmpty &&
        tester.widget<OutlinedButton>(_fileButton101()).onPressed == null,
  );
  expect(harness.snapshotLaneStarted, isTrue);
  harness.expectNoImport();
}

Future<void> _expectMappedImport101(
  _OriginHarness101 harness, {
  bool replacement = false,
}) async {
  final owner = replacement ? harness.replacementTodos : harness.todos;
  final other = replacement ? harness.todos : harness.replacementTodos;
  expect(owner.importCalls, 1);
  expect(owner.receivedTitles, [
    [_mappedTitle],
  ]);
  expect(owner.todos.single.title, _mappedTitle);
  expect(other.importCalls, 0);
  expect(other.todos, isEmpty);
  expect(harness.base.anniversaries.items, isEmpty);
  expect(harness.base.countdowns.items, isEmpty);
  expect(
    harness.store.businessMutations.where(
      (item) => item == 'set:flutter.todos',
    ),
    hasLength(1),
  );
  final prefs = await SharedPreferences.getInstance();
  final saved = jsonDecode(prefs.getString('todos')!) as List<dynamic>;
  expect(saved, hasLength(1));
  expect((saved.single as Map<String, dynamic>)['title'], _mappedTitle);
  expect(harness.clipboardWrites, 0);
}

Future<void> _awaitResult101(WidgetTester tester) async {
  await _until101(
    tester,
    () =>
        _dialog(DataSettingsUiCopy.importCompletedTitle).evaluate().isNotEmpty,
  );
  await _settle(tester);
  expect(_dialog(DataSettingsUiCopy.importCompletedTitle), findsOneWidget);
}

void _expectNoFeedback101() {
  expect(find.byType(AppDialog, skipOffstage: false), findsNothing);
  expect(find.byType(SnackBar), findsNothing);
}

enum _SnapshotRevocation101 { lock, update, session }

enum _UndoRevocation101 { provider, cover, lock }

void _originTests101() {
  testWidgets(
    '101 held picker cover and uncover permanently rejects obsolete result and permits fresh mapped file',
    (tester) async {
      await _withOrigin101(tester, (harness) async {
        final screen = find.byType(BackupScreen);
        final state = tester.state(screen);
        final route = ModalRoute.of(tester.element(screen))!;
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        harness.base.selector.holdNextOpen();
        await _openFile101(tester, harness);
        expect(harness.base.selector.heldOpenStarted, isTrue);
        await _cover(tester, harness.base);
        expect(route.isCurrent, isFalse);
        harness.base.navigatorKey.currentState!.pop();
        await _settle(tester);
        expect(route.isCurrent, isTrue);
        expect(tester.state(screen), same(state));
        harness.base.selector.release();
        await _settle(tester);
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        expect(harness.base.selector.opens, 1);
        _expectNoFeedback101();
        harness.expectNoImport();
        await _filePreview101(tester, harness);
        expect(harness.base.selector.opens, 2);
        harness.expectNoImport();
        await _tap(
          tester,
          _dialogButton(
            _dialog(DataSettingsUiCopy.importPreviewTitle),
            TextButton,
            I18n.tr('action.cancel'),
          ),
        );
        harness.expectNoImport();
      });
    },
  );

  for (final revocation in _SnapshotRevocation101.values) {
    testWidgets(
      '101 tasks-only held snapshot rejects ${revocation.name} revocation after access returns',
      (tester) async {
        await _withOrigin101(tester, (harness) async {
          final screen = find.byType(BackupScreen);
          final state = tester.state(screen);
          final route = ModalRoute.of(tester.element(screen));
          final generation = AccountLocalDataCleaner.accountDataGeneration;
          final session = harness.auth.sessionGeneration;
          await _tasksPreview101(tester);
          expect(harness.base.selector.opens, 0);
          await _beginHeldSnapshot101(tester, harness);
          switch (revocation) {
            case _SnapshotRevocation101.lock:
              harness.lock.lock();
              await _frames101(tester);
              expect(harness.lock.isLocked, isTrue);
              expect(harness.routes.isBlocked, isTrue);
              expect(find.text('Origin 101 locked'), findsOneWidget);
              await harness.lock.unlockWith('123456');
              break;
            case _SnapshotRevocation101.update:
              harness.forceUpdate = true;
              await tester.runAsync(harness.update.checkNow);
              await _frames101(tester);
              expect(harness.update.mustUpdate, isTrue);
              expect(harness.routes.isBlocked, isTrue);
              expect(find.text('Origin 101 update required'), findsOneWidget);
              harness.forceUpdate = false;
              await tester.runAsync(harness.update.checkNow);
              expect(
                harness.requests.where(
                  (request) => request == 'GET /api/mobile/apps/duoyi/update',
                ),
                hasLength(2),
              );
              break;
            case _SnapshotRevocation101.session:
              // Auth's writeback tail belongs to this widget-test fake zone.
              // Start and observe login here, then let bounded pumps drive it
              // while the actual snapshot lane remains held.
              var loginSettled = false;
              Object? loginError;
              StackTrace? loginStack;
              final login = harness.auth.login(
                username: _originAccount101.username!,
                password: 'synthetic-pin',
              );
              final observedLogin = login.then<void>(
                (_) {
                  loginSettled = true;
                },
                onError: (Object error, StackTrace stack) {
                  loginError = error;
                  loginStack = stack;
                  loginSettled = true;
                },
              );
              await _until101(tester, () => loginSettled);
              await observedLogin;
              if (loginError != null) {
                Error.throwWithStackTrace(loginError!, loginStack!);
              }
              await _frames101(tester);
              expect(harness.auth.sessionGeneration, greaterThan(session));
              expect(harness.auth.state.userId, _originAccount101.userId);
              expect(harness.auth.state.token, _originAccount101.token);
              expect(harness.auth.isAccountTransitionInProgress, isFalse);
              expect(harness.requests, contains('POST /api/auth/login'));
              break;
          }
          await _frames101(tester);
          expect(harness.routes.isBlocked, isFalse);
          expect(harness.lock.isLocked, isFalse);
          expect(harness.update.mustUpdate, isFalse);
          expect(AccountLocalDataCleaner.accountDataGeneration, generation);
          expect(tester.state(screen), same(state));
          expect(ModalRoute.of(tester.element(screen)), same(route));
          expect(
            tester.element(screen).read<TodoProvider>(),
            same(harness.todos),
          );
          harness.releaseSnapshot();
          await _settle(tester);
          harness.expectNoImport(
            allowSessionWrites: revocation == _SnapshotRevocation101.session,
          );
          _expectNoFeedback101();
          expect(
            tester.widget<OutlinedButton>(_fileButton101()).onPressed,
            isNotNull,
          );
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('todos'), isNull);
        });
      },
    );
  }

  testWidgets(
    '101 provider replacement cancels held apply releases busy and imports through fresh mapped flow',
    (tester) async {
      await _withOrigin101(tester, (harness) async {
        final screen = find.byType(BackupScreen);
        final state = tester.state(screen);
        final route = ModalRoute.of(tester.element(screen));
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        await _filePreview101(tester, harness);
        await _beginHeldSnapshot101(tester, harness);
        harness.base.useReplacement.value = true;
        await _frames101(tester);
        expect(tester.state(screen), same(state));
        expect(ModalRoute.of(tester.element(screen)), same(route));
        expect(
          tester.element(screen).read<TodoProvider>(),
          same(harness.replacementTodos),
        );
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        harness.releaseSnapshot();
        await _settle(tester);
        harness.expectNoImport();
        _expectNoFeedback101();
        expect(
          tester.widget<OutlinedButton>(_fileButton101()).onPressed,
          isNotNull,
        );
        await _filePreview101(tester, harness);
        final confirm = await _enableConfirm101(tester);
        await tester.tap(confirm);
        await _awaitResult101(tester);
        await _expectMappedImport101(harness, replacement: true);
        expect(harness.base.selector.opens, 2);
        await _tap(
          tester,
          _dialogButton(
            _dialog(DataSettingsUiCopy.importCompletedTitle),
            FilledButton,
            DataSettingsUiCopy.gotIt,
          ),
        );
        expect(
          find.text(
            DataSettingsUiCopy.importSuccessBanner(
              DataSettingsUiCopy.sourceTickTick,
              1,
              0,
              '',
            ),
          ),
          findsOneWidget,
        );
        await _expectMappedImport101(harness, replacement: true);
      });
    },
  );

  for (final revocation in _UndoRevocation101.values) {
    testWidgets(
      '101 original Undo queued behind real load rejects ${revocation.name} revocation without restore effects or successor reload',
      (tester) async {
        await _withOrigin101(tester, (harness) async {
          await _filePreview101(tester, harness);
          final confirm = await _enableConfirm101(tester);
          await tester.tap(confirm);
          await _awaitResult101(tester);
          await _expectMappedImport101(harness);
          final screen = find.byType(BackupScreen);
          final state = tester.state(screen);
          final screenRoute = ModalRoute.of(tester.element(screen))!;
          final generation = AccountLocalDataCleaner.accountDataGeneration;
          final prefs = await SharedPreferences.getInstance();
          final persisted = prefs.getString('todos');
          final imported = harness.todos.todos.single.toJson();
          final mutations = List<String>.of(harness.store.businessMutations);
          final loads = harness.todos.publicLoads;
          final reads = harness.store.reads;
          final undo = _dialogButton(
            _dialog(DataSettingsUiCopy.importCompletedTitle),
            TextButton,
            DataSettingsUiCopy.undoImport,
          );
          await tester.ensureVisible(undo);
          await _settle(tester);
          // Reset only the plugin singleton, retaining real persisted data.
          // The real forced load reserves TodoProvider's existing write queue.
          SharedPreferences.resetStatic();
          harness.store.holdNextRead();
          harness.queuedLoad = harness.todos.loadFromStorage(force: true);
          await _until101(tester, () => harness.store.heldReadStarted);
          await tester.tap(undo);
          await _until101(tester, () => harness.todos.externalUpdates == 1);
          expect(harness.todos.queuedOperationEntries, 0);
          expect(harness.todos.publicLoads, loads + 1);
          switch (revocation) {
            case _UndoRevocation101.provider:
              harness.base.useReplacement.value = true;
              await _frames101(tester);
              expect(
                tester.element(screen).read<TodoProvider>(),
                same(harness.replacementTodos),
              );
              break;
            case _UndoRevocation101.cover:
              unawaited(
                harness.base.navigatorKey.currentState!.push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Center(child: Text(_coverText))),
                  ),
                ),
              );
              await _frames101(tester);
              expect(screenRoute.isCurrent, isFalse);
              expect(find.text(_coverText), findsOneWidget);
              harness.base.navigatorKey.currentState!.pop();
              await _frames101(tester);
              expect(screenRoute.isCurrent, isTrue);
              break;
            case _UndoRevocation101.lock:
              harness.lock.lock();
              await _frames101(tester);
              expect(harness.routes.isBlocked, isTrue);
              expect(find.text('Origin 101 locked'), findsOneWidget);
              break;
          }
          expect(AccountLocalDataCleaner.accountDataGeneration, generation);
          harness.store.releaseRead();
          await _frames101(tester);
          await harness.queuedLoad;
          if (revocation == _UndoRevocation101.lock) {
            await harness.lock.unlockWith('123456');
          }
          await _settle(tester);
          expect(tester.state(screen), same(state));
          expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
          expect(harness.todos.externalUpdates, 1);
          expect(harness.todos.publicLoads, loads + 1);
          expect(harness.replacementTodos.externalUpdates, 0);
          expect(harness.replacementTodos.publicLoads, 0);
          expect(harness.replacementTodos.importCalls, 0);
          expect(harness.replacementTodos.todos, isEmpty);
          expect(harness.todos.todos.single.toJson(), imported);
          expect(harness.store.businessMutations, mutations);
          expect(harness.store.reads, reads + 1);
          final after = await SharedPreferences.getInstance();
          expect(after.getString('todos'), persisted);
          _expectNoFeedback101();
          expect(
            tester.widget<OutlinedButton>(_fileButton101()).onPressed,
            isNotNull,
          );
        });
      },
    );
  }

  testWidgets(
    '101 positive tasks-only held snapshot imports mapped dropdown choice and real Undo restores snapshot',
    (tester) async {
      await _withOrigin101(tester, (harness) async {
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        await _tasksPreview101(tester);
        await _beginHeldSnapshot101(tester, harness);
        await _frames101(tester);
        harness.expectNoImport();
        harness.releaseSnapshot();
        await _awaitResult101(tester);
        await _expectMappedImport101(harness);
        final result = _dialog(DataSettingsUiCopy.importCompletedTitle);
        expect(
          find.descendant(
            of: result,
            matching: find.text('${DataSettingsUiCopy.sourceTickTick} · JSON'),
          ),
          findsOneWidget,
        );
        final undo = _dialogButton(
          result,
          TextButton,
          DataSettingsUiCopy.undoImport,
        );
        await tester.ensureVisible(undo);
        await _settle(tester);
        await tester.tap(undo);
        await _until101(
          tester,
          () => find
              .text(DataSettingsUiCopy.undoImportSuccess)
              .evaluate()
              .isNotEmpty,
        );
        await _settle(tester);
        expect(harness.todos.externalUpdates, 1);
        expect(harness.todos.queuedOperationEntries, 1);
        expect(harness.todos.importCalls, 1);
        expect(harness.todos.todos, isEmpty);
        expect(harness.replacementTodos.publicLoads, 0);
        expect(harness.replacementTodos.todos, isEmpty);
        expect(
          harness.store.businessMutations,
          contains('remove:flutter.todos'),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('todos'), isNull);
        expect(
          prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey),
          'id:${_originAccount101.userId}',
        );
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        expect(harness.base.selector.opens, 0);
        expect(find.byType(AppDialog), findsNothing);
        expect(find.text(DataSettingsUiCopy.undoImportSuccess), findsOneWidget);
        expect(
          tester.widget<OutlinedButton>(_fileButton101()).onPressed,
          isNotNull,
        );
        expect(harness.clipboardWrites, 0);
      });
    },
  );
}

// Revision 109 is installed at test/screens/backup_source_chooser_live_theme_test.dart.
// The preceding actual 27-case fixture is preserved; these three cases are
// preparation only and require main's serialized validation before acceptance.
const _foreignFieldKey109 = ValueKey('foreign-source-field-109');
const _foreignInitial109 = 'Foreign initial choice 109';
const _foreignSelected109 = 'Foreign selected choice 109';

class _ForeignDropdown109 {
  _ForeignDropdown109({required this.withForeignCallback});

  final bool withForeignCallback;
  final createdRoutes = <Route<dynamic>>{};
  final receivedValues = <String?>[];
  int callbackInvocations = 0;
  OverlayEntry? _entry;

  // This callback belongs only to this unrelated field. It never receives,
  // captures or invokes an import-origin callback or its owner signal.
  void _observeForeignRoute(Route<dynamic> route) {
    callbackInvocations++;
    createdRoutes.add(route);
  }

  void install(_OriginHarness101 harness) {
    if (_entry != null) throw StateError('Foreign dropdown already installed');
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: 40,
        left: 20,
        width: 300,
        child: Material(
          child: AppDropdownField<String>(
            key: _foreignFieldKey109,
            initialValue: 'foreign-initial',
            items: const [
              DropdownMenuItem(
                value: 'foreign-initial',
                child: Text(_foreignInitial109),
              ),
              DropdownMenuItem(
                value: 'foreign-selected',
                child: Text(_foreignSelected109),
              ),
            ],
            onChanged: receivedValues.add,
            onMenuRouteCreated: withForeignCallback
                ? _observeForeignRoute
                : null,
          ),
        ),
      ),
    );
    _entry = entry;
    // Inserting an OverlayEntry does not push a covering Navigator route.
    // Its actual AppDropdownField will perform the single popup push itself.
    harness.base.navigatorKey.currentState!.overlay!.insert(entry);
  }

  void dispose() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.remove();
    entry.dispose();
  }
}

Future<void> _foreignDropdownRevokesPicker109(
  WidgetTester tester,
  _OriginHarness101 harness, {
  required bool withForeignCallback,
}) async {
  final screen = find.byType(BackupScreen);
  final state = tester.state(screen);
  final screenRoute = ModalRoute.of(tester.element(screen))!;
  final generation = AccountLocalDataCleaner.accountDataGeneration;
  final session = harness.auth.sessionGeneration;
  final revision = harness.routes.routeRevision.value;
  final before = await harness.store.getAll();
  final foreign = _ForeignDropdown109(withForeignCallback: withForeignCallback);
  try {
    harness.base.selector.holdNextOpen();
    await _openFile101(tester, harness);
    expect(harness.base.selector.heldOpenStarted, isTrue);
    expect(harness.base.selector.opens, 1);
    expect(harness.routes.routeRevision.value, revision);
    _expectNoFeedback101();
    harness.expectNoImport();

    // Install only once the picker is held, so this unrelated control cannot
    // obscure the import entry button while scrolling to start the real flow.
    foreign.install(harness);
    await _settle(tester);
    expect(harness.routes.routeRevision.value, revision);
    expect(harness.routes.currentRoute, same(screenRoute));
    expect(harness.routes.registeredRouteCount, 1);
    final installedField = tester.widget<AppDropdownField<String>>(
      find.byKey(_foreignFieldKey109),
    );
    expect(
      installedField.onMenuRouteCreated,
      withForeignCallback ? isNotNull : isNull,
    );

    await _tap(tester, find.byKey(_foreignFieldKey109));
    final foreignMenu = harness.routes.currentRoute!;
    expect(foreignMenu, isNot(same(screenRoute)));
    expect(foreignMenu.settings.name, 'AppAnchoredDropdownMenu');
    expect(foreignMenu.isCurrent, isTrue);
    expect(foreignMenu.isActive, isTrue);
    expect(screenRoute.isCurrent, isFalse);
    expect(screenRoute.isActive, isTrue);
    expect(harness.routes.routeRevision.value, revision + 1);
    expect(harness.routes.registeredRouteCount, 2);
    if (withForeignCallback) {
      expect(foreign.callbackInvocations, greaterThan(0));
      expect(foreign.createdRoutes, unorderedEquals([foreignMenu]));
    } else {
      expect(foreign.callbackInvocations, 0);
      expect(foreign.createdRoutes, isEmpty);
    }
    expect(foreign.receivedValues, isEmpty);
    harness.expectNoImport();

    // A real item tap must complete this unrelated field's own selection.
    // Do not simulate the menu by pushing a hand-named MaterialPageRoute.
    await _tap(tester, find.text(_foreignSelected109).hitTestable());
    expect(foreign.receivedValues, ['foreign-selected']);
    expect(
      find.descendant(
        of: find.byKey(_foreignFieldKey109),
        matching: find.text(_foreignSelected109),
      ),
      findsOneWidget,
    );
    expect(harness.routes.currentRoute, same(screenRoute));
    expect(harness.routes.routeRevision.value, revision + 2);
    expect(harness.routes.registeredRouteCount, 1);
    expect(screenRoute.isCurrent, isTrue);
    expect(tester.state(screen), same(state));
    expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
    foreign.dispose();
    await _settle(tester);
    expect(harness.routes.routeRevision.value, revision + 2);

    // The same screen is current again, but the held import has permanently
    // lost authority. A shared menu name or unrelated callback cannot revive it.
    harness.base.selector.release();
    await _settle(tester);
    expect(harness.base.selector.opens, 1);
    expect(harness.routes.currentRoute, same(screenRoute));
    expect(harness.routes.routeRevision.value, revision + 2);
    expect(harness.routes.registeredRouteCount, 1);
    expect(tester.state(screen), same(state));
    expect(tester.element(screen).read<TodoProvider>(), same(harness.todos));
    expect(harness.auth.sessionGeneration, session);
    expect(AccountLocalDataCleaner.accountDataGeneration, generation);
    expect(harness.routes.isBlocked, isFalse);
    _expectNoFeedback101();
    harness.expectNoImport();
    expect(await harness.store.getAll(), before);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos'), isNull);
    expect(harness.todos.externalUpdates, 0);
    expect(harness.replacementTodos.externalUpdates, 0);
    expect(harness.replacementTodos.publicLoads, 0);
  } finally {
    foreign.dispose();
  }
}

void _originTests109() {
  testWidgets(
    '109 successful import SnackBar Undo restores original snapshot exactly once after Got it',
    (tester) async {
      await _withOrigin101(tester, (harness) async {
        final screen = find.byType(BackupScreen);
        final state = tester.state(screen);
        final screenRoute = ModalRoute.of(tester.element(screen))!;
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        final session = harness.auth.sessionGeneration;
        final lockGeneration = harness.lock.accessGeneration;
        final initialPreferences = await SharedPreferences.getInstance();
        expect(initialPreferences.getString('todos'), isNull);
        final owner = initialPreferences.getString(
          AccountLocalDataCleaner.accountDataOwnerKey,
        );
        final authState = initialPreferences.getString('auth_state');
        final brand = initialPreferences.getString('active_brand');
        await _filePreview101(tester, harness);
        final confirm = await _enableConfirm101(tester);
        await tester.tap(confirm);
        await _awaitResult101(tester);
        await _expectMappedImport101(harness);
        expect(harness.todos.externalUpdates, 0);
        await _tap(
          tester,
          _dialogButton(
            _dialog(DataSettingsUiCopy.importCompletedTitle),
            FilledButton,
            DataSettingsUiCopy.gotIt,
          ),
        );
        final snack = find.byType(SnackBar);
        expect(snack, findsOneWidget);
        expect(
          find.descendant(
            of: snack,
            matching: find.text(
              DataSettingsUiCopy.importSuccessBanner(
                DataSettingsUiCopy.sourceTickTick,
                1,
                0,
                '',
              ),
            ),
          ),
          findsOneWidget,
        );
        expect(find.byType(AppDialog, skipOffstage: false), findsNothing);
        expect(harness.routes.currentRoute, same(screenRoute));
        expect(screenRoute.isCurrent, isTrue);
        expect(tester.state(screen), same(state));
        expect(
          tester.element(screen).read<TodoProvider>(),
          same(harness.todos),
        );
        expect(harness.auth.sessionGeneration, session);
        expect(harness.lock.accessGeneration, lockGeneration);
        expect(harness.routes.isBlocked, isFalse);
        final undo = find.descendant(
          of: snack,
          matching: find.widgetWithText(
            SnackBarAction,
            DataSettingsUiCopy.undoImport,
          ),
        );
        expect(undo, findsOneWidget);
        final boundUndo = tester.widget<SnackBarAction>(undo).onPressed;
        await tester.ensureVisible(undo);
        await _settle(tester);
        // Click the actual still-visible SnackBar action after entry finally
        // has returned. Dialog Undo cannot establish this lifetime contract.
        expect(undo.hitTestable(), findsOneWidget);
        await tester.tap(undo);
        await _until101(
          tester,
          () => find
              .text(DataSettingsUiCopy.undoImportSuccess)
              .evaluate()
              .isNotEmpty,
        );
        await _settle(tester);
        expect(harness.todos.importCalls, 1);
        expect(harness.todos.externalUpdates, 1);
        expect(harness.todos.queuedOperationEntries, 1);
        expect(harness.todos.todos, isEmpty);
        expect(harness.replacementTodos.importCalls, 0);
        expect(harness.replacementTodos.externalUpdates, 0);
        expect(harness.replacementTodos.publicLoads, 0);
        expect(harness.replacementTodos.todos, isEmpty);
        expect(harness.base.anniversaries.items, isEmpty);
        expect(harness.base.countdowns.items, isEmpty);
        expect(
          harness.store.businessMutations,
          contains('remove:flutter.todos'),
        );
        final after = await SharedPreferences.getInstance();
        expect(after.getString('todos'), isNull);
        expect(
          after.getString(AccountLocalDataCleaner.accountDataOwnerKey),
          owner,
        );
        expect(after.getString('auth_state'), authState);
        expect(after.getString('active_brand'), brand);
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        expect(harness.auth.sessionGeneration, session);
        expect(tester.state(screen), same(state));
        expect(ModalRoute.of(tester.element(screen)), same(screenRoute));
        expect(harness.routes.currentRoute, same(screenRoute));
        expect(find.byType(AppDialog, skipOffstage: false), findsNothing);
        expect(find.text(DataSettingsUiCopy.undoImportSuccess), findsOneWidget);
        expect(harness.base.selector.opens, 1);
        expect(harness.clipboardWrites, 0);
        expect(
          tester.widget<OutlinedButton>(_fileButton101()).onPressed,
          isNotNull,
        );

        // Retain the original business callback to verify the consumed token
        // cannot enqueue a second restore after its SnackBar has disappeared.
        final mutations = List<String>.of(harness.store.businessMutations);
        final loads = harness.todos.publicLoads;
        boundUndo();
        await _frames101(tester);
        await _settle(tester);
        expect(harness.todos.externalUpdates, 1);
        expect(harness.todos.publicLoads, loads);
        expect(harness.store.businessMutations, mutations);
        expect(after.getString('todos'), isNull);
        expect(harness.replacementTodos.publicLoads, 0);
        expect(find.text(DataSettingsUiCopy.undoImportSuccess), findsOneWidget);
      });
    },
  );

  testWidgets(
    '109 held picker rejects same-name foreign AppDropdownField menu with no route callback',
    (tester) async {
      await _withOrigin101(
        tester,
        (harness) => _foreignDropdownRevokesPicker109(
          tester,
          harness,
          withForeignCallback: false,
        ),
      );
    },
  );

  testWidgets(
    '109 held picker rejects same-name foreign AppDropdownField menu with unrelated owner callback',
    (tester) async {
      await _withOrigin101(
        tester,
        (harness) => _foreignDropdownRevokesPicker109(
          tester,
          harness,
          withForeignCallback: true,
        ),
      );
    },
  );
}

// Revision 115 preserves the released 30-case prefix and adds three cases.
// Preparation only. Main owns formatting, execution and acceptance.
class _Banner115 {
  _Banner115(this.snackBar, this.controller) {
    controller.closed.then((reason) {
      closedReason = reason;
      closed = true;
    });
  }
  final SnackBar snackBar;
  final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller;
  bool closed = false;
  SnackBarClosedReason? closedReason;
}

class _ObservedMessenger115 extends ScaffoldMessenger {
  const _ObservedMessenger115({required super.child, super.key});
  @override
  ScaffoldMessengerState createState() => _ObservedMessengerState115();
}

class _ObservedMessengerState115 extends ScaffoldMessengerState {
  final shown = <_Banner115>[];
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final controller = super.showSnackBar(
      snackBar,
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
    shown.add(_Banner115(snackBar, controller));
    return controller;
  }
}

class _Gate115 {
  final started = Completer<void>();
  final release = Completer<void>();
  void releaseNow() {
    if (!release.isCompleted) release.complete();
  }
}

class _Mutation115 {
  _Mutation115(this.operation, this.key, this.value);
  final String operation;
  final String key;
  final Object? value;
  bool persisted = false;
}

class _LifecycleStore115 extends _OriginStore101 {
  _LifecycleStore115(super.data);
  final mutations = <_Mutation115>[];
  _Gate115? _removeGate;
  final gates = <_Gate115>[];
  _Gate115 holdNextTodoRemoval() {
    if (_removeGate != null) throw StateError('Restore ACK already held');
    final gate = _removeGate = _Gate115();
    gates.add(gate);
    return gate;
  }

  Future<Map<String, Object>> backing() => super.getAll();
  int get todoRemovals => mutations
      .where((m) => m.operation == 'remove' && m.key == 'flutter.todos')
      .length;
  int get todoSets => mutations
      .where((m) => m.operation == 'set' && m.key == 'flutter.todos')
      .length;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final event = _Mutation115('set', key, value);
    mutations.add(event);
    final saved = await super.setValue(type, key, value);
    event.persisted = saved;
    return saved;
  }

  @override
  Future<bool> remove(String key) async {
    final event = _Mutation115('remove', key, null);
    mutations.add(event);
    final gate = key == 'flutter.todos' ? _removeGate : null;
    if (gate != null) _removeGate = null;
    final saved = await super.remove(key);
    event.persisted = saved;
    if (gate != null) {
      expect(saved, isTrue);
      gate.started.complete();
      await gate.release.future;
    }
    return saved;
  }

  void releaseAll() {
    releaseRead();
    for (final gate in gates) {
      gate.releaseNow();
    }
  }
}

class _ExternalRun115 {
  bool done = false;
  Object? error;
}

class _LifecycleTodos115 extends _OriginTodos101 {
  final externalRuns = <_ExternalRun115>[];
  @override
  Future<T> runExternalStorageUpdate<T>(
    Future<T> Function() operation, {
    int? expectedAccountDataGeneration,
  }) {
    final observed = _ExternalRun115();
    externalRuns.add(observed);
    final result = super.runExternalStorageUpdate<T>(
      operation,
      expectedAccountDataGeneration: expectedAccountDataGeneration,
    );
    result.then<void>(
      (_) {
        observed.done = true;
      },
      onError: (Object error, StackTrace _) {
        observed.error = error;
        observed.done = true;
      },
    );
    return result;
  }
}

class _LifecycleHarness115 {
  _LifecycleHarness115(this.store) : inner = _OriginHarness101(store) {
    todos.scheduler = inner.base.reminderScheduler;
    replacementTodos.scheduler = inner.base.reminderScheduler;
  }
  final _LifecycleStore115 store;
  final _OriginHarness101 inner;
  final todos = _LifecycleTodos115();
  final replacementTodos = _LifecycleTodos115();
  final messengerKey = GlobalKey<_ObservedMessengerState115>();
  final gates = <_Gate115>[];
  final pending = <Future<void>>[];
  Future<void>? heldLoad;
  _ObservedMessengerState115 get messenger => messengerKey.currentState!;
  Widget get app => ValueListenableBuilder<bool>(
    valueListenable: inner.base.useReplacement,
    builder: (context, replace, _) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: inner.base.theme),
        ChangeNotifierProvider<TodoProvider>.value(
          value: replace ? replacementTodos : todos,
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: inner.auth),
        ChangeNotifierProvider<AppLockProvider>.value(value: inner.lock),
        ChangeNotifierProvider<AppUpdateService>.value(value: inner.update),
        Provider<AppAccessRouteGate>.value(value: inner.routes),
        ChangeNotifierProvider<HabitProvider>.value(value: inner.base.habits),
        ChangeNotifierProvider<PomodoroProvider>.value(
          value: inner.base.pomodoro,
        ),
        ChangeNotifierProvider<NoteProvider>.value(value: inner.base.notes),
        ChangeNotifierProvider<AnniversaryProvider>.value(
          value: inner.base.anniversaries,
        ),
        ChangeNotifierProvider<DiaryProvider>.value(value: inner.base.diary),
        ChangeNotifierProvider<GoalProvider>.value(value: inner.base.goals),
        ChangeNotifierProvider<CourseProvider>.value(value: inner.base.courses),
        ChangeNotifierProvider<UserProvider>.value(value: inner.base.users),
        ChangeNotifierProvider<TimeAuditProvider>.value(
          value: inner.base.timeAudit,
        ),
        ChangeNotifierProvider<AchievementProvider>.value(
          value: inner.base.achievements,
        ),
        ChangeNotifierProvider<ShareProvider>.value(value: inner.base.shares),
        ChangeNotifierProvider<CalendarProvider>.value(
          value: inner.base.calendar,
        ),
        ChangeNotifierProvider<CountdownProvider>.value(
          value: inner.base.countdowns,
        ),
        ChangeNotifierProvider<LocationReminderProvider>.value(
          value: inner.base.locationReminders,
        ),
        ChangeNotifierProvider<PreferencesProvider>.value(
          value: inner.base.preferences,
        ),
        ChangeNotifierProvider<QuickCaptureTemplateProvider>.value(
          value: inner.base.quickCaptureTemplates,
        ),
      ],
      child: AnimatedBuilder(
        animation: Listenable.merge([
          inner.base.theme,
          I18n.localeListenable,
          inner.lock,
          inner.update,
        ]),
        builder: (context, _) => MaterialApp(
          navigatorKey: inner.base.navigatorKey,
          navigatorObservers: [inner.routes],
          locale: Locale(I18n.current == AppLocale.en ? 'en' : 'zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: inner.base.theme.brand.theme,
          builder: (context, child) => _ObservedMessenger115(
            key: messengerKey,
            child: AppAccessLayer(
              locked: inner.lock.isLocked,
              mustUpdate: inner.update.mustUpdate,
              routes: inner.routes,
              lockOverlay: const Center(child: Text('Lifecycle115 locked')),
              updateOverlay: const Center(
                child: Text('Lifecycle115 update required'),
              ),
              child: child!,
            ),
          ),
          home: const BrandRouteSurface(
            remountOnLocaleChange: false,
            child: BackupScreen(initialMode: BackupEntryMode.restore),
          ),
        ),
      ),
    ),
  );
  void dispose() {
    todos.onLocalMutationPersisted = null;
    todos.dispose();
    replacementTodos.dispose();
    inner.dispose();
  }
}

// Bounded frame pumping gives Flutter animations/microtasks their real turns.
// Completion predicates, actual SDK.closed and owned gates establish ordering;
// there is no wall-clock sleep or preference drain during held work.
Future<void> _until115(
  WidgetTester tester,
  bool Function() ready, {
  Duration step = const Duration(milliseconds: 20),
}) async {
  for (var frame = 0; frame < 500 && !ready(); frame++) {
    await tester.pump(step);
    await tester.runAsync(() async {});
  }
  expect(tester.takeException(), isNull);
  expect(
    ready(),
    isTrue,
    reason: 'Lifecycle115 did not reach its observed boundary',
  );
}

Future<void> _tap115(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
}

Future<_Banner115> _importBanner115(
  WidgetTester tester,
  _LifecycleHarness115 h,
) async {
  final file = _fileButton101();
  await tester.scrollUntilVisible(
    file,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await _tap115(tester, file);
  await _until115(tester, () => _chooser().evaluate().isNotEmpty);
  await _tap115(tester, _sourceField());
  await _until115(
    tester,
    () =>
        find
            .text(DataSettingsUiCopy.sourceTickTick)
            .hitTestable()
            .evaluate()
            .length ==
        1,
  );
  await _tap115(
    tester,
    find.text(DataSettingsUiCopy.sourceTickTick).hitTestable(),
  );
  await _until115(
    tester,
    () =>
        find
            .descendant(
              of: _chooser(),
              matching: find.text(DataSettingsUiCopy.hintTickTick),
            )
            .evaluate()
            .length ==
        1,
  );
  await _tap115(
    tester,
    _dialogButton(
      _chooser(),
      OutlinedButton,
      DataSettingsUiCopy.advancedFieldMapping,
    ),
  );
  await _until115(tester, () => _mapping().evaluate().isNotEmpty);
  await tester.ensureVisible(_mappingTitleInput());
  await tester.enterText(_mappingTitleInput(), _mappingColumn);
  await _tap115(
    tester,
    _dialogButton(_mapping(), FilledButton, I18n.tr('action.save')),
  );
  await _until115(
    tester,
    () =>
        _mapping().evaluate().isEmpty &&
        find
                .descendant(
                  of: _chooser(),
                  matching: find.text(_mappingSummary()),
                )
                .evaluate()
                .length ==
            1,
  );
  await _tap115(
    tester,
    _dialogButton(
      _chooser(),
      FilledButton,
      DataSettingsUiCopy.importCompetitorFileSourceAction,
    ),
  );
  final preview = _dialog(DataSettingsUiCopy.importPreviewTitle);
  await _until115(tester, () => preview.evaluate().isNotEmpty);
  _expectMappedPreview101();
  final confirm = _dialogButton(
    preview,
    FilledButton,
    DataSettingsUiCopy.confirmImport,
  );
  expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
  await _tap115(
    tester,
    find.descendant(
      of: preview,
      matching: find.widgetWithText(
        CheckboxListTile,
        DataSettingsUiCopy.confirmImportPolicyCheckbox,
      ),
    ),
  );
  await _until115(
    tester,
    () => tester.widget<FilledButton>(confirm).onPressed != null,
  );
  await _tap115(tester, confirm);
  final result = _dialog(DataSettingsUiCopy.importCompletedTitle);
  await _until115(tester, () => result.evaluate().isNotEmpty);
  final shownBefore = h.messenger.shown.length;
  await _tap115(
    tester,
    _dialogButton(result, FilledButton, DataSettingsUiCopy.gotIt),
  );
  await _until115(
    tester,
    () =>
        h.messenger.shown.length == shownBefore + 1 &&
        find.byType(SnackBarAction).hitTestable().evaluate().length == 1,
  );
  final banner = h.messenger.shown.last;
  expect(banner.snackBar.action!.label, DataSettingsUiCopy.undoImport);
  expect(
    (banner.snackBar.content as Text).data,
    DataSettingsUiCopy.importSuccessBanner(
      DataSettingsUiCopy.sourceTickTick,
      1,
      0,
      '',
    ),
  );
  expect(banner.closed, isFalse);
  return banner;
}

Future<void> _tapBannerUndo115(WidgetTester tester) async => _tap115(
  tester,
  find.widgetWithText(SnackBarAction, DataSettingsUiCopy.undoImport),
);

Future<void> _sdkClosed115(WidgetTester tester, _Banner115 banner) async {
  await _until115(tester, () => banner.closed);
  expect(await banner.controller.closed, banner.closedReason);
  // Flush handlers attached by product after the SDK controller was returned.
  await tester.pump();
}

Future<void> _restored115(
  WidgetTester tester,
  _LifecycleHarness115 h,
  _LifecycleTodos115 owner,
) async {
  await _until115(
    tester,
    () =>
        owner.externalRuns.length == 1 &&
        owner.externalRuns.single.done &&
        find.text(DataSettingsUiCopy.undoImportSuccess).evaluate().isNotEmpty,
  );
  expect(owner.externalRuns.single.error, isNull);
  expect(owner.externalUpdates, 1);
  expect(owner.queuedOperationEntries, 1);
  expect(find.text(DataSettingsUiCopy.undoImportSuccess), findsOneWidget);
}

Future<void> _withLifecycle115(
  WidgetTester tester,
  Future<void> Function(_LifecycleHarness115) body,
) async {
  final oldLocale = I18n.current;
  final oldZone = LocalTimezoneResolver.debugSystemTimeZoneReader;
  final oldSelector = FileSelectorPlatform.instance;
  final oldStore = SharedPreferencesStorePlatform.instance;
  final values = <String, Object>{
    'active_brand': 'defaultBrand',
    'theme_shop_state': jsonEncode({
      'activeBrand': 'defaultBrand',
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    'auth_state': jsonEncode(_originAccount101.toJson()),
    AccountLocalDataCleaner.accountDataOwnerKey:
        'id:${_originAccount101.userId}',
  };
  SharedPreferences.setMockInitialValues(values);
  final h = _LifecycleHarness115(
    _LifecycleStore115({
      for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
    }),
  );
  SharedPreferencesStorePlatform.instance = h.store;
  FileSelectorPlatform.instance = h.inner.base.selector;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') h.inner.clipboardWrites++;
        return null;
      });
  await http.runWithClient(() async {
    try {
      I18n.setLocale(AppLocale.en);
      LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
          'Asia/Shanghai';
      await tester.runAsync(loadWeeklyReviewScreenshotFonts);
      await h.inner.base.theme.loadFromStorage();
      await h.inner.lock.loadFromStorage();
      expect(await h.inner.lock.setPin('123456'), isTrue);
      h.store.businessMutations.clear();
      h.store.mutations.clear();
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(h.app);
      await _settle(tester);
      await body(h);
      await _settle(tester);
    } finally {
      Object? cleanupError;
      StackTrace? cleanupStack;
      var allOwnedSettled = false;
      var drainStarted = false;
      final owned =
          <({String label, bool Function() settled, Future<void> observed})>[];

      void recordFailure(Object error, StackTrace stack) {
        if (cleanupError == null) {
          cleanupError = error;
          cleanupStack = stack;
        }
      }

      void attempt(void Function() operation) {
        try {
          operation();
        } catch (error, stack) {
          recordFailure(error, stack);
        }
      }

      ({String label, bool Function() settled, Future<void> observed}) observe(
        String label,
        Future<void> source,
      ) {
        var settled = false;
        final observed = source.then<void>(
          (_) {
            settled = true;
          },
          onError: (Object error, StackTrace stack) {
            recordFailure(error, stack);
            settled = true;
          },
        );
        final observation = (
          label: label,
          settled: () => settled,
          observed: observed,
        );
        owned.add(observation);
        return observation;
      }

      bool externalSettled() =>
          h.todos.externalRuns.every((run) => run.done) &&
          h.replacementTodos.externalRuns.every((run) => run.done);

      Future<void> cleanupTurn(Duration step) async {
        try {
          await tester.pump(step);
        } catch (error, stack) {
          recordFailure(error, stack);
        }
        try {
          // Yield a real-zone turn, never await an unsettled owned Future here.
          await tester.runAsync(() async {});
        } catch (error, stack) {
          recordFailure(error, stack);
        }
        try {
          final reported = tester.takeException();
          if (reported != null) {
            final stack = reported is Error
                ? reported.stackTrace ?? StackTrace.current
                : StackTrace.current;
            recordFailure(reported, stack);
          }
        } catch (error, stack) {
          recordFailure(error, stack);
        }
      }

      Future<void> drive(String label, bool Function() ready) async {
        for (var frame = 0; frame < 500 && !ready(); frame++) {
          await cleanupTurn(const Duration(milliseconds: 20));
        }
        if (!ready()) {
          recordFailure(
            TimeoutException(
              'Lifecycle115 cleanup did not settle $label after 500 frame turns',
              const Duration(seconds: 10),
            ),
            StackTrace.current,
          );
        }
      }

      try {
        try {
          // Attach real-Future observers before unmount can release work.
          final heldLoad = h.heldLoad;
          if (heldLoad != null) observe('heldLoad', heldLoad);
          for (var index = 0; index < h.pending.length; index++) {
            observe('pending[$index]', h.pending[index]);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        } catch (error, stack) {
          recordFailure(error, stack);
        } finally {
          attempt(() => h.todos.onLocalMutationPersisted = null);
          attempt(() => h.replacementTodos.onLocalMutationPersisted = null);
          attempt(h.store.releaseAll);
          // Keep releasing other ACK gates even if releaseAll itself failed.
          for (final gate in h.store.gates) {
            attempt(gate.releaseNow);
          }
          for (final gate in h.gates) {
            attempt(gate.releaseNow);
          }
          attempt(h.inner.base.selector.release);
        }

        // Frame/SDK errors are retained without skipping later owned waits.
        await drive('externalRuns', externalSettled);
        for (final observation in owned) {
          await drive(observation.label, observation.settled);
          if (observation.settled()) await observation.observed;
        }
        for (var frame = 0; frame < 4; frame++) {
          await cleanupTurn(const Duration(milliseconds: 40));
        }
        await drive(
          'scheduled frames',
          () => !tester.binding.hasScheduledFrame,
        );

        // Start the real tracker drain in the owning fake zone and immediately
        // observe it. Its own write-error suppression is unchanged.
        final drain = observe(
          'AccountPreferenceWrites.drain',
          AccountPreferenceWrites.drain(),
        );
        drainStarted = true;
        await drive(drain.label, drain.settled);
        if (drain.settled()) await drain.observed;

        // Later stages can settle earlier timed-out work. Keep its timeout
        // failure, but acknowledge real completion before deciding restoration.
        for (final observation in owned) {
          if (observation.settled()) await observation.observed;
        }
      } catch (error, stack) {
        recordFailure(error, stack);
      } finally {
        allOwnedSettled =
            drainStarted &&
            externalSettled() &&
            owned.every((observation) => observation.settled());
        if (allOwnedSettled) {
          attempt(h.dispose);
          attempt(tester.view.reset);
          attempt(() => I18n.setLocale(oldLocale));
          attempt(
            () => LocalTimezoneResolver.debugSystemTimeZoneReader = oldZone,
          );
          attempt(() => FileSelectorPlatform.instance = oldSelector);
          attempt(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          attempt(SharedPreferences.resetStatic);
          attempt(() => SharedPreferencesStorePlatform.instance = oldStore);
        }
      }

      if (!allOwnedSettled) {
        final pendingLabels = <String>[
          if (!h.todos.externalRuns.every((run) => run.done))
            'todos.externalRuns',
          if (!h.replacementTodos.externalRuns.every((run) => run.done))
            'replacementTodos.externalRuns',
          for (final observation in owned)
            if (!observation.settled()) observation.label,
          if (!drainStarted) 'AccountPreferenceWrites.drain (not started)',
        ];
        final fatal = FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('Fatal Lifecycle115 cleanup: owned work is unsettled.'),
          ErrorDescription(
            'Pending: ${pendingLabels.join(', ')}. Synthetic providers/store and fixture global overrides were '
                'retained. The runner must use --fail-fast and terminate this '
                'fixture process; later cases must not reuse this state.',
          ),
          DiagnosticsProperty<Object?>('First cleanup error', cleanupError),
          if (cleanupStack != null)
            ErrorDescription(
              'First cleanup error stack:\n$cleanupStack',
            ),
        ]);
        Error.throwWithStackTrace(fatal, cleanupStack ?? StackTrace.current);
      }
      if (cleanupError != null) {
        Error.throwWithStackTrace(cleanupError!, cleanupStack!);
      }
    }
  }, () => MockClient(h.inner.respond));
}

void _originTests115() {
  testWidgets(
    '115 accepted SnackBar Undo waits for real Todo queue through SDK closed then restores once',
    (tester) async {
      await _withLifecycle115(tester, (h) async {
        final banner = await _importBanner115(tester, h);
        expect(h.todos.todos.single.title, _mappedTitle);
        final before = await h.store.backing();
        final mutations = List<String>.of(h.store.businessMutations);
        SharedPreferences.resetStatic();
        h.store.holdNextRead();
        h.heldLoad = h.todos.loadFromStorage(force: true);
        await _until115(tester, () => h.store.heldReadStarted);
        await _tapBannerUndo115(tester);
        await _until115(
          tester,
          () => h.todos.externalUpdates == 1,
          step: Duration.zero,
        );
        expect(h.todos.queuedOperationEntries, 0);
        expect(h.todos.externalRuns.single.done, isFalse);
        await _sdkClosed115(tester, banner);
        expect(banner.closedReason, SnackBarClosedReason.action);
        expect(h.todos.externalRuns.single.done, isFalse);
        expect(h.store.todoRemovals, 0);
        expect(h.store.businessMutations, mutations);
        // backing() would wait on the deliberately held plugin read; inspect
        // the already captured map only until the actual read gate is released.
        expect(before['flutter.todos'], isNotNull);
        h.store.releaseRead();
        await _restored115(tester, h, h.todos);
        await h.heldLoad;
        expect(h.todos.todos, isEmpty);
        expect((await h.store.backing())['flutter.todos'], isNull);
        expect(h.store.todoRemovals, 1);
        expect(h.replacementTodos.externalUpdates, 0);
        expect(h.replacementTodos.publicLoads, 0);
        final writes = h.store.mutations.length;
        banner.snackBar.action!.onPressed();
        await tester.pump();
        expect(h.todos.externalUpdates, 1);
        expect(h.store.mutations.length, writes);
      });
    },
  );

  testWidgets(
    '115 dispatched restore holds real persistence ACK through SDK closed then completes once',
    (tester) async {
      await _withLifecycle115(tester, (h) async {
        final banner = await _importBanner115(tester, h);
        final ack = h.store.holdNextTodoRemoval();
        await _tapBannerUndo115(tester);
        // Drain real storage microtasks without advancing the SDK's close
        // animation clock until the actual persistence ACK gate has entered.
        await _until115(
          tester,
          () => ack.started.isCompleted,
          step: Duration.zero,
        );
        expect(ack.release.isCompleted, isFalse);
        expect(h.store.todoRemovals, 1);
        final removal = h.store.mutations.singleWhere(
          (m) => m.operation == 'remove' && m.key == 'flutter.todos',
        );
        expect(removal.persisted, isTrue);
        expect((await h.store.backing())['flutter.todos'], isNull);
        expect(h.todos.todos.single.title, _mappedTitle);
        expect(h.todos.externalRuns.single.done, isFalse);
        expect(banner.closed, isFalse);
        await _sdkClosed115(tester, banner);
        expect(banner.closedReason, SnackBarClosedReason.action);
        expect(ack.release.isCompleted, isFalse);
        expect(h.todos.externalRuns.single.done, isFalse);
        // This actual persisted remove is dispatch/effect evidence. Queue
        // enrollment counters are supplementary, never a static dispatch count.
        ack.releaseNow();
        await _restored115(tester, h, h.todos);
        expect(h.todos.todos, isEmpty);
        expect((await h.store.backing())['flutter.todos'], isNull);
        expect(h.store.todoRemovals, 1);
        expect(h.replacementTodos.publicLoads, 0);
        final writes = h.store.mutations.length;
        banner.snackBar.action!.onPressed();
        await tester.pump();
        expect(h.todos.externalUpdates, 1);
        expect(h.store.mutations.length, writes);
      });
    },
  );

  testWidgets(
    '115 revoked A Undo settles after B banner without releasing B Undo authority',
    (tester) async {
      await _withLifecycle115(tester, (h) async {
        final screen = find.byType(BackupScreen);
        final state = tester.state(screen);
        final route = ModalRoute.of(tester.element(screen));
        final bannerA = await _importBanner115(tester, h);
        final queue = _Gate115();
        h.gates.add(queue);
        h.todos.onLocalMutationPersisted = () async {
          queue.started.complete();
          await queue.release.future;
        };
        const renamedA = 'Committed predecessor A115';
        final original = h.todos.todos.single;
        final edit = h.todos.updateTodo(
          original.id,
          original.copyWith(title: renamedA),
          waitForReminderSync: false,
        );
        h.pending.add(
          edit.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
        await _until115(tester, () => queue.started.isCompleted);
        h.todos.onLocalMutationPersisted = null;
        final preB = (await h.store.backing())['flutter.todos'];
        expect(preB, contains(renamedA));
        await _tapBannerUndo115(tester);
        await _until115(
          tester,
          () => h.todos.externalUpdates == 1,
          step: Duration.zero,
        );
        expect(h.todos.queuedOperationEntries, 0);
        expect(h.todos.externalRuns.single.done, isFalse);
        final oldGeneration = AccountLocalDataCleaner.accountDataGeneration;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        h.inner.base.useReplacement.value = true;
        await _until115(
          tester,
          () =>
              tester.widget<OutlinedButton>(_fileButton101()).onPressed !=
                  null &&
              identical(
                tester.element(screen).read<TodoProvider>(),
                h.replacementTodos,
              ),
        );
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          greaterThan(oldGeneration),
        );
        await _sdkClosed115(tester, bannerA);
        expect(queue.release.isCompleted, isFalse);
        // A's earlier write is already committed; only its real persistence
        // publication callback keeps Todo's queue held. B can use its own queue
        // and cached preferences without waiting on a global held getInstance.
        final bannerB = await _importBanner115(tester, h);
        expect(h.replacementTodos.importCalls, 1);
        expect(
          h.replacementTodos.todos.map((t) => t.title),
          unorderedEquals([renamedA, _mappedTitle]),
        );
        expect(h.replacementTodos.externalUpdates, 0);
        expect(bannerB.closed, isFalse);
        expect(h.todos.externalRuns.single.done, isFalse);
        expect(queue.release.isCompleted, isFalse);
        final bPersisted = (await h.store.backing())['flutter.todos'];
        final writes = List<String>.of(h.store.businessMutations);
        final loadsB = h.replacementTodos.publicLoads;
        expect(tester.state(screen), same(state));
        expect(ModalRoute.of(tester.element(screen)), same(route));
        queue.releaseNow();
        await _until115(tester, () => h.todos.externalRuns.single.done);
        await edit;
        await tester.pump();
        expect(h.store.businessMutations, writes);
        expect((await h.store.backing())['flutter.todos'], bPersisted);
        expect(h.store.todoRemovals, 0);
        expect(h.replacementTodos.publicLoads, loadsB);
        expect(h.replacementTodos.externalUpdates, 0);
        expect(bannerB.closed, isFalse);
        expect(
          find
              .widgetWithText(SnackBarAction, DataSettingsUiCopy.undoImport)
              .hitTestable(),
          findsOneWidget,
        );
        await _tapBannerUndo115(tester);
        await _restored115(tester, h, h.replacementTodos);
        expect(h.replacementTodos.todos.single.title, renamedA);
        expect((await h.store.backing())['flutter.todos'], preB);
        expect(h.replacementTodos.externalUpdates, 1);
        expect(h.todos.externalUpdates, 1);
        final restoredWrites = h.store.mutations.length;
        bannerB.snackBar.action!.onPressed();
        await tester.pump();
        expect(h.replacementTodos.externalUpdates, 1);
        expect(h.store.mutations.length, restoredWrites);
        expect(tester.state(screen), same(state));
      });
    },
  );
}
