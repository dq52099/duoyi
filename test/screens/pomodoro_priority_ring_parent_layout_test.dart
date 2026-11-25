import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/main_ui_copy.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/pomodoro_timer_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/priority_theme_fixture.dart';

class _PausedPomodoro extends PomodoroProvider {
  @override
  PomodoroState get state => const PomodoroState(
    remainingSeconds: 750,
    totalSeconds: 1500,
    isRunning: false,
    type: PomodoroType.focus,
    completedSessions: 0,
  );
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final size in [const Size(390, 844), const Size(568, 320)]) {
        testWidgets('ring fits real timer parent $brand ${locale.name} $size', (
          tester,
        ) async {
          final provider = _PausedPomodoro();
          final originalState = provider.state;
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient(
                (_) async => fail('No fixture HTTP allowed'),
              ),
            ),
          );
          await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: size,
            scale: 2,
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<PomodoroProvider>(
                  create: (_) => provider,
                ),
                ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
                ChangeNotifierProvider(
                  create: (_) => CustomFocusSoundProvider(),
                ),
              ],
              child: const PomodoroScreen(),
            ),
          );
          final ring = tester.widget<PomodoroTimerRing>(
            find.byType(PomodoroTimerRing),
          );
          expect(ring.progress, 0.5);
          expect(ring.timeText, '12:30');
          if (size.height == 844) {
            expect(ring.size, 172);
            expect(
              find.text(MainUiCopy.pomodoroRemainingPercent(50)),
              findsOneWidget,
            );
          } else {
            expect(ring.size, 126);
          }
          expect(tester.takeException(), isNull);
          final mainButton = find.widgetWithIcon(
            FloatingActionButton,
            Icons.play_arrow,
          );
          await tester.ensureVisible(mainButton);
          await tester.pumpAndSettle();
          expect(mainButton.hitTestable(), findsOneWidget);
          final rect = tester.getRect(mainButton);
          expect(rect.width, greaterThanOrEqualTo(44));
          expect(rect.height, greaterThanOrEqualTo(44));
          expect(provider.state, same(originalState));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
