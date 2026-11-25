import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/widgets/widget_quick_todo_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'widget-quick-entry-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final submitted = <String>[];
          final boundary = await mountPriorityFixture(
            tester,
            auth: AuthProvider(),
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => WidgetQuickTodoDialog(
                      canSubmit: () => true,
                      onSubmit: (text) async {
                        submitted.add(text);
                        return false;
                      },
                    ),
                  ),
                  child: const Text('Open synthetic widget quick entry'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open synthetic widget quick entry'));
          await tester.pumpAndSettle();
          final element = tester.element(find.byType(WidgetQuickTodoDialog));
          final probe = RouteRenderProbe(tester, boundary, name);
          Future<void> controls(String stage, {bool empty = false}) async {
            final english = I18n.current == AppLocale.en;
            for (final text in [
              english ? 'Quick task' : '快速待办',
              I18n.tr('action.cancel'),
              I18n.tr('action.add'),
              if (empty)
                english
                    ? 'Describe your task and its date'
                    : '一句话描述（如：明天下午3点开会）',
            ]) {
              await probe.text(
                find.text(text),
                role: '$stage $text',
                minimumGeometricScale: .999,
              );
            }
            if (!empty) {
              await probe.text(
                find.textContaining(english ? 'Detected:' : '识别到:'),
                role: '$stage detected date',
                minimumGeometricScale: .999,
              );
            }
            await probe.capture(stage);
          }

          await controls('empty', empty: true);
          const draft = '明天下午3点开会 / literal widget draft';
          await tester.enterText(find.byType(TextField), draft);
          await tester.pumpAndSettle();
          final field = tester.widget<TextField>(find.byType(TextField));
          field.controller!.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 6,
          );
          await controls('detected');
          await tester.tap(find.text(I18n.tr('action.add')));
          await tester.pumpAndSettle();
          expect(submitted, [draft]);
          expect(
            tester.element(find.byType(WidgetQuickTodoDialog)),
            same(element),
          );
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          final live = tester.widget<TextField>(find.byType(TextField));
          expect(
            tester.element(find.byType(WidgetQuickTodoDialog)),
            same(element),
          );
          expect(live.controller, same(field.controller));
          expect(live.focusNode, same(field.focusNode));
          expect(live.controller!.text, draft);
          expect(
            live.controller!.selection,
            const TextSelection(baseOffset: 2, extentOffset: 6),
          );
          await controls('live');
          await tester.tap(find.text(I18n.tr('action.cancel')));
          await tester.pumpAndSettle();
          expect(find.byType(WidgetQuickTodoDialog), findsNothing);
          expect(submitted, [draft]);
          await probe.finish();
        });
      }
    }
  }
}
