import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

(String, String, IconData) _scenarioFixture(String scenario) =>
    switch (scenario) {
      'notifications' => (
        NotificationUiCopy.notificationPermissionMissing,
        NotificationUiCopy.notificationPermissionAction,
        Icons.notifications_off_outlined,
      ),
      'exact' => (
        NotificationUiCopy.exactAlarmMissing,
        NotificationUiCopy.exactAlarmAction,
        Icons.alarm_off_outlined,
      ),
      _ => (
        NotificationUiCopy.fullScreenMissing,
        NotificationUiCopy.fullScreenAction,
        Icons.phonelink_lock_outlined,
      ),
    };

double _expectedBaseFontSize(
  WidgetTester tester,
  String role,
  Finder finder,
) {
  switch (role) {
    case 'title':
      return 13.0;
    case 'permission explanation':
      return 11.0;
    default:
      final context = tester.element(finder);
      final textButtonThemeStyle = Theme.of(context).textButtonTheme.style;
      final buttonTextStyle =
          textButtonThemeStyle?.textStyle?.resolve(const {});
      return buttonTextStyle?.fontSize ??
          DefaultTextStyle.of(context).style.fontSize ??
          12.0;
  }
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  final cjkRegex = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]');
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts.where(
        (layout) => ['common', 'large', 'nonlinear'].contains(layout.name),
      )) {
        for (final scenario in ['notifications', 'exact', 'full-screen']) {
          final name = '$brand-${locale.name}-${layout.name}-$scenario';
          testWidgets('complete reminder health action tile $name', (
            tester,
          ) async {
            I18n.setLocale(locale);
            var actionCalls = 0;
            var settingsCalls = 0;
            final auth = AuthProvider(
              client: ApiClient(
                baseUrl: 'https://duoyi.test',
                httpClient: MockClient((_) async => fail('No fixture HTTP')),
              ),
            );
            final expectedScaler = layout.scale < 0
                ? const RouteProbeNonlinearScaler()
                : TextScaler.linear(layout.scale);
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
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Builder(
                        builder: (context) {
                          final (subtitle, action, icon) =
                              _scenarioFixture(scenario);
                          // Same production AppActionTile arguments used by
                          // ReminderHealthHint's three permission branches.
                          return AppActionTile(
                            icon: icon,
                            label: NotificationUiCopy.reminderHealthLabel,
                            color: Colors.red,
                            subtitle: subtitle,
                            onTap: () => settingsCalls++,
                            trailing: TextButton(
                              onPressed: () => actionCalls++,
                              child: Text(action),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
            final probe = RouteRenderProbe(tester, boundary, name);
            final initialError = tester.takeException();
            if (initialError != null) probe.errors.add('$initialError');
            final (subtitle, action, icon) = _scenarioFixture(scenario);
            if (locale == AppLocale.en) {
              expect(
                cjkRegex.hasMatch(NotificationUiCopy.reminderHealthLabel),
                isFalse,
                reason: 'Expected English title must not contain Chinese',
              );
              expect(
                cjkRegex.hasMatch(subtitle),
                isFalse,
                reason: 'Expected English subtitle must not contain Chinese',
              );
              expect(
                cjkRegex.hasMatch(action),
                isFalse,
                reason: 'Expected English action must not contain Chinese',
              );
            }
            for (final (label, role) in [
              (NotificationUiCopy.reminderHealthLabel, 'title'),
              (subtitle, 'permission explanation'),
              (action, 'permission action'),
            ]) {
              await probe.text(
                find.text(label),
                role: role,
                minimumGeometricScale: .999,
              );
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: find.text(label),
                  matching: find.byType(RichText),
                ),
              );
              final renderedText = paragraph.text.toPlainText();
              if (locale == AppLocale.en) {
                if (cjkRegex.hasMatch(renderedText)) {
                  probe.errors.add(
                    '$role rendered text contains Chinese in English case: "$renderedText"',
                  );
                }
                expect(
                  cjkRegex.hasMatch(renderedText),
                  isFalse,
                  reason:
                      '$role rendered text must not contain Chinese in English case: "$renderedText"',
                );
              }
              final expectedBase = _expectedBaseFontSize(
                tester,
                role,
                find.text(label),
              );
              final actualBase = paragraph.text.style?.fontSize;
              if (actualBase == null ||
                  (actualBase - expectedBase).abs() > 0.001) {
                probe.errors.add(
                  '$role base font size $actualBase does not match expected $expectedBase',
                );
              }
              final expectedScaled = expectedScaler.scale(expectedBase);
              final actualScaled = paragraph.textScaler.scale(actualBase ?? 0.0);
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
              final fullWidth = paragraph.size.width;
              for (final word in RegExp(r'[A-Za-z]+').allMatches(label)) {
                final boxes = paragraph.getBoxesForSelection(
                  TextSelection(
                    baseOffset: word.start,
                    extentOffset: word.end,
                  ),
                );
                final painter = TextPainter(
                  text: TextSpan(
                    text: word[0],
                    style: paragraph.text.style,
                  ),
                  textDirection: TextDirection.ltr,
                  textScaler: paragraph.textScaler,
                )..layout();
                final fits = painter.width <= fullWidth + .1;
                painter.dispose();
                if (fits && boxes.map((box) => box.top).toSet().length > 1) {
                  probe.errors.add('$role splits fitting word ${word[0]}');
                }
              }
            }
            await probe.capture('initial');
            final actionButton = find.byType(TextButton);
            await tester.ensureVisible(actionButton);
            await tester.pumpAndSettle();
            final rect = tester.getRect(actionButton);
            probe.rows.add({
              'role': 'permission action target',
              'width': rect.width,
              'height': rect.height,
            });
            if (rect.width < 44 || rect.height < 44) {
              probe.errors.add('permission action target below44dp');
            }
            await tester.tap(actionButton);
            await tester.pumpAndSettle();
            expect(actionCalls, 1);
            expect(settingsCalls, 0);
            await tester.tap(find.byIcon(icon));
            await tester.pumpAndSettle();
            expect(settingsCalls, 1);
            expect(actionCalls, 1);
            // A collapsed paragraph can yield 0/0 in the shared geometric
            // probe. Preserve it as an explicit failure and serializable null.
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
}
