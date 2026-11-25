import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/widgets/app_date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dateFormatPreferenceKey = 'pref_date_format';
const _patterns = <String>[
  'yyyy-MM-dd',
  'MM/dd/yyyy',
  'dd/MM/yyyy',
  'yyyy年M月d日',
];
const _expectedDateByPattern = <String, String>{
  'yyyy-MM-dd': '2026-05-15',
  'MM/dd/yyyy': '05/15/2026',
  'dd/MM/yyyy': '15/05/2026',
  'yyyy年M月d日': '2026年5月15日',
};
final _sampleDate = DateTime(2026, 5, 15, 15, 4);

Future<PreferencesProvider> _loadPreferences(
  WidgetTester tester, {
  String? dateFormat,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  late PreferencesProvider preferences;
  await tester.runAsync(() async {
    // Initialize the provider's write tail in this real async zone. Creating
    // it in the widget test's fakeAsync zone can leave setDateFormat waiting
    // on a microtask that only advances during a pump.
    preferences = PreferencesProvider();
    await preferences.loadFromStorage();
    if (dateFormat != null) {
      await preferences.setDateFormat(dateFormat);
    }
    final storage = await SharedPreferences.getInstance();
    expect(storage.getString(_dateFormatPreferenceKey), dateFormat);
    await preferences.loadFromStorage();
  });
  addTearDown(preferences.dispose);
  return preferences;
}

Widget _appWithPreferences(PreferencesProvider? preferences, Widget child) {
  final app = MaterialApp(home: Scaffold(body: child));
  if (preferences == null) return app;
  return ChangeNotifierProvider<PreferencesProvider>.value(
    value: preferences,
    child: app,
  );
}

class _DateFormatProbe extends StatelessWidget {
  final DateTime value;
  final String keyPrefix;

  const _DateFormatProbe({required this.value, required this.keyPrefix});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppDateFormat.patternOf(context) ?? 'legacy',
          key: ValueKey('$keyPrefix.pattern'),
        ),
        Text(
          AppDateFormat.date(context, value),
          key: ValueKey('$keyPrefix.date'),
        ),
        Text(
          AppDateFormat.fullDateTime(context, value),
          key: ValueKey('$keyPrefix.full'),
        ),
        Text(
          AppDateFormat.smartDate(context, value, includeTime: false),
          key: ValueKey('$keyPrefix.smartDate'),
        ),
        Text(
          AppDateFormat.smartDate(context, value, includeTime: true),
          key: ValueKey('$keyPrefix.smartDateTime'),
        ),
      ],
    );
  }
}

class _DateOnlyProbe extends StatelessWidget {
  final DateTime value;
  final String keyName;

  const _DateOnlyProbe({required this.value, required this.keyName});

  @override
  Widget build(BuildContext context) {
    return Text(AppDateFormat.date(context, value), key: ValueKey(keyName));
  }
}

class _DateFormatDialog extends StatefulWidget {
  final DateTime value;

  const _DateFormatDialog({required this.value});

  @override
  State<_DateFormatDialog> createState() => _DateFormatDialogState();
}

class _DateFormatDialogState extends State<_DateFormatDialog> {
  final _draftController = TextEditingController();
  final _draftFocusNode = FocusNode();
  bool _selected = false;

  @override
  void dispose() {
    _draftController.dispose();
    _draftFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit date'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppDateFormat.date(context, widget.value),
            key: const ValueKey('dialog.formatted-date'),
          ),
          TextField(
            key: const ValueKey('dialog.draft'),
            controller: _draftController,
            focusNode: _draftFocusNode,
            decoration: const InputDecoration(labelText: 'Draft'),
          ),
          CheckboxListTile(
            key: const ValueKey('dialog.selection'),
            title: const Text('Selected'),
            value: _selected,
            onChanged: (value) => setState(() => _selected = value ?? false),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _DialogLauncher extends StatelessWidget {
  final DateTime value;

  const _DialogLauncher({required this.value});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _DateFormatDialog(value: value),
        ),
        child: const Text('Open editor'),
      ),
    );
  }
}

String _probeText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final locale in AppLocale.values) {
    for (final pattern in _patterns) {
      testWidgets(
        '${locale.name} $pattern formats date and date-time together',
        (tester) async {
          I18n.setLocale(locale);
          final preferences = await _loadPreferences(
            tester,
            dateFormat: pattern,
          );
          expect(preferences.dateFormat, pattern);

          await tester.pumpWidget(
            _appWithPreferences(
              preferences,
              _DateFormatProbe(value: _sampleDate, keyPrefix: 'matrix'),
            ),
          );

          final expectedDate = _expectedDateByPattern[pattern]!;
          final weekday = locale == AppLocale.en ? 'Fri' : '周五';
          final time = locale == AppLocale.en ? '3:04 PM' : '15:04';
          final expectedFull = '$expectedDate $weekday $time';
          expect(_probeText(tester, 'matrix.pattern'), pattern);
          expect(_probeText(tester, 'matrix.date'), expectedDate);
          expect(_probeText(tester, 'matrix.full'), expectedFull);
          expect(_probeText(tester, 'matrix.smartDate'), expectedDate);
          expect(_probeText(tester, 'matrix.smartDateTime'), expectedFull);
        },
      );
    }
  }

  testWidgets('real preferences default to yyyy-MM-dd', (tester) async {
    final preferences = await _loadPreferences(tester);
    I18n.setLocale(AppLocale.zh);
    expect(preferences.dateFormat, 'yyyy-MM-dd');

    await tester.pumpWidget(
      _appWithPreferences(
        preferences,
        _DateFormatProbe(value: _sampleDate, keyPrefix: 'default'),
      ),
    );

    expect(_probeText(tester, 'default.pattern'), 'yyyy-MM-dd');
    expect(_probeText(tester, 'default.date'), '2026-05-15');
  });

  for (final locale in AppLocale.values) {
    testWidgets(
      '${locale.name} output without PreferencesProvider preserves legacy formatting',
      (tester) async {
        I18n.setLocale(locale);
        String? patternWithoutProvider;
        await tester.pumpWidget(
          _appWithPreferences(
            null,
            Builder(
              builder: (context) {
                patternWithoutProvider = AppDateFormat.patternOf(context);
                return _DateFormatProbe(
                  value: _sampleDate,
                  keyPrefix: 'legacy',
                );
              },
            ),
          ),
        );
        expect(patternWithoutProvider, isNull);
        expect(_probeText(tester, 'legacy.pattern'), 'legacy');

        final expectedDate = locale == AppLocale.en
            ? 'May 15, 2026'
            : '2026年5月15日';
        final expectedFull = locale == AppLocale.en
            ? 'May 15, 2026 Fri 3:04 PM'
            : '2026年5月15日 周五 15:04';
        expect(_probeText(tester, 'legacy.date'), expectedDate);
        expect(_probeText(tester, 'legacy.full'), expectedFull);
        expect(_probeText(tester, 'legacy.smartDate'), expectedDate);
        expect(_probeText(tester, 'legacy.smartDateTime'), expectedFull);
      },
    );
  }

  testWidgets('two provider scopes keep their own date patterns', (
    tester,
  ) async {
    final usPreferences = await _loadPreferences(
      tester,
      dateFormat: 'MM/dd/yyyy',
    );
    final dayFirstPreferences = await _loadPreferences(
      tester,
      dateFormat: 'dd/MM/yyyy',
    );
    I18n.setLocale(AppLocale.zh);

    await tester.pumpWidget(
      ChangeNotifierProvider<PreferencesProvider>.value(
        value: usPreferences,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                _DateOnlyProbe(value: _sampleDate, keyName: 'us.date'),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: dayFirstPreferences,
                  child: _DateOnlyProbe(
                    value: _sampleDate,
                    keyName: 'day-first.date',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(_probeText(tester, 'us.date'), '05/15/2026');
    expect(_probeText(tester, 'day-first.date'), '15/05/2026');
  });

  testWidgets('reset and provider replacement refresh the existing formatter', (
    tester,
  ) async {
    final firstPreferences = await _loadPreferences(
      tester,
      dateFormat: 'MM/dd/yyyy',
    );
    final replacementPreferences = await _loadPreferences(
      tester,
      dateFormat: 'dd/MM/yyyy',
    );
    I18n.setLocale(AppLocale.zh);

    Widget app(PreferencesProvider preferences) => _appWithPreferences(
      preferences,
      _DateFormatProbe(value: _sampleDate, keyPrefix: 'refresh'),
    );

    await tester.pumpWidget(app(firstPreferences));
    expect(_probeText(tester, 'refresh.date'), '05/15/2026');

    firstPreferences.resetLocalState();
    await tester.pumpAndSettle();
    expect(_probeText(tester, 'refresh.pattern'), 'yyyy-MM-dd');
    expect(_probeText(tester, 'refresh.date'), '2026-05-15');

    await tester.pumpWidget(app(replacementPreferences));
    await tester.pumpAndSettle();
    expect(_probeText(tester, 'refresh.pattern'), 'dd/MM/yyyy');
    expect(_probeText(tester, 'refresh.date'), '15/05/2026');
  });

  testWidgets(
    'changing format keeps an open dialog draft, selection, and focus',
    (tester) async {
      final preferences = await _loadPreferences(
        tester,
        dateFormat: 'yyyy-MM-dd',
      );
      I18n.setLocale(AppLocale.zh);
      await tester.pumpWidget(
        _appWithPreferences(preferences, _DialogLauncher(value: _sampleDate)),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      final draftFinder = find.byKey(const ValueKey('dialog.draft'));
      await tester.enterText(draftFinder, 'keep this draft');
      await tester.tap(find.byKey(const ValueKey('dialog.selection')));
      await tester.pumpAndSettle();
      await tester.tap(draftFinder);
      await tester.pump();

      final controller = tester.widget<TextField>(draftFinder).controller!;
      final focusNode = tester.widget<TextField>(draftFinder).focusNode!;
      expect(controller.text, 'keep this draft');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('dialog.selection')),
            )
            .value,
        isTrue,
      );
      expect(focusNode.hasFocus, isTrue);

      await tester.runAsync(() => preferences.setDateFormat('MM/dd/yyyy'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_probeText(tester, 'dialog.formatted-date'), '05/15/2026');
      expect(
        tester.widget<TextField>(draftFinder).controller,
        same(controller),
      );
      expect(tester.widget<TextField>(draftFinder).focusNode, same(focusNode));
      expect(controller.text, 'keep this draft');
      expect(focusNode.hasFocus, isTrue);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('dialog.selection')),
            )
            .value,
        isTrue,
      );
    },
  );

  testWidgets(
    'readPattern from an action callback reads without registering select',
    (tester) async {
      const pattern = 'dd/MM/yyyy';
      final preferences = await _loadPreferences(tester, dateFormat: pattern);
      String? patternReadFromCallback;
      await tester.pumpWidget(
        _appWithPreferences(
          preferences,
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () {
                  patternReadFromCallback = AppDateFormat.readPattern(context);
                },
                child: const Text('Read pattern'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Read pattern'));
      await tester.pump();
      expect(patternReadFromCallback, pattern);
      expect(tester.takeException(), isNull);
    },
  );
}
