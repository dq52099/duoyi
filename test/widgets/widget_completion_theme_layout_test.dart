import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_ui_copy.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/todo_completion_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/priority_theme_fixture.dart';
import '../support/rendered_control_contrast.dart';
import '../support/secondary_route_render_probe.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'widget-completion-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final todo = TodoItem(
            id: name,
            title: 'Plan the next release',
            date: DateTime(2026, 10, 23, 9),
            timeTargetSeconds: 1800,
          );
          final todos = _CompletionTodos(todo);
          final audit = _CompletionAudit();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            todos.dispose();
            audit.dispose();
          });
          final boundary = await mountPriorityFixture(
            tester,
            auth: AuthProvider(),
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<TodoProvider>.value(value: todos),
                ChangeNotifierProvider<TimeAuditProvider>.value(value: audit),
              ],
              child: BrandRouteSurface(
                remountOnLocaleChange: false,
                child: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () =>
                          completeTodoWithOptionalTimeRecord(context, todo),
                      child: const Text('Launch completion'),
                    ),
                  ),
                ),
              ),
            ),
          );
          final probe = RouteRenderProbe(tester, boundary, name);
          await withControlEvidenceShadows(() async {
            await tester.tap(find.text('Launch completion'));
            await tester.pumpAndSettle();
            Future<void> checkText(String copy, String role) async {
              await probe.text(
                find.text(copy).last,
                role: role,
                minimumGeometricScale: .999,
              );
            }

            Future<void> checkAction(String copy) async {
              final control = find
                  .ancestor(
                    of: find.text(copy),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is TextButton || widget is FilledButton,
                    ),
                  )
                  .first;
              await probe.reveal(control);
              await probe.text(
                find.text(copy),
                role: 'action',
                minimumGeometricScale: .999,
              );
              expectControlTouchTarget(tester, control);
            }

            await checkText(TodoUiCopy.confirmCompleteTitle, 'confirm title');
            await checkText(
              TodoUiCopy.confirmCompleteContent(todo.title),
              'confirm content',
            );
            await checkAction(TodoUiCopy.actionCancel);
            await checkAction(TodoUiCopy.actionContinue);
            await probe.capture('confirmation');
            await tester.tap(find.text(TodoUiCopy.actionContinue));
            await tester.pumpAndSettle();
            final input = find.byType(TextField);
            final controller = tester.widget<TextField>(input).controller!;
            final route = ModalRoute.of(tester.element(input));
            expect(controller.text, '30');
            Future<void> checkRecord(String stage) async {
              await checkText(TodoUiCopy.recordDurationTitle, '$stage title');
              await checkText(
                TodoUiCopy.recordDurationContent(todo.title),
                '$stage content',
              );
              // InputDecorator intentionally paints floating labels at 75% scale.
              await probe.text(
                find.text(TodoUiCopy.durationLabel).last,
                role: '$stage field label',
                minimumGeometricScale: .749,
              );
              final labelRow = probe.rows.last;
              expect(labelRow['geometricScale'] as double, closeTo(.75, .001));
              final paintedFont =
                  (labelRow['renderedFontSize'] as double) * .75;
              final required = paintedFont >= 24 ? 3.0 : 4.5;
              labelRow['paintedFontSizeAfterMaterialTransform'] = paintedFont;
              labelRow['paintedRequiredContrast'] = required;
              if ((labelRow['ratio'] as double) < required) {
                probe.errors.add(
                  '$stage painted floating label contrast below $required',
                );
              }
              await checkText(
                TodoUiCopy.durationMinutesSuffix,
                '$stage suffix',
              );
              await checkAction(TodoUiCopy.actionSkip);
              await checkAction(TodoUiCopy.actionRecord);
              await probe.capture(stage);
            }

            await checkRecord('record');
            await probe.reveal(input);
            await tester.enterText(input, '');
            tester.testTextInput.hide();
            await tester.pumpAndSettle();
            await checkText(TodoUiCopy.durationHint, 'empty input guidance');
            await probe.capture('empty-input');
            await tester.enterText(input, '47');
            tester.testTextInput.hide();
            await tester.pumpAndSettle();
            I18n.setLocale(
              locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
            );
            await tester.pumpAndSettle();
            expect(
              tester.widget<TextField>(input).controller,
              same(controller),
            );
            expect(ModalRoute.of(tester.element(input)), same(route));
            expect(controller.text, '47');
            expect(todos.completedIds, isEmpty);
            expect(audit.entriesAdded, isEmpty);
            await checkRecord('live-locale');
            await probe.reveal(find.text(TodoUiCopy.actionRecord));
            await tester.tap(find.text(TodoUiCopy.actionRecord));
            await tester.pumpAndSettle();
            expect(todos.completedIds, [todo.id]);
            expect(audit.entriesAdded, hasLength(1));
            expect(audit.entriesAdded.single.durationSeconds, 47 * 60);
            expect(audit.entriesAdded.single.sourceId, todo.id);
            expect(audit.entriesAdded.single.title, todo.title);
            expect(
              audit.entriesAdded.single.note,
              TodoUiCopy.manualDurationNote(47),
            );
            await probe.finish();
          });
        });
      }
    }
  }
}

class _CompletionTodos extends TodoProvider {
  _CompletionTodos(this.todo);
  final TodoItem todo;
  final completedIds = <String>[];
  @override
  List<TodoItem> get todos => [todo];
  @override
  Future<int> completeTodos(
    Iterable<String> ids, {
    bool recordCompletionTime = true,
  }) async {
    expect(recordCompletionTime, isFalse);
    completedIds.addAll(ids);
    return 1;
  }
}

class _CompletionAudit extends TimeAuditProvider {
  final entriesAdded = <TimeEntry>[];
  @override
  Future<void> add(TimeEntry entry) async {
    entriesAdded.add(entry);
  }
}
