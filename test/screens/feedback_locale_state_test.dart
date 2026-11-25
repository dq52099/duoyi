import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/feedback_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _content = 'literal / 原始反馈';
const _reply = 'literal / 原始回复';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final large in [false, true]) {
      final name = '$brand-${large ? 'narrow-large' : 'ordinary'}';
      testWidgets('feedback detail follows live theme $name', (tester) async {
        SharedPreferences.setMockInitialValues({
          'active_brand': brand,
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        });
        final theme = ThemeProvider();
        addTearDown(theme.dispose);
        await theme.loadFromStorage();
        final boundary = GlobalKey();
        final requests = <String>[];
        await _pump(
          tester,
          requests,
          const FeedbackScreen(),
          theme: theme,
          size: Size(large ? 320 : 390, 844),
          textScale: large ? 2 : 1,
          screenshotBoundary: boundary,
        );
        expect(
          Theme.of(tester.element(find.byType(FeedbackScreen))).colorScheme,
          theme.brand.theme.colorScheme,
        );
        await tester.tap(
          find.byKey(const ValueKey('feedback_record_card_tap_target')),
        );
        await tester.pumpAndSettle();
        final pageState = tester.state(find.byType(FeedbackScreen));
        final modal = tester.element(find.byType(AppDialog));
        final route = ModalRoute.of(modal)!;
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(AppDialog),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final offset = scroll.position.pixels;
        final requestSnapshot = List<String>.of(requests);

        void expectRetained() {
          final current = tester.element(find.byType(AppDialog));
          expect(current, same(modal));
          expect(ModalRoute.of(current), same(route));
          expect(route.isCurrent, isTrue);
          expect(tester.state(find.byType(FeedbackScreen)), same(pageState));
          expect(Theme.of(current).colorScheme, theme.brand.theme.colorScheme);
          expect(
            tester
                .widgetList<SelectableText>(find.byType(SelectableText))
                .map((text) => text.data),
            containsAll([_content, _reply]),
          );
          expect(
            tester.state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(AppDialog),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            ),
            same(scroll),
          );
          expect(requests, requestSnapshot);
          expect(
            requests.where((request) => request.startsWith('POST')),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        }

        expectRetained();
        await _captureFeedback(tester, boundary, '$name-initial');
        final other = brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand';
        var switched = false;
        theme.setBrand(other).then((_) => switched = true);
        for (var frame = 0; frame < 100 && !switched; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(switched, isTrue);
        await tester.pumpAndSettle();
        expect(theme.brand.id, other);
        expectRetained();
        expect(scroll.position.pixels, closeTo(offset, 0.1));
        await _captureFeedback(tester, boundary, '$name-switched');
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expectRetained();
        _english(tester);

        switched = false;
        theme.setBrand(brand).then((_) => switched = true);
        for (var frame = 0; frame < 100 && !switched; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(switched, isTrue);
        await tester.pumpAndSettle();
        expect(theme.brand.id, brand);
        expectRetained();
        await _captureFeedback(tester, boundary, '$name-return-en');
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pumpAndSettle();
        expect(route.isActive, isFalse);
        expect(find.byType(AppDialog), findsNothing);
        expect(tester.state(find.byType(FeedbackScreen)), same(pageState));
        expect(requests, requestSnapshot);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'feedback draft retains controller focus selection and scroll across locale',
    (tester) async {
      final requests = <String>[];
      await _pump(
        tester,
        requests,
        const FeedbackSubmitScreen(initialCategory: 'bug'),
      );
      final field = find.byKey(const ValueKey('feedback_submit_content'));
      await tester.enterText(field, _content);
      final text = tester.widget<TextField>(field);
      final controller = text.controller!;
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 7,
      );
      final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      final state = tester.state(find.byType(FeedbackSubmitScreen));
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offset = scroll.position.pixels;
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(FeedbackSubmitScreen)), same(state));
      expect(tester.widget<TextField>(field).controller, same(controller));
      expect(controller.text, _content);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 7),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable).first),
        same(scroll),
      );
      expect(scroll.position.pixels, closeTo(offset, 0.1));
      expect(requests, isEmpty);
      _english(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'feedback history detail switches locale without another request or translating user text',
    (tester) async {
      final requests = <String>[];
      await _pump(tester, requests, const FeedbackScreen());
      expect(requests.length, 1);
      await tester.tap(
        find.byKey(const ValueKey('feedback_record_card_tap_target')),
      );
      await tester.pumpAndSettle();
      final screenState = tester.state(find.byType(FeedbackScreen));
      final dialog = tester.element(find.byType(AppDialog));
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(FeedbackScreen)), same(screenState));
      expect(tester.element(find.byType(AppDialog)), same(dialog));
      _english(tester);
      final values = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((text) => text.data)
          .toList();
      expect(values, contains(_content));
      expect(values, contains(_reply));
      expect(requests.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'open feedback category menu switches language without closing or losing draft',
    (tester) async {
      final requests = <String>[];
      await _pump(
        tester,
        requests,
        const FeedbackSubmitScreen(initialCategory: 'bug'),
      );
      final field = find.byKey(const ValueKey('feedback_submit_content'));
      await tester.enterText(field, _content);
      await tester.ensureVisible(find.byType(PopupMenuButton<String>));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(3));
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(3));
      _english(tester);
      expect(requests, isEmpty);
      expect(tester.widget<TextField>(field).controller!.text, _content);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'account replacement dismisses feedback detail without closing foreground route',
    (tester) async {
      final requests = <String>[];
      final auth = await _pump(tester, requests, const FeedbackScreen());
      await tester.tap(
        find.byKey(const ValueKey('feedback_record_card_tap_target')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(AppDialog))).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Foreground page')),
        ),
      );
      await tester.pumpAndSettle();
      await _replace(tester, auth);
      await tester.pumpAndSettle();
      expect(find.text('Foreground page'), findsOneWidget);
      expect(find.byType(AppDialog, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'retained feedback draft cannot post into a replacement session',
    (tester) async {
      final requests = <String>[];
      final auth = await _pump(tester, requests, const FeedbackSubmitScreen());
      await tester.enterText(
        find.byKey(const ValueKey('feedback_submit_content')),
        _content,
      );
      await _replace(tester, auth);
      await tester.tap(
        find.byKey(const ValueKey('feedback_submit_page_button')),
      );
      await tester.pumpAndSettle();
      expect(requests.where((request) => request.startsWith('POST')), isEmpty);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('feedback_submit_content')),
            )
            .controller!
            .text,
        _content,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'departed held feedback result cannot pop the current route or show success',
    (tester) async {
      final requests = <String>[];
      final release = Completer<http.Response>();
      final auth = await _pump(
        tester,
        requests,
        const FeedbackSubmitScreen(),
        release: release,
      );
      await tester.enterText(
        find.byKey(const ValueKey('feedback_submit_content')),
        _content,
      );
      await tester.tap(
        find.byKey(const ValueKey('feedback_submit_page_button')),
      );
      await tester.pump();
      expect(requests.where((request) => request.startsWith('POST')).length, 1);
      await _replace(tester, auth);
      release.complete(
        http.Response(
          '{"id": 7}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackSubmitScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<AuthProvider> _pump(
  WidgetTester tester,
  List<String> requests,
  Widget screen, {
  Completer<http.Response>? release,
  ThemeProvider? theme,
  Size size = const Size(320, 844),
  double textScale = 1.6,
  GlobalKey? screenshotBoundary,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient(
    baseUrl: 'https://duoyi.test',
    token: 'synthetic-feedback-A',
    httpClient: MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'POST') {
        if (release != null) return release.future;
        return http.Response(
          '{"id": 7}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': 1,
              'category': 'bug',
              'status': 'in_progress',
              'content': _content,
              'admin_reply': _reply,
              'created_at': '2026-10-12 12:00',
              'updated_at': '2026-10-12 12:01',
            },
          ],
          'total': 2,
          'page': 1,
          'page_size': 10,
          'total_pages': 2,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  final auth = _FeedbackAuth(client);
  addTearDown(auth.dispose);
  final screenshotDirectory =
      Platform.environment['DUOYI_FEEDBACK_SCREENSHOTS'];
  if (screenshotDirectory != null) {
    await tester.runAsync(loadWeeklyReviewScreenshotFonts);
  }
  final page = screen is FeedbackScreen
      ? (theme == null
            ? ChangeNotifierProvider(
                create: (_) => ThemeProvider(),
                child: BrandRouteSurface(child: screen),
              )
            : ChangeNotifierProvider.value(
                value: theme,
                child: BrandRouteSurface(child: screen),
              ))
      : screen;
  Widget buildApp() => MaterialApp(
    theme: theme?.brand.theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: page,
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: screenshotBoundary,
      child: ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: theme == null
            ? buildApp()
            : AnimatedBuilder(
                animation: theme,
                builder: (context, child) => buildApp(),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return auth;
}

Future<void> _captureFeedback(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final directory = Platform.environment['DUOYI_FEEDBACK_SCREENSHOTS'];
  if (directory == null) return;
  if (!directory.startsWith('evidence/screenshots/')) {
    throw StateError('Screenshot path must be under evidence/screenshots/');
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _replace(WidgetTester tester, AuthProvider auth) async {
  var finished = false;
  final pending = () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'auth_state',
      jsonEncode(
        const AuthState(
          userId: 'feedback-B',
          username: 'B',
          token: 'synthetic-feedback-B',
        ).toJson(),
      ),
    );
    await auth.loadFromStorage(refreshServerConfig: false);
  }().whenComplete(() => finished = true);
  for (var frame = 0; frame < 100 && !finished; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finished, isTrue);
  await pending;
  await tester.pump(const Duration(milliseconds: 50));
  expect(auth.state.userId, 'feedback-B');
}

void _english(WidgetTester tester) {
  final labels = <String>[
    for (final text in tester.widgetList<Text>(find.byType(Text)))
      text.data ?? text.textSpan?.toPlainText() ?? '',
    for (final tooltip in tester.widgetList<Tooltip>(find.byType(Tooltip)))
      tooltip.message ?? '',
    for (final field in tester.widgetList<TextField>(
      find.byType(TextField),
    )) ...[
      field.decoration?.labelText ?? '',
      field.decoration?.hintText ?? '',
      field.decoration?.helperText ?? '',
      field.decoration?.errorText ?? '',
    ],
  ];
  expect(
    labels.where(
      (label) =>
          label != _content &&
          label != _reply &&
          RegExp(r'[\u3400-\u9fff]').hasMatch(label),
    ),
    isEmpty,
  );
}

// Keep recording direct feedback API requests after real storage hydration
// replaces AuthProvider's internal transport. The real session epoch/lease
// logic still runs; an attempted write from a retained draft is observable.
class _FeedbackAuth extends AuthProvider {
  _FeedbackAuth(this.fixture)
    : super(
        initialState: const AuthState(
          userId: 'feedback-A',
          username: 'A',
          token: 'synthetic-feedback-A',
        ),
        client: fixture,
      );
  final ApiClient fixture;
  @override
  ApiClient get client => fixture;
}
