import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/focus_room_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/services/focus_dnd_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

// Exercise the production entry points, not a copy of either dialog builder.
// Device effects are irrelevant to editing a draft; provider state is real.
class _DialogTimer extends PomodoroProvider {
  @override
  Future<FocusDndStatus> refreshFocusDndStatus() async =>
      const FocusDndStatus.unavailable();
}

enum _Entrance { createRoom, editTask }

const _openFocus = ValueKey('open-pomodoro-brand-route');
const _originalTask = 'Existing focus task';
const _originalTag = 'original-tag';
const _settleTimeout = Duration(seconds: 5);
final _evidenceDirectory =
    Platform.environment['DUOYI_THEME_DIALOG_EVIDENCE_DIR'];

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    _settleTimeout,
  );
}

class _Fixture {
  final theme = ThemeProvider();
  final timer = _DialogTimer();
  final rooms = FocusRoomProvider();
  final sounds = CustomFocusSoundProvider();
  final auth = AuthProvider();
  final boundaryKey = GlobalKey();

  Future<void> mount(WidgetTester tester, {required bool captureEvidence}) async {
    await tester.runAsync(() async {
      await theme.loadFromStorage().timeout(_settleTimeout);
      await timer.setFocusRoomId(FocusRoomProvider.defaultRoomId);
      await AccountPreferenceWrites.drain().timeout(_settleTimeout);
      if (captureEvidence) {
        await loadWeeklyReviewScreenshotFonts().timeout(_settleTimeout);
      }
    });
    timer.setTaskName(_originalTask);
    timer.setTag(_originalTag);
    expect(theme.brand.id, 'defaultBrand');
    expect(theme.isBrandUnlocked('liquidGlass'), isTrue);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<PomodoroProvider>.value(value: timer),
          ChangeNotifierProvider<FocusRoomProvider>.value(value: rooms),
          ChangeNotifierProvider<CustomFocusSoundProvider>.value(value: sounds),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ],
        child: Consumer<ThemeProvider>(
          builder: (_, current, _) => RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: current.brand.theme,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      key: _openFocus,
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const BrandRouteSurface(
                            child: PomodoroScreen(useShellBackground: true),
                          ),
                        ),
                      ),
                      child: const Text('Open focus'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(_openFocus));
    await _settle(tester);
    expect(find.byType(BrandRouteSurface), findsOneWidget);
    expect(find.byType(PomodoroScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = _evidenceDirectory;
    if (directory == null || directory.isEmpty) return;
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Could not encode $name screenshot');
        final file = File('$directory/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  Future<void> dispose(WidgetTester tester) async {
    // Unmount before disposing providers, including on a failed brand assertion.
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    await tester.runAsync(() async {
      await AccountPreferenceWrites.drain().timeout(_settleTimeout);
      await timer.waitForSnapshotWrites().timeout(_settleTimeout);
    });
    timer.dispose();
    rooms.dispose();
    sounds.dispose();
    auth.dispose();
    theme.dispose();
    await tester.pump();
  }
}

Finder get _dialog => find.byType(AppDialog);
Finder get _fields => find.descendant(
  of: _dialog,
  matching: find.byType(TextField),
);

Future<void> _openDialog(WidgetTester tester, _Entrance entrance) async {
  switch (entrance) {
    case _Entrance.createRoom:
      final roomTile = find.text(FocusRoomUiCopy.studyRoomTitle(AppLocale.en));
      await tester.ensureVisible(roomTile);
      await tester.tap(roomTile);
      await _settle(tester);
      final newRoom = find.text(FocusRoomUiCopy.newRoomButton(AppLocale.en));
      await tester.ensureVisible(newRoom);
      await tester.tap(newRoom);
      await _settle(tester);
      expect(_fields, findsNWidgets(3));
      expect(tester.widget<TextField>(_fields.at(2)).controller!.text, '300');
    case _Entrance.editTask:
      // The task also appears in the preset tile. Its editable timer chip is
      // wrapped directly by a tappable GestureDetector/ConstrainedBox pair.
      final taskChip = find.ancestor(
        of: find.descendant(
          of: find.byType(PomodoroScreen),
          matching: find.text(_originalTask),
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is GestureDetector &&
              widget.onTap != null &&
              widget.child is ConstrainedBox,
          description: 'editable timer task chip GestureDetector',
        ),
      );
      expect(taskChip, findsOneWidget);
      await tester.ensureVisible(taskChip);
      expect(taskChip.hitTestable(), findsOneWidget);
      await tester.tap(taskChip);
      await _settle(tester);
      expect(_fields, findsNWidgets(2));
      expect(
        tester.widget<TextField>(_fields.at(0)).controller!.text,
        _originalTask,
      );
      expect(
        tester.widget<TextField>(_fields.at(1)).controller!.text,
        _originalTag,
      );
  }
  expect(_dialog, findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<List<TextEditingController>> _enterDraft(
  WidgetTester tester,
  _Entrance entrance,
) async {
  final values = entrance == _Entrance.createRoom
      ? ['Unsubmitted room name', 'Unsubmitted room description', '475']
      : ['Unsubmitted focus task', 'draft-tag'];
  final controllers = <TextEditingController>[];
  for (var index = 0; index < values.length; index++) {
    final field = _fields.at(index);
    await tester.ensureVisible(field);
    await tester.enterText(field, values[index]);
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    controllers.add(controller);
  }
  // The regression concerns route capture and controller lifetime, without IME.
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  return controllers;
}

Future<void> _cancelDuringReverse(
  WidgetTester tester,
  ModalRoute<dynamic> route,
  List<TextEditingController> controllers,
  List<TextEditingValue> drafts,
) async {
  final cancel = find.descendant(
    of: _dialog,
    matching: find.widgetWithText(
      TextButton,
      FocusRoomUiCopy.cancel(AppLocale.en),
    ),
  );
  await tester.ensureVisible(cancel);
  expect(cancel.hitTestable(), findsOneWidget);
  await tester.tap(cancel);
  // showDialog's result completes before route.completed. Inputs still mounted
  // in the reverse transition must keep usable controllers during this window.
  await tester.pump();
  expect(route.isCurrent, isFalse);
  expect(route.animation!.status, AnimationStatus.reverse);
  expect(_dialog, findsOneWidget);
  for (var index = 0; index < controllers.length; index++) {
    expect(
      tester.widget<TextField>(_fields.at(index)).controller,
      same(controllers[index]),
    );
    expect(controllers[index].value, drafts[index]);
    // A value read alone does not assert a ChangeNotifier is still alive.
    void listener() {}
    expect(() => controllers[index].addListener(listener), returnsNormally);
    controllers[index].removeListener(listener);
  }
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.takeException(),
      isNull,
      reason: 'Cancel must not dispose controllers used by exiting inputs.',
    );
  }
  await _settle(tester);
  expect(_dialog, findsNothing);
  expect(find.byType(PomodoroScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  final previousLocale = I18n.current;
  setUp(() {
    I18n.setLocale(AppLocale.en);
    SharedPreferences.setMockInitialValues({
      'active_brand': 'defaultBrand',
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'theme_shop_state': jsonEncode({
        'activeBrand': 'defaultBrand',
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
    });
  });
  tearDown(() => I18n.setLocale(previousLocale));

  for (final entrance in _Entrance.values) {
    for (final roundtrip in [true, false]) {
      testWidgets(
        'Pomodoro ${entrance.name} on brand route: '
        '${roundtrip ? 'live defaultBrand/liquidGlass/defaultBrand draft' : 'cancel reverse-animation controller lifetime'}',
        (tester) async {
          tester.view.physicalSize = const Size(390, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final captureEvidence = roundtrip &&
              _evidenceDirectory != null &&
              _evidenceDirectory!.isNotEmpty;
          final previousShadows = debugDisableShadows;
          try {
            if (captureEvidence) {
              debugDisableShadows = false;
            }
            late final _Fixture fixture;
            await tester.runAsync(() async {
              fixture = _Fixture();
            });
            addTearDown(() => fixture.dispose(tester));
            await fixture.mount(tester, captureEvidence: captureEvidence);
            final screenElement = tester.element(find.byType(PomodoroScreen));
            final screenRoute = ModalRoute.of(screenElement);
            await _openDialog(tester, entrance);
            final dialogElement = tester.element(_dialog);
            final dialogRoute = ModalRoute.of(dialogElement)!;
            final controllers = await _enterDraft(tester, entrance);
            final drafts = controllers
                .map((controller) => controller.value)
                .toList();
            final stateBefore = fixture.timer.state;
            final configBefore = jsonEncode(fixture.timer.config.toJson());
            final roomsBefore = fixture.rooms.rooms;
            final joinedBefore = fixture.rooms.joinedRoomIds;
            final activeBefore = fixture.rooms.activeRoomId;
            var roomChanges = 0;
            fixture.rooms.onLocalChanged = () => roomChanges++;

            if (roundtrip) {
              var brandState = 0;
              for (final brand in ['defaultBrand', 'liquidGlass', 'defaultBrand']) {
                brandState++;
                await tester.runAsync(() async {
                  expect(await fixture.theme.setBrand(brand), isTrue);
                  await AccountPreferenceWrites.drain().timeout(_settleTimeout);
                });
                await _settle(tester);
                expect(tester.element(_dialog), same(dialogElement));
                expect(ModalRoute.of(tester.element(_dialog)), same(dialogRoute));
                expect(dialogRoute.isCurrent, isTrue);
                expect(
                  tester.element(find.byType(PomodoroScreen)),
                  same(screenElement),
                );
                expect(ModalRoute.of(screenElement), same(screenRoute));
                final expected = AppBrands.byId(brand).theme;
                final actual = Theme.of(tester.element(_dialog));
                expect(actual.colorScheme.primary, expected.colorScheme.primary);
                expect(actual.colorScheme.surface, expected.colorScheme.surface);
                expect(
                  appSurfaceStyleOf(tester.element(_dialog)),
                  expected.extension<AppSurfaceStyle>(),
                );
                final material = tester.widget<Material>(
                  find.descendant(
                    of: find.byType(AlertDialog),
                    matching: find.byType(Material),
                  ).first,
                );
                expect(
                  material.color,
                  expected.dialogTheme.backgroundColor ??
                      expected.colorScheme.surface,
                );
                for (var index = 0; index < controllers.length; index++) {
                  expect(
                    tester.widget<TextField>(_fields.at(index)).controller,
                    same(controllers[index]),
                  );
                  expect(controllers[index].value, drafts[index]);
                }
                expect(tester.takeException(), isNull);
                if (captureEvidence) {
                  await fixture.capture(
                    tester,
                    'pomodoro-${entrance.name}-$brandState-$brand',
                  );
                }
              }
            }

            await _cancelDuringReverse(tester, dialogRoute, controllers, drafts);
            expect(fixture.timer.state, same(stateBefore));
            expect(jsonEncode(fixture.timer.config.toJson()), configBefore);
            expect(fixture.rooms.rooms, orderedEquals(roomsBefore));
            expect(fixture.rooms.joinedRoomIds, unorderedEquals(joinedBefore));
            expect(fixture.rooms.activeRoomId, activeBefore);
            expect(roomChanges, 0);
            expect(fixture.timer.state.taskName, _originalTask);
            expect(fixture.timer.state.tag, _originalTag);
            expect(
              tester.element(find.byType(PomodoroScreen)),
              same(screenElement),
            );
            expect(ModalRoute.of(screenElement), same(screenRoute));
          } finally {
            // Flutter checks painting globals before addTearDown callbacks.
            debugDisableShadows = previousShadows;
          }
        },
      );
    }
  }
}
