import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/ai_schedule_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _input = 'literal / 安排原文';
const _title = 'literal / 日程标题';
const _notes = 'literal / 日程备注';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'AI schedule input retains focus selection and scroll on locale change',
    (tester) async {
      final ai = _ScheduleAi();
      await _pump(tester, ai);
      final field = find.byType(TextField).first;
      await tester.enterText(field, _input);
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 7,
      );
      final editable = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      final screenState = tester.state(find.byType(AiScheduleScreen));
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offset = scroll.position.pixels;
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AiScheduleScreen)), same(screenState));
      expect(tester.widget<TextField>(field).controller, same(controller));
      expect(controller.text, _input);
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
      expect(ai.recognitions, 0);
      _expectEnglish(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'AI schedule draft localizes labels while preserving returned user data',
    (tester) async {
      final ai = _ScheduleAi();
      await _pump(tester, ai);
      await tester.enterText(find.byType(TextField).first, _input);
      await tester.ensureVisible(_recognizeButton());
      await tester.tap(_recognizeButton());
      await tester.pumpAndSettle();
      expect(ai.recognitions, 1);
      expect(find.text(_title), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_notes), findsOneWidget);
      expect(ai.recognitions, 1);
      _expectEnglish(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'AI schedule held recognition cannot publish draft after account replacement',
    (tester) async {
      final ai = _ScheduleAi()..held = true;
      final auth = await _pump(tester, ai);
      await tester.enterText(find.byType(TextField).first, _input);
      await tester.ensureVisible(_recognizeButton());
      await tester.tap(_recognizeButton());
      await tester.pump();
      expect(ai.recognitions, 1);
      await _replace(tester, auth);
      ai.release.complete(_draft());
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'AI schedule retained input cannot start recognition for replacement account',
    (tester) async {
      final ai = _ScheduleAi();
      final auth = await _pump(tester, ai);
      await tester.enterText(find.byType(TextField).first, _input);
      await _replace(tester, auth);
      await tester.ensureVisible(_recognizeButton());
      await tester.tap(_recognizeButton());
      await tester.pumpAndSettle();
      expect(ai.recognitions, 0);
      expect(find.text(_title), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Finder _recognizeButton() => find
    .ancestor(
      of: find.byIcon(Icons.manage_search_outlined),
      matching: find.byType(FilledButton),
    )
    .first;

AiScheduleDraft _draft() => AiScheduleDraft(
  type: AiScheduleType.calendar,
  title: _title,
  notes: _notes,
  startAt: DateTime(2026, 10, 13, 15),
  endAt: DateTime(2026, 10, 13, 16),
);

Future<AuthProvider> _pump(WidgetTester tester, _ScheduleAi ai) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = AuthProvider(
    initialState: const AuthState(
      userId: 'schedule-A',
      username: 'account-A',
      token: 'synthetic-schedule-A',
    ),
    client: ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-schedule-A',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    ),
  );
  final theme = ThemeProvider();
  addTearDown(auth.dispose);
  addTearDown(ai.dispose);
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AiService>.value(value: ai),
      ],
      child: MaterialApp(
        theme: theme.brand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: const AiScheduleScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<void> _replace(WidgetTester tester, AuthProvider auth) async {
  var finished = false;
  final pending = () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'auth_state',
      jsonEncode(
        const AuthState(
          userId: 'schedule-B',
          username: 'account-B',
          token: 'synthetic-schedule-B',
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
  expect(auth.state.userId, 'schedule-B');
}

void _expectEnglish(WidgetTester tester) {
  final chinese = RegExp(r'[\u3400-\u9fff]');
  final text = <String>[
    for (final widget in tester.widgetList<Text>(find.byType(Text)))
      widget.data ?? widget.textSpan?.toPlainText() ?? '',
    for (final widget in tester.widgetList<TextField>(
      find.byType(TextField),
    )) ...[
      widget.decoration?.labelText ?? '',
      widget.decoration?.hintText ?? '',
      widget.decoration?.helperText ?? '',
      widget.decoration?.errorText ?? '',
    ],
  ];
  expect(
    text.where((s) => s != _title && s != _notes && chinese.hasMatch(s)),
    isEmpty,
  );
}

class _ScheduleAi extends AiService {
  bool held = false;
  int recognitions = 0;
  final release = Completer<AiScheduleDraft>();
  @override
  bool get enabled => false;
  @override
  Future<AiScheduleDraft> createScheduleDraft(
    String input, {
    DateTime? now,
  }) async {
    recognitions++;
    return held ? release.future : _draft();
  }
}
