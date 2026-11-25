import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/todo_detail_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';
import '../support/weekly_review_screenshot_font.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  _registerTodoModalThemeTests();
  _registerQuadrantReadabilityTests();

  testWidgets(
    'branded router detail retains its editing draft and selection across locale changes and discard cancellation',
    (tester) async {
      final fixture = await _mountRouter(tester);
      final editor = await _editDraft(tester);
      final original = fixture.provider.todos.single.toJson();

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();

        editor.expectRetained(tester);
        _expectLocalizedDetail(tester);
        expect(fixture.routeCompletions, 0);
        expect(fixture.provider.todos.single.toJson(), original);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(_backButton());
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text(TodoDetailUiCopy.discardDialogTitle), findsOneWidget);
      expect(find.text(TodoDetailUiCopy.discardDialogContent), findsOneWidget);
      expect(fixture.routeCompletions, 0);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      expect(
        find.text(
          'Current changes are not saved. Returning will discard them.',
        ),
        findsOneWidget,
      );
      expect(find.text('放弃未保存的修改？'), findsNothing);
      expect(editor.state.mounted, isTrue);
      expect(
        tester.state(find.byType(TodoDetailScreen, skipOffstage: false)),
        same(editor.state),
      );

      await tester.tap(
        find.widgetWithText(TextButton, TodoDetailUiCopy.cancel),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      editor.expectRetained(tester);
      _expectLocalizedDetail(tester);
      expect(fixture.routeCompletions, 0);
      expect(fixture.provider.todos.single.toJson(), original);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      editor.expectRetained(tester);
      _expectLocalizedDetail(tester);
      await tester.tap(_backButton());
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(TextButton, TodoDetailUiCopy.discardAction),
      );
      await tester.pumpAndSettle();

      expect(editor.state.mounted, isFalse);
      expect(editor.route.isActive, isFalse);
      expect(find.byType(TodoDetailScreen), findsNothing);
      expect(find.byType(BrandRouteSurface), findsNothing);
      expect(find.text('router-home'), findsOneWidget);
      expect(fixture.routeCompletions, 1);
      expect(fixture.provider.todos.single.toJson(), original);
      expect(await _storedTodos(), [original]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving a localized branded detail persists its retained draft and returns to the router source',
    (tester) async {
      final fixture = await _mountRouter(tester);
      final editor = await _editDraft(tester);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();

        editor.expectRetained(tester);
        _expectLocalizedDetail(tester);
        expect(fixture.provider.todos.single.title, fixture.original.title);
        expect(fixture.provider.todos.single.notes, fixture.original.notes);
        expect(fixture.routeCompletions, 0);
      }

      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      final saved = fixture.provider.todos.single;
      expect(saved.id, fixture.original.id);
      expect(saved.title, _draftTitle);
      expect(saved.notes, _draftNotes);
      expect(saved.isCompleted, fixture.original.isCompleted);
      expect(saved.tags, fixture.original.tags);
      expect(await _storedTodos(), [saved.toJson()]);
      expect(find.byType(AppDialog), findsNothing);
      expect(editor.state.mounted, isFalse);
      expect(editor.route.isActive, isFalse);
      expect(find.byType(TodoDetailScreen), findsNothing);
      expect(find.byType(BrandRouteSurface), findsNothing);
      expect(find.text('router-home'), findsOneWidget);
      expect(fixture.routeCompletions, 1);
      expect(
        Navigator.of(tester.element(find.byKey(_openDetailKey))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

const _openDetailKey = ValueKey('open-branded-todo-detail');
const _draftTitle = 'Literal 混合 task draft';
const _draftNotes = 'Unsaved notes **原文**\nSecond draft line';
const _titleSelection = TextSelection(baseOffset: 2, extentOffset: 10);
const _notesSelection = TextSelection(baseOffset: 8, extentOffset: 18);

Finder _titleField() => find.descendant(
  of: find.byType(TodoDetailScreen),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText == TodoDetailUiCopy.taskTitleLabel,
  ),
);

Finder _notesField() => find.descendant(
  of: find.byType(TodoDetailScreen),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == TodoDetailUiCopy.markdownHint,
  ),
);

Finder _backButton() => find.descendant(
  of: find.byType(TodoDetailScreen),
  matching: find.widgetWithIcon(IconButton, Icons.arrow_back),
);

void _expectLocalizedDetail(WidgetTester tester) {
  final english = I18n.current == AppLocale.en;
  expect(find.text(english ? 'Task Details' : '任务详情'), findsOneWidget);
  expect(find.text(english ? '任务详情' : 'Task Details'), findsNothing);
  expect(_titleField(), findsOneWidget);
  expect(
    tester.widget<TextField>(_titleField()).decoration?.labelText,
    english ? 'Task title' : '任务名称',
  );
  expect(find.text(english ? 'Description' : '任务描述'), findsOneWidget);
  expect(
    tester.widget<TextField>(_notesField()).decoration?.hintText,
    english ? 'Markdown description supported' : '支持 Markdown 描述',
  );
  expect(find.byTooltip(english ? 'Save' : '保存'), findsOneWidget);
  expect(
    find.byTooltip(english ? 'Preview description' : '预览描述'),
    findsOneWidget,
  );
}

Future<_EditorSnapshot> _editDraft(WidgetTester tester) async {
  final editor = _EditorSnapshot(
    state: tester.state(find.byType(TodoDetailScreen)),
    route: ModalRoute.of(tester.element(find.byType(TodoDetailScreen)))!,
    title: tester.widget<TextField>(_titleField()).controller!,
    notes: tester.widget<TextField>(_notesField()).controller!,
  );
  await tester.enterText(_titleField(), _draftTitle);
  await tester.enterText(_notesField(), _draftNotes);
  editor.title.selection = _titleSelection;
  editor.notes.selection = _notesSelection;
  await tester.pump();
  editor.expectRetained(tester);
  return editor;
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.state,
    required this.route,
    required this.title,
    required this.notes,
  });

  final State<TodoDetailScreen> state;
  final ModalRoute<dynamic> route;
  final TextEditingController title;
  final TextEditingController notes;

  void expectRetained(WidgetTester tester) {
    expect(state.mounted, isTrue);
    expect(route.isActive, isTrue);
    expect(route.isCurrent, isTrue);
    expect(tester.state(find.byType(TodoDetailScreen)), same(state));
    expect(
      ModalRoute.of(tester.element(find.byType(TodoDetailScreen))),
      same(route),
    );
    expect(tester.widget<TextField>(_titleField()).controller, same(title));
    expect(tester.widget<TextField>(_notesField()).controller, same(notes));
    expect(title.text, _draftTitle);
    expect(notes.text, _draftNotes);
    expect(title.selection, _titleSelection);
    expect(notes.selection, _notesSelection);
    final popScope = tester.widget<PopScope<dynamic>>(
      find.descendant(
        of: find.byType(TodoDetailScreen),
        matching: find.byWidgetPredicate(
          (widget) => widget is PopScope<dynamic>,
        ),
      ),
    );
    expect(popScope.canPop, isFalse, reason: 'The unsaved draft stays editing');
  }
}

Future<List<dynamic>> _storedTodos() async {
  final preferences = await SharedPreferences.getInstance();
  return jsonDecode(preferences.getString('todos')!) as List<dynamic>;
}

Future<_RouterFixture> _mountRouter(
  WidgetTester tester, {
  String? initialBrand,
  Size size = const Size(700, 1400),
  double textScale = 1,
}) async {
  if (initialBrand != null) {
    SharedPreferences.setMockInitialValues({
      'active_brand': initialBrand,
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'theme_shop_state': jsonEncode({
        'activeBrand': initialBrand,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
    });
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fixture = _RouterFixture();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    fixture.provider.dispose();
    fixture.theme.dispose();
  });
  await fixture.provider.addTodo(fixture.original);
  if (initialBrand != null) {
    await tester.runAsync(() async {
      await fixture.theme.loadFromStorage();
      await loadWeeklyReviewScreenshotFonts();
    });
  }
  Widget buildApp({ThemeData? theme}) => MaterialApp(
    theme: theme,
    builder: (context, child) => RepaintBoundary(
      key: fixture.screenshotBoundary,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('router-home'),
              TextButton(
                key: _openDetailKey,
                onPressed: () => unawaited(
                  TodayDetailRouter.open(
                    context,
                    TodaySectionKind.todos,
                    id: fixture.original.id,
                  ).then<void>((_) {
                    fixture.routeCompletions++;
                  }),
                ),
                child: const Text('Open task'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: fixture.provider),
        ChangeNotifierProvider<ThemeProvider>.value(value: fixture.theme),
      ],
      child: initialBrand == null
          ? buildApp()
          : Consumer<ThemeProvider>(
              builder: (_, current, _) => buildApp(theme: current.brand.theme),
            ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_openDetailKey));
  await tester.pumpAndSettle();
  expect(find.byType(TodoDetailScreen), findsOneWidget);
  final brandSurface = find.ancestor(
    of: find.byType(TodoDetailScreen),
    matching: find.byType(BrandRouteSurface),
  );
  expect(brandSurface, findsOneWidget);
  expect(
    tester.widget<BrandRouteSurface>(brandSurface).remountOnLocaleChange,
    isTrue,
    reason: 'Exercise the production router with its default brand wrapper',
  );
  expect(fixture.routeCompletions, 0);
  _expectLocalizedDetail(tester);
  expect(tester.takeException(), isNull);
  return fixture;
}

class _RouterFixture {
  final screenshotBoundary = GlobalKey();
  final provider = TodoProvider()..scheduler = RecordingReminderScheduler();
  final theme = ThemeProvider();
  final original = TodoItem(
    id: 'branded-locale-task',
    title: 'Original 原始 task',
    notes: 'Original 备注',
    tags: ['Literal 标签'],
  );
  int routeCompletions = 0;
}

Finder _modalField(String label) => find.descendant(
  of: find.byType(AppDialog),
  matching: find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  ),
);

Future<void> _captureTodoModal(
  WidgetTester tester,
  _RouterFixture fixture,
  String name,
) async {
  final directory = Platform.environment['DUOYI_TODO_MODAL_CAPTURE_DIR'];
  if (directory == null) return;
  if (!directory.startsWith('evidence/screenshots/')) {
    throw StateError('Screenshot path must be under evidence/screenshots');
  }
  await tester.runAsync(() async {
    final boundary =
        fixture.screenshotBoundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _registerTodoModalThemeTests() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final attachment in [true, false]) {
      final kind = attachment ? 'attachment' : 'discard';
      testWidgets('Todo modal live theme $brand $kind retains draft and route', (
        tester,
      ) async {
        final fixture = await _mountRouter(
          tester,
          initialBrand: brand,
          size: brand == 'defaultBrand'
              ? const Size(390, 844)
              : const Size(320, 844),
          textScale: brand == 'defaultBrand' ? 1 : 2,
        );
        final editor = await _editDraft(tester);
        final original = fixture.original.toJson();
        if (attachment) {
          FocusManager.instance.primaryFocus?.unfocus();
          final button = find.byTooltip(TodoDetailUiCopy.addLinkTooltip);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.tap(button);
        } else {
          await tester.tap(_backButton());
        }
        await tester.pumpAndSettle();
        final modal = find.byType(AppDialog);
        final element = tester.element(modal);
        final route = ModalRoute.of(element);
        final controllers = <TextEditingController>[];
        if (attachment) {
          for (final pair in [
            (TodoDetailUiCopy.attachmentNameLabel, 'Unsaved manual guide'),
            (
              TodoDetailUiCopy.attachmentUriLabel,
              'https://example.test/guide.pdf',
            ),
            (TodoDetailUiCopy.attachmentMimeLabel, 'application/pdf'),
          ]) {
            final field = _modalField(pair.$1);
            await tester.ensureVisible(field);
            await tester.enterText(field, pair.$2);
            controllers.add(tester.widget<TextField>(field).controller!);
          }
          controllers[1].selection = const TextSelection(
            baseOffset: 8,
            extentOffset: 15,
          );
          await tester.pump();
        }
        final otherBrand = brand == 'defaultBrand'
            ? 'liquidGlass'
            : 'defaultBrand';
        var stage = 0;
        for (final nextBrand in [brand, otherBrand, brand]) {
          await tester.runAsync(() async {
            expect(await fixture.theme.setBrand(nextBrand), isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await tester.pumpAndSettle();
          expect(tester.element(modal), same(element));
          expect(ModalRoute.of(tester.element(modal)), same(route));
          expect(
            Theme.of(tester.element(modal)).colorScheme,
            fixture.theme.brand.theme.colorScheme,
            reason: 'Opened Todo $kind must follow $nextBrand',
          );
          expect(
            appSurfaceStyleOf(tester.element(modal)),
            fixture.theme.brand.theme.extension<AppSurfaceStyle>(),
          );
          expect(
            tester.state(find.byType(TodoDetailScreen)),
            same(editor.state),
          );
          expect(editor.title.text, _draftTitle);
          expect(editor.notes.text, _draftNotes);
          expect(editor.title.selection, _titleSelection);
          expect(editor.notes.selection, _notesSelection);
          expect(fixture.provider.todos.single.toJson(), original);
          expect(await _storedTodos(), [original]);
          if (attachment) {
            final fields = [
              TodoDetailUiCopy.attachmentNameLabel,
              TodoDetailUiCopy.attachmentUriLabel,
              TodoDetailUiCopy.attachmentMimeLabel,
            ];
            for (var i = 0; i < fields.length; i++) {
              expect(
                tester.widget<TextField>(_modalField(fields[i])).controller,
                same(controllers[i]),
              );
            }
            expect(controllers.map((c) => c.text), [
              'Unsaved manual guide',
              'https://example.test/guide.pdf',
              'application/pdf',
            ]);
            expect(
              controllers[1].selection,
              const TextSelection(baseOffset: 8, extentOffset: 15),
            );
          }
          expect(tester.takeException(), isNull);
          if (stage < 2) {
            await _captureTodoModal(
              tester,
              fixture,
              '$brand-$kind-$stage-$nextBrand',
            );
          }
          stage++;
        }
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(tester.element(modal), same(element));
        expect(
          find.text(
            attachment
                ? TodoDetailUiCopy.addAttachmentLinkDialogTitle
                : TodoDetailUiCopy.discardDialogTitle,
          ),
          findsOneWidget,
        );
        if (attachment) {
          expect(_modalField('Name'), findsOneWidget);
          expect(_modalField('Link or local path'), findsOneWidget);
          expect(controllers[0].text, 'Unsaved manual guide');
        }
        await _captureTodoModal(tester, fixture, '$brand-$kind-en');
        final accept = brand == 'liquidGlass';
        final action = find.widgetWithText(
          attachment && accept ? FilledButton : TextButton,
          accept
              ? (attachment
                    ? TodoDetailUiCopy.add
                    : TodoDetailUiCopy.discardAction)
              : TodoDetailUiCopy.cancel,
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(modal, findsNothing);
        if (attachment) {
          for (final controller in controllers) {
            expect(
              () => controller.addListener(() {}),
              throwsFlutterError,
              reason:
                  'Manual attachment controllers must be released after the dialog exit animation',
            );
          }
          final scrollable = find
              .descendant(
                of: find.byType(TodoDetailScreen),
                matching: find.byType(Scrollable),
              )
              .first;
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
        }
        if (accept && !attachment) {
          expect(find.byType(TodoDetailScreen), findsNothing);
          expect(fixture.routeCompletions, 1);
          expect(await _storedTodos(), [original]);
        } else {
          editor.expectRetained(tester);
          expect(fixture.provider.todos.single.toJson(), original);
          if (accept) {
            await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
            await tester.pumpAndSettle();
            final saved = fixture.provider.todos.single;
            expect(saved.title, _draftTitle);
            expect(saved.notes, _draftNotes);
            expect(saved.attachments.single.name, 'Unsaved manual guide');
            expect(
              saved.attachments.single.uri,
              'https://example.test/guide.pdf',
            );
            expect(saved.attachments.single.mimeType, 'application/pdf');
            expect(await _storedTodos(), [saved.toJson()]);
            expect(fixture.routeCompletions, 1);
          } else {
            expect(await _storedTodos(), [original]);
            expect(fixture.routeCompletions, 0);
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

void _registerQuadrantReadabilityTests() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in const [
        (name: 'ordinary', size: Size(390, 844), scale: 1.0),
        (name: 'narrow-large', size: Size(320, 844), scale: 2.0),
        (name: 'landscape-large', size: Size(568, 320), scale: 2.0),
      ]) {
        final name = '$brand-${locale.name}-${layout.name}';
        testWidgets('Todo selected quadrant full label $name', (tester) async {
          I18n.setLocale(locale);
          final fixture = await _mountRouter(
            tester,
            initialBrand: brand,
            size: layout.size,
            textScale: layout.scale,
          );
          final route = find.byType(TodoDetailScreen);
          final state = tester.state(route);
          final original = fixture.original.toJson();
          final titleController = tester
              .widget<TextField>(_titleField())
              .controller!;
          await tester.enterText(_titleField(), _draftTitle);
          titleController.selection = _titleSelection;
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          final anchor = find.byType(AppDropdownField<EisenhowerQuadrant>);
          final scroll = find
              .descendant(of: route, matching: find.byType(Scrollable))
              .first;
          Future<void> revealAnchor() async {
            tester.state<ScrollableState>(scroll).position.jumpTo(0);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(anchor, 120, scrollable: scroll);
            await tester.ensureVisible(anchor);
            await tester.pumpAndSettle();
          }

          String label(EisenhowerQuadrant value) => switch (value) {
            EisenhowerQuadrant.urgentImportant => TodoDetailUiCopy.quadrantQ1,
            EisenhowerQuadrant.notUrgentImportant =>
              TodoDetailUiCopy.quadrantQ2,
            EisenhowerQuadrant.urgentNotImportant =>
              TodoDetailUiCopy.quadrantQ3,
            EisenhowerQuadrant.notUrgentNotImportant =>
              TodoDetailUiCopy.quadrantQ4,
          };
          void checkText(Finder finder, String expected) {
            final rich = find.descendant(
              of: finder,
              matching: find.byType(RichText),
            );
            final paragraph = tester.renderObject<RenderParagraph>(rich);
            expect(paragraph.text.toPlainText(), expected);
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason:
                  'Complete selected/menu quadrant label required: $expected at $name',
            );
            final painter = TextPainter(
              text: paragraph.text,
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
              locale: paragraph.locale,
              maxLines: paragraph.maxLines,
              ellipsis: paragraph.overflow == TextOverflow.ellipsis
                  ? '\u2026'
                  : null,
            )..layout(maxWidth: paragraph.size.width);
            try {
              expect(painter.didExceedMaxLines, isFalse, reason: expected);
              expect(
                painter.height,
                lessThanOrEqualTo(paragraph.size.height + 0.5),
              );
              expect(
                paragraph.textScaler.scale(14),
                closeTo(14 * layout.scale, 0.01),
              );
              expect(paragraph.text.style!.fontSize, greaterThanOrEqualTo(12));
              for (final word in RegExp(r'[A-Za-z0-9]+').allMatches(expected)) {
                final boxes = paragraph.getBoxesForSelection(
                  TextSelection(baseOffset: word.start, extentOffset: word.end),
                );
                expect(boxes, isNotEmpty);
                expect(
                  boxes.map((box) => box.top.round()).toSet(),
                  hasLength(1),
                  reason: word.group(0),
                );
              }
            } finally {
              painter.dispose();
            }
          }

          Future<void> checkSelected(EisenhowerQuadrant value) async {
            await revealAnchor();
            final text = find.descendant(
              of: anchor,
              matching: find.text(label(value)),
            );
            expect(text, findsOneWidget);
            checkText(text, label(value));
            expect(tester.state(route), same(state));
            expect(titleController.text, _draftTitle);
            expect(titleController.selection, _titleSelection);
            expect(fixture.provider.todos.single.toJson(), original);
            expect(await _storedTodos(), [original]);
            expect(tester.takeException(), isNull);
          }

          await checkSelected(EisenhowerQuadrant.notUrgentImportant);
          await _captureTodoModal(tester, fixture, 'quadrant-$name-initial');
          for (final selected in EisenhowerQuadrant.values) {
            await tester.tap(anchor);
            await tester.pumpAndSettle();
            final menu = find.byWidgetPredicate(
              (w) => w is PopupMenuItem<EisenhowerQuadrant>,
            );
            expect(menu, findsNWidgets(4));
            for (final value in EisenhowerQuadrant.values) {
              final text = find.descendant(
                of: menu,
                matching: find.text(label(value)),
              );
              await tester.ensureVisible(text);
              await tester.pumpAndSettle();
              checkText(text, label(value));
            }
            final choice = find.descendant(
              of: menu,
              matching: find.text(label(selected)),
            );
            await tester.ensureVisible(choice);
            await tester.pumpAndSettle();
            await tester.tap(choice);
            await tester.pumpAndSettle();
            await checkSelected(selected);
          }
          final other = locale == AppLocale.zh ? AppLocale.en : AppLocale.zh;
          for (final next in [other, locale]) {
            I18n.setLocale(next);
            await tester.pumpAndSettle();
            await checkSelected(EisenhowerQuadrant.notUrgentNotImportant);
          }
          await _captureTodoModal(tester, fixture, 'quadrant-$name-final');
          await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
          await tester.pumpAndSettle();
          final saved = fixture.provider.todos.single;
          expect(saved.title, _draftTitle);
          expect(saved.quadrant, EisenhowerQuadrant.notUrgentNotImportant);
          expect(saved.notes, fixture.original.notes);
          expect(saved.tags, fixture.original.tags);
          expect(await _storedTodos(), [saved.toJson()]);
          expect(find.byType(TodoDetailScreen), findsNothing);
          expect(fixture.routeCompletions, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
