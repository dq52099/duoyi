import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/goal_screen.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Login countdown follows locale without restarting request or form',
    (tester) async {
      final auth = _EmailCodeAuth();
      final theme = ThemeProvider();
      addTearDown(auth.dispose);
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.tap(find.text(I18n.tr('auth.email_code_login')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'reader@example.test',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, I18n.tr('auth.send')));
      await tester.pumpAndSettle();
      expect(auth.requests, 1);
      final screen = tester.state<State<LoginScreen>>(find.byType(LoginScreen));
      final initial = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      final controller = initial.controller;
      final focus = initial.focusNode;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      focus.requestFocus();
      await tester.pump();

      I18n.setLocale(AppLocale.en);
      // A locale event alone must update the retained route before the next tick.
      await tester.pump();
      expect(find.text('Retry in 60s'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Retry in 60s'),
      );
      expect(button.onPressed, isNull);
      final retained = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(
        tester.state<State<LoginScreen>>(find.byType(LoginScreen)),
        same(screen),
      );
      expect(retained.controller, same(controller));
      expect(retained.focusNode, same(focus));
      expect(controller.text, 'reader@example.test');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      expect(focus.hasFocus, isTrue);
      expect(auth.requests, 1);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Retry in 59s'), findsOneWidget);
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(find.text('59s 后'), findsOneWidget);
      expect(auth.requests, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('Goal fallbacks follow locale and retain saved content', (
    tester,
  ) async {
    final goals = _StaticGoals([
      GoalItem(
        id: 'synthetic-shared-goal',
        title: '自定义 / user title',
        description: '原文 / user description',
        workspaceId: 'missing-synthetic-workspace',
      ),
    ]);
    addTearDown(goals.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<GoalProvider>.value(
        value: goals,
        child: const MaterialApp(home: GoalScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无期限'), findsOneWidget);
    expect(find.text('共享'), findsOneWidget);
    final element = tester.element(find.byType(GoalScreen));
    for (final locale in [AppLocale.en, AppLocale.zh, AppLocale.en]) {
      I18n.setLocale(locale);
      await tester.pump();
      expect(tester.element(find.byType(GoalScreen)), same(element));
      expect(
        find.text(locale == AppLocale.en ? 'No deadline' : '无期限'),
        findsOneWidget,
      );
      expect(
        find.text(locale == AppLocale.en ? 'Shared' : '共享'),
        findsOneWidget,
      );
      expect(find.text('自定义 / user title'), findsOneWidget);
      expect(find.text('原文 / user description'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(goals.notifications, 0);
  });
}

class _EmailCodeAuth extends AuthProvider {
  int requests = 0;

  @override
  Future<Map<String, dynamic>> sendEmailCode({
    required String email,
    String purpose = 'login',
  }) async {
    requests++;
    return {'message': 'Synthetic mail delivery'};
  }
}

class _StaticGoals extends GoalProvider {
  final List<GoalItem> _items;
  int notifications = 0;

  _StaticGoals(this._items);

  @override
  List<GoalItem> get goals => _items;

  @override
  void notifyListeners() {
    notifications++;
    super.notifyListeners();
  }
}
