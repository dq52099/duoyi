import 'package:duoyi/core/achievements.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/achievement_feedback_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _feedbackKey = ValueKey('achievement-feedback');

AchievementContext _context({int completedTodos = 0}) => AchievementContext(
  totalTodos: completedTodos,
  completedTodos: completedTodos,
  longestHabitStreak: 0,
  habitCount: 0,
  focusMinutes: 0,
  focusSessions: 0,
  diaryStreak: 0,
  diaryCount: 0,
  goalsTotal: 0,
  goalsAchieved: 0,
  anniversaries: 0,
  courses: 0,
  notes: 0,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.en);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'shows a real unlock banner, updates locale, and does not duplicate',
    (tester) async {
      final harness = _Harness();
      final provider = await harness.createProvider();
      await _mount(tester, harness, provider);

      await provider.updateContext(_context(completedTodos: 1));
      await tester.pumpAndSettle();

      expect(find.byKey(_feedbackKey), findsOneWidget);
      expect(find.text('Achievement unlocked: First step'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Achievement unlocked: First step'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );

      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(find.text('解锁成就：启程'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.byKey(
                      const ValueKey('achievement-feedback-close'),
                    ),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .label,
        '关闭',
      );

      // Persistence notifications and a repeated snapshot must not enqueue the
      // same badge a second time.
      await provider.updateContext(_context(completedTodos: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(_feedbackKey), findsOneWidget);
      expect(find.text('解锁成就：启程'), findsOneWidget);
    },
  );

  testWidgets(
    'clears visible and queued badges on account invalidation and never replays',
    (tester) async {
      final harness = _Harness();
      final provider = await harness.createProvider();
      await _mount(tester, harness, provider);

      await provider.updateContext(_context(completedTodos: 1));
      await tester.pumpAndSettle();
      expect(find.text('Achievement unlocked: First step'), findsOneWidget);

      await provider.updateContext(_context(completedTodos: 100));
      await tester.pumpAndSettle();
      expect(find.text('Achievement unlocked: First step'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(
        find.text('Achievement unlocked: Getting things done'),
        findsOneWidget,
      );

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_feedbackKey), findsNothing);

      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(find.text('Achievement unlocked: First step'), findsNothing);
      expect(
        find.text('Achievement unlocked: Getting things done'),
        findsNothing,
      );
    },
  );

  testWidgets('lock and must-update changes hide feedback without replay', (
    tester,
  ) async {
    final harness = _Harness();
    final provider = await harness.createProvider();
    await _mount(tester, harness, provider);

    await provider.updateContext(_context(completedTodos: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(_feedbackKey), findsOneWidget);

    harness.lock.setLocked(true);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_feedbackKey), findsNothing);

    harness.lock.setLocked(false);
    await tester.pump();
    expect(find.byKey(_feedbackKey), findsNothing);

    await provider.updateContext(_context(completedTodos: 10));
    await tester.pumpAndSettle();
    expect(
      find.text('Achievement unlocked: Getting things done'),
      findsOneWidget,
    );

    harness.updater.setRequired(true);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_feedbackKey), findsNothing);

    harness.updater.setRequired(false);
    await tester.pump();
    expect(find.byKey(_feedbackKey), findsNothing);
  });

  testWidgets('provider replacement discards old visible and queued feedback', (
    tester,
  ) async {
    final harness = _Harness();
    final oldProvider = await harness.createProvider();
    // Prepare both providers before the old one persists any unlocked state.
    final replacement = await harness.createProvider();
    await _mount(tester, harness, oldProvider);

    await oldProvider.updateContext(_context(completedTodos: 10));
    await tester.pumpAndSettle();
    expect(find.text('Achievement unlocked: First step'), findsOneWidget);

    await tester.pumpWidget(harness.app(replacement));
    await tester.pumpAndSettle();
    expect(find.byKey(_feedbackKey), findsNothing);

    oldProvider.resetLocalState();
    await tester.pump();
    expect(find.byKey(_feedbackKey), findsNothing);

    await replacement.updateContext(_context(completedTodos: 1));
    await tester.pumpAndSettle();
    expect(find.text('Achievement unlocked: First step'), findsOneWidget);
    expect(
      find.text('Achievement unlocked: Getting things done'),
      findsNothing,
    );
  });

  testWidgets(
    'storage reset clears visible and pending feedback without closing another snackbar',
    (tester) async {
      final harness = _Harness();
      final provider = await harness.createProvider();
      await _mount(tester, harness, provider);
      final messenger = ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold)),
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unrelated operation'),
          duration: Duration(seconds: 30),
        ),
      );
      await provider.updateContext(_context(completedTodos: 100));
      await tester.pumpAndSettle();
      expect(find.text('Unrelated operation'), findsOneWidget);
      expect(find.byKey(_feedbackKey), findsOneWidget);
      provider.resetLocalState();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(find.text('Unrelated operation'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(find.text('Unrelated operation'), findsOneWidget);
    },
  );

  testWidgets('banner stays above a 300 pixel keyboard inset', (tester) async {
    final harness = _Harness(viewInsetsBottom: 300);
    final provider = await harness.createProvider();
    await _mount(tester, harness, provider);

    await provider.updateContext(_context(completedTodos: 1));
    await tester.pumpAndSettle();

    final banner = find.byKey(_feedbackKey);
    expect(banner, findsOneWidget);
    final bannerBounds = tester.getRect(banner);
    expect(
      bannerBounds.bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - 300),
    );
  });

  testWidgets(
    'enabling accessible navigation retains an already visible banner',
    (tester) async {
      final harness = _Harness(accessibleNavigation: false);
      final provider = await harness.createProvider();
      await _mount(tester, harness, provider);
      await provider.updateContext(_context(completedTodos: 1));
      await tester.pumpAndSettle();
      harness.accessibleNavigation = true;
      await tester.pumpWidget(harness.app(provider));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(_feedbackKey), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('achievement-feedback-close')),
      );
      await tester.pump();
      expect(find.byKey(_feedbackKey), findsNothing);
    },
  );

  testWidgets('accessible navigation keeps feedback visible until Close', (
    tester,
  ) async {
    final harness = _Harness(accessibleNavigation: true);
    final provider = await harness.createProvider();
    await _mount(tester, harness, provider);

    await provider.updateContext(_context(completedTodos: 1));
    await tester.pumpAndSettle();
    expect(find.text('Achievement unlocked: First step'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(_feedbackKey), findsOneWidget);
    expect(find.text('Achievement unlocked: First step'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('achievement-feedback-close')));
    await tester.pump();
    expect(find.byKey(_feedbackKey), findsNothing);
  });
}

Future<void> _mount(
  WidgetTester tester,
  _Harness harness,
  AchievementProvider provider,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
    tester.view.reset();
  });
  await tester.pumpWidget(harness.app(provider));
  await tester.pumpAndSettle();
}

class _Harness {
  _Harness({this.viewInsetsBottom = 0, this.accessibleNavigation});

  final double viewInsetsBottom;
  bool? accessibleNavigation;
  final List<AchievementProvider> _providers = [];
  final _TestLock lock = _TestLock();
  final _TestUpdater updater = _TestUpdater();

  Future<AchievementProvider> createProvider() async {
    final provider = AchievementProvider();
    _providers.add(provider);
    await provider.loadFromStorage();
    await provider.updateContext(_context());
    return provider;
  }

  Widget app(AchievementProvider provider) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AchievementProvider>.value(value: provider),
      ChangeNotifierProvider<AppLockProvider>.value(value: lock),
      ChangeNotifierProvider<AppUpdateService>.value(value: updater),
    ],
    child: MaterialApp(
      home: const Scaffold(body: Center(child: Text('Feedback host fixture'))),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            viewInsets: EdgeInsets.only(bottom: viewInsetsBottom),
            accessibleNavigation:
                accessibleNavigation ?? media.accessibleNavigation,
          ),
          child: AchievementFeedbackHost(child: child!),
        );
      },
    ),
  );

  void dispose() {
    for (final provider in _providers) {
      provider.dispose();
    }
    lock.dispose();
    updater.dispose();
  }
}

class _TestLock extends AppLockProvider {
  bool _locked = false;

  @override
  bool get isLocked => _locked;

  void setLocked(bool value) {
    _locked = value;
    notifyListeners();
  }
}

class _TestUpdater extends AppUpdateService {
  _TestUpdater() : super(repo: 'fixture/duoyi', currentVersion: '1.0.0');

  bool _required = false;

  @override
  bool get mustUpdate => _required;

  void setRequired(bool value) {
    _required = value;
    notifyListeners();
  }

  @override
  Future<void> checkServerPolicyNow() async {}
}
