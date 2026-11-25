import 'dart:math' as math;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/notification_health_card.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

String _syntheticErrorText(AppLocale locale) => switch (locale) {
  AppLocale.en =>
    'Unable to check health status. Please check reminder settings and tap to retry.',
  AppLocale.zh =>
    '无法读取系统提醒健康状态，请检查通知设置并点击重试。',
};

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts.where(
        (layout) => ['common', 'large', 'nonlinear'].contains(layout.name),
      )) {
        final name = '$brand-${locale.name}-${layout.name}-health-error';
        testWidgets('notification health card error priority layout $name', (
          tester,
        ) async {
          var refreshCalls = 0;
          var settingsCalls = 0;
          var channelCalls = 0;
          var testCalls = 0;
          var strongTestCalls = 0;
          var clearCalls = 0;
          var notificationPermissionCalls = 0;
          var exactAlarmPermissionCalls = 0;
          var fullScreenPermissionCalls = 0;

          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient((_) async => fail('No fixture HTTP')),
            ),
          );

          final expectedScaler = layout.scale < 0
              ? const RouteProbeNonlinearScaler()
              : TextScaler.linear(layout.scale);

          final errorText = _syntheticErrorText(locale);

          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: BrandRouteSurface(
              remountOnLocaleChange: false,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: SingleChildScrollView(
                  child: NotificationHealthCard(
                    report: null,
                    errorText: errorText,
                    onRefresh: () => refreshCalls++,
                    onOpenSystemSettings: () => settingsCalls++,
                    onOpenNotificationChannelSettings: (_) => channelCalls++,
                    onSendTest: () => testCalls++,
                    onSendStrongTest: () => strongTestCalls++,
                    onClearPending: () => clearCalls++,
                    onRequestNotificationPermission: () =>
                        notificationPermissionCalls++,
                    onRequestExactAlarmPermission: () =>
                        exactAlarmPermissionCalls++,
                    onRequestFullScreenIntentPermission: () =>
                        fullScreenPermissionCalls++,
                  ),
                ),
              ),
            ),
          );

          final probe = RouteRenderProbe(tester, boundary, name);
          final initialError = tester.takeException();
          if (initialError != null) probe.errors.add('$initialError');

          final cardFinder = find.byType(NotificationHealthCard);
          expect(cardFinder, findsOneWidget);

          final actionTileFinder = find.descendant(
            of: cardFinder,
            matching: find.byType(AppActionTile),
          );
          expect(actionTileFinder, findsOneWidget);

          final titleFinder = find.descendant(
            of: actionTileFinder,
            matching: find.text(NotificationUiCopy.healthCheckFailed),
          );
          expect(titleFinder, findsOneWidget);

          final errorFinder = find.descendant(
            of: actionTileFinder,
            matching: find.text(errorText),
          );
          expect(errorFinder, findsOneWidget);

          // Verify text scaling retention, contrast, and completeness.
          await probe.text(
            titleFinder,
            role: 'title',
            minimumGeometricScale: .999,
          );
          await probe.text(
            errorFinder,
            role: 'error explanation',
            minimumGeometricScale: .999,
          );

          // Blindspot 1: Verify base font size (13 for title, 11 for error explanation)
          // and ensure the RenderParagraph textScaler matches the root input layout scaler.
          for (final (finder, role, expectedBase) in [
            (titleFinder, 'title', 13.0),
            (errorFinder, 'error explanation', 11.0),
          ]) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: finder, matching: find.byType(RichText)),
            );
            final actualBase = paragraph.text.style?.fontSize;
            if (actualBase == null ||
                (actualBase - expectedBase).abs() > 0.001) {
              probe.errors.add(
                '$role base font size $actualBase does not match expected $expectedBase',
              );
            }
            final expectedScaled = expectedScaler.scale(expectedBase);
            final actualScaled =
                paragraph.textScaler.scale(actualBase ?? 0.0);
            if ((actualScaled - expectedScaled).abs() > 0.001) {
              probe.errors.add(
                '$role scaled font size $actualScaled does not match expected $expectedScaled',
              );
            }
            expect(
              actualBase,
              expectedBase,
              reason:
                  '$role base font size must not be lowered from $expectedBase',
            );
            expect(
              actualScaled,
              closeTo(expectedScaled, 0.001),
              reason:
                  '$role scaled font size must equal layout scale applied to $expectedBase',
            );
          }

          // Default chevron icon must exist on the shared AppActionTile error row.
          final chevronFinder = find.descendant(
            of: actionTileFinder,
            matching: find.byIcon(Icons.chevron_right),
          );
          expect(chevronFinder, findsOneWidget);

          // Blindspot 2: Ensure the entire AppActionTile is in view before screenshot capture,
          // so large/nonlinear layouts do not leave the title scrolled out of the top edge.
          await tester.ensureVisible(actionTileFinder);
          await tester.pumpAndSettle();
          final tileRect = tester.getRect(actionTileFinder);
          if (tileRect.top < 0) {
            final scrollable =
                Scrollable.maybeOf(tester.element(actionTileFinder));
            if (scrollable != null) {
              scrollable.position.jumpTo(
                math.max(0.0, scrollable.position.pixels + tileRect.top),
              );
              await tester.pumpAndSettle();
            }
          }

          // Capture verification screenshot under DUOYI_SECONDARY_SCREENSHOTS.
          await probe.capture('initial');

          // Tapping the error row icon must trigger onRefresh exactly once.
          final errorIconFinder = find.descendant(
            of: actionTileFinder,
            matching: find.byIcon(Icons.error_outline),
          );
          expect(errorIconFinder, findsOneWidget);

          expect(refreshCalls, 0);
          await tester.ensureVisible(errorIconFinder);
          await tester.pumpAndSettle();
          await tester.tap(errorIconFinder);
          await tester.pumpAndSettle();

          expect(refreshCalls, 1);
          expect(settingsCalls, 0);
          expect(channelCalls, 0);
          expect(testCalls, 0);
          expect(strongTestCalls, 0);
          expect(clearCalls, 0);
          expect(notificationPermissionCalls, 0);
          expect(exactAlarmPermissionCalls, 0);
          expect(fullScreenPermissionCalls, 0);

          // Inputs and card widgets remain stable and unchanged after observation and tap.
          expect(cardFinder, findsOneWidget);
          expect(actionTileFinder, findsOneWidget);
          expect(titleFinder, findsOneWidget);
          expect(errorFinder, findsOneWidget);
          expect(chevronFinder, findsOneWidget);
          expect(errorIconFinder, findsOneWidget);

          for (final row in probe.rows) {
            for (final entry in row.entries.toList()) {
              final value = entry.value;
              if (value is double && !value.isFinite) {
                probe.errors.add('${row['role']} has no drawable area');
                row[entry.key] = null;
              }
            }
          }

          await probe.finish();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
