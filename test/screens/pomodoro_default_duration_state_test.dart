import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/focus_room_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

const _capture = ValueKey('pomodoro-default-capture');
const _default = ValueKey('pomodoro-default-duration');
final _screenshots = Platform.environment['DUOYI_POMODORO_SCREENSHOT_DIR'];

void main() {
  late AppLocale locale;
  late Future<String?> Function()? reader;
  setUp(() {
    locale = I18n.current;
    I18n.setLocale(AppLocale.zh);
    reader = LocalTimezoneResolver.debugSystemTimeZoneReader;
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = reader;
    I18n.setLocale(locale);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'default duration and explicit 25 stay distinct at width $width',
      (tester) async {
        final f = await _open(tester, width: width);
        expect(
          tester.widget<ChoiceChip>(find.byKey(_default)).selected,
          isTrue,
        );
        expect(
          find.text(FocusRoomUiCopy.defaultDuration(45, AppLocale.zh)),
          findsOneWidget,
        );
        await _captureImage(tester, 'pomodoro-default-${width.toInt()}-zh.png');
        final explicit25 = _minutesChip(25);
        await tester.ensureVisible(explicit25);
        await tester.tap(explicit25);
        await tester.pumpAndSettle();
        expect(f.timer.config.focusDurationUsesDefault, isFalse);
        expect(f.timer.state.totalSeconds, 1500);
        expect(tester.widget<ChoiceChip>(explicit25).selected, isTrue);
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(
          find.text(FocusRoomUiCopy.defaultDuration(45, AppLocale.en)),
          findsOneWidget,
        );
        expect(f.timer.config.focusDurationUsesDefault, isFalse);
        await tester.ensureVisible(find.byKey(_default));
        await tester.tap(find.byKey(_default));
        await tester.pumpAndSettle();
        expect(f.timer.state.totalSeconds, 2700);
        expect(f.timer.config.focusDurationUsesDefault, isTrue);
        await tester.runAsync(
          () => f.preferences.setDefaultPomodoroMinutes(60),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(FocusRoomUiCopy.defaultDuration(60, AppLocale.en)),
          findsOneWidget,
        );
        expect(f.timer.state.totalSeconds, 3600);
        await _captureImage(tester, 'pomodoro-default-${width.toInt()}-en.png');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'rejected duration selection retains mode and localizes its error',
    (tester) async {
      final f = await _open(tester);
      f.store.rejectNext = true;
      final select = tester.widget<ChoiceChip>(_minutesChip(25)).onSelected!;
      select(true);
      await tester.pumpAndSettle();
      expect(f.timer.config.focusDurationUsesDefault, isTrue);
      expect(f.timer.state.totalSeconds, 2700);
      expect(
        find.text(FocusRoomUiCopy.durationSaveFailed(AppLocale.zh)),
        findsOneWidget,
      );
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(
        find.text(FocusRoomUiCopy.durationSaveFailed(AppLocale.en)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('running timer disables default and numeric choices', (
    tester,
  ) async {
    final f = await _open(tester);
    f.timer.startIfIdle();
    await tester.pump();
    expect(tester.widget<ChoiceChip>(find.byKey(_default)).onSelected, isNull);
    expect(tester.widget<ChoiceChip>(_minutesChip(25)).onSelected, isNull);
    f.timer.toggleTimer();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final invalidate in ['account', 'covered']) {
    testWidgets('retained duration callback refuses a $invalidate origin', (
      tester,
    ) async {
      final f = await _open(tester);
      final select = tester.widget<ChoiceChip>(_minutesChip(25)).onSelected!;
      if (invalidate == 'account') {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      } else {
        final context = tester.element(find.byKey(_default));
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('covering focus')),
          ),
        );
        await tester.pumpAndSettle();
      }
      final writes = f.store.configWrites;
      select(true);
      await tester.pumpAndSettle();
      expect(f.store.configWrites, writes);
      expect(f.timer.config.focusDurationUsesDefault, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}

Finder _minutesChip(int minutes) => find.widgetWithText(
  ChoiceChip,
  FocusRoomUiCopy.minutesSuffix(minutes, I18n.current),
);

Future<_Fixture> _open(WidgetTester tester, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = _ConfigStore();
  SharedPreferencesStorePlatform.instance = store;
  late PreferencesProvider preferences;
  final timer = PomodoroProvider();
  final auth = AuthProvider();
  final theme = ThemeProvider();
  final rooms = FocusRoomProvider();
  final sounds = CustomFocusSoundProvider();
  await tester.runAsync(() async {
    // The queue and its reads must share runAsync's real clock.
    preferences = PreferencesProvider();
    await preferences.loadFromStorage();
    timer.attachPreferences(preferences, auth: auth);
    await timer.loadFromStorage();
    if (_screenshots != null) {
      await loadWidgetPolishScreenshotFonts();
      final bytes = File(
        'assets/fonts/DroidSansFallbackFull.ttf',
      ).readAsBytesSync();
      await (FontLoader(
        'DroidSansFallbackFull',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      await (FontLoader(
        'PingFang SC',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      final latin = File('assets/fonts/DejaVuSans.ttf').readAsBytesSync();
      await (FontLoader(
        'sans-serif',
      )..addFont(Future.value(ByteData.sublistView(latin)))).load();
      await (FontLoader(
        'DejaVu Sans',
      )..addFont(Future.value(ByteData.sublistView(latin)))).load();
      await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
        'type': 'fontsChange',
      });
    }
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    timer.dispose();
    preferences.dispose();
    auth.dispose();
    theme.dispose();
    rooms.dispose();
    sounds.dispose();
    await tester.runAsync(() async {
      await AccountPreferenceWrites.drain();
      await timer.waitForSnapshotWrites();
    });
    await tester.pump();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PomodoroProvider>.value(value: timer),
        ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<FocusRoomProvider>.value(value: rooms),
        ChangeNotifierProvider<CustomFocusSoundProvider>.value(value: sounds),
      ],
      child: MaterialApp(
        theme: _screenshots == null
            ? theme.brand.theme
            : theme.brand.theme.copyWith(
                textTheme: theme.brand.theme.textTheme.apply(
                  fontFamily: 'DuoyiScreenshotLatin',
                ),
                primaryTextTheme: theme.brand.theme.primaryTextTheme.apply(
                  fontFamily: 'DuoyiScreenshotLatin',
                ),
              ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.3 : 1)),
          child: child!,
        ),
        home: const RepaintBoundary(key: _capture, child: PomodoroScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fixture(timer, preferences, store);
}

Future<void> _captureImage(WidgetTester tester, String name) async {
  if (_screenshots == null) return;
  final directory = Directory(_screenshots!).absolute.path;
  final root = Directory('evidence/screenshots').absolute.path;
  if (!directory.startsWith('$root/')) {
    throw StateError(
      'Screenshot directory must be under evidence/screenshots/',
    );
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(directory).createSync(recursive: true);
    File('$directory/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _Fixture {
  final PomodoroProvider timer;
  final PreferencesProvider preferences;
  final _ConfigStore store;
  _Fixture(this.timer, this.preferences, this.store);
}

class _ConfigStore extends InMemorySharedPreferencesStore {
  _ConfigStore()
    : super.withData({'flutter.pref_default_pomodoro_minutes': 45});
  bool rejectNext = false;
  int configWrites = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.pomodoro_config') {
      configWrites++;
      if (rejectNext) {
        rejectNext = false;
        return false;
      }
    }
    return super.setValue(type, key, value);
  }
}
