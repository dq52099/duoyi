import 'package:duoyi/core/ai_schedule_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/ai_schedule_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

const _input = 'Tomorrow review accessibility / 明天检查界面';
const _title = 'Review accessibility with the product team / 检查界面';
const _notes = 'Keep the original wording and review every reminder / 原始备注';
const _subtask = 'Prepare screenshots and check the calendar / 准备截图';

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'ai-schedule-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          final ai = _SyntheticAi();
          addTearDown(ai.dispose);
          final auth = AuthProvider(
            initialState: const AuthState(
              userId: 'synthetic-schedule',
              username: 'Synthetic account',
              token: 'synthetic-token',
            ),
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient((_) async {
                fail('The visual fixture must not issue an HTTP request');
              }),
            ),
          );
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: ChangeNotifierProvider<AiService>.value(
              value: ai,
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BrandRouteSurface(
                            child: AiScheduleScreen(),
                          ),
                        ),
                      ),
                      child: const Text('Open synthetic schedule'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open synthetic schedule'));
          await tester.pumpAndSettle();
          final screen = find.byType(AiScheduleScreen);
          final retained = tester.state(screen);
          final probe = RouteRenderProbe(tester, boundary, name);

          Future<void> measure(String stage, Finder region) async {
            final texts = tester
                .widgetList<Text>(
                  find.descendant(of: region, matching: find.byType(Text)),
                )
                .where((text) => text.data?.isNotEmpty ?? false)
                .toList();
            for (var i = 0; i < texts.length; i++) {
              final widget = texts[i];
              final finder = find.byWidget(widget);
              await probe.text(
                finder,
                role: '$stage text $i',
                minimumGeometricScale: .999,
              );
              final cards = find.ancestor(
                of: finder,
                matching: find.byType(AppSurfaceCard),
              );
              if (cards.evaluate().isNotEmpty) {
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(of: finder, matching: find.byType(RichText)),
                );
                final available = tester.getSize(cards.first).width - 32;
                final broken = <String>[];
                for (final word in RegExp(
                  r'[A-Za-z]+',
                ).allMatches(widget.data!)) {
                  final painter = TextPainter(
                    text: TextSpan(
                      text: word.group(0),
                      style: paragraph.text.style,
                    ),
                    textDirection: paragraph.textDirection,
                    textScaler: paragraph.textScaler,
                  )..layout();
                  final fits = painter.width <= available + .1;
                  painter.dispose();
                  final boxes = paragraph.getBoxesForSelection(
                    TextSelection(
                      baseOffset: word.start,
                      extentOffset: word.end,
                    ),
                  );
                  if (fits &&
                      boxes
                              .map((b) => b.top.toStringAsFixed(2))
                              .toSet()
                              .length >
                          1) {
                    broken.add(word.group(0)!);
                  }
                }
                probe.rows.add({
                  'role': '$stage word layout $i',
                  'text': widget.data,
                  'fullCardContentWidth': available,
                  'fittingWordsSplit': broken,
                });
                if (broken.isNotEmpty) {
                  probe.errors.add('$stage: fitting words split: $broken');
                }
              }
            }
            Object? frameworkError;
            while ((frameworkError = tester.takeException()) != null) {
              probe.errors.add('$stage: $frameworkError');
            }
          }

          final listScroll = find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first;
          Future<void> scrollTo(String text) async {
            await tester.scrollUntilVisible(
              find.text(text),
              160,
              scrollable: listScroll,
              maxScrolls: 100,
            );
            await probe.reveal(find.text(text));
          }

          Future<void> measureDraft(String stage) async {
            await scrollTo(AiScheduleUiCopy.warningTitle(ai.draft));
            await measure(
              '$stage warning',
              find.ancestor(
                of: find.text(AiScheduleUiCopy.warningTitle(ai.draft)),
                matching: find.byType(AppInfoBanner),
              ),
            );
            await scrollTo(AiScheduleUiCopy.draftTitle);
            await measure(
              '$stage summary',
              find.ancestor(
                of: find.text(AiScheduleUiCopy.draftTitle),
                matching: find.byType(AppInfoBanner),
              ),
            );
            await scrollTo(AiScheduleUiCopy.confirmCardTitle);
            await probe.capture('$stage-title');
            await measure(
              stage,
              find.ancestor(
                of: find.text(AiScheduleUiCopy.confirmCardTitle),
                matching: find.byType(AppSurfaceCard),
              ),
            );
            expect(find.text(_title), findsOneWidget);
            expect(find.text(_notes), findsOneWidget);
            expect(find.text(_subtask), findsOneWidget);
            await probe.reveal(find.text(_notes));
            await probe.capture('$stage-notes');
            await scrollTo(AiScheduleUiCopy.create);
            await probe.text(
              find.text(AiScheduleUiCopy.create),
              role: '$stage create action',
              minimumGeometricScale: .999,
            );
            await probe.capture('$stage-action');
          }

          await probe.capture('form');
          await probe.text(
            find.text(AiScheduleUiCopy.screenTitle),
            role: 'route title',
            minimumGeometricScale: .999,
          );
          await scrollTo(AiScheduleUiCopy.aiDisabledTitle);
          await measure(
            'offline banner',
            find.ancestor(
              of: find.text(AiScheduleUiCopy.aiDisabledTitle),
              matching: find.byType(AppInfoBanner),
            ),
          );
          await scrollTo(AiScheduleUiCopy.inputTitle);
          await measure(
            'form',
            find.ancestor(
              of: find.text(AiScheduleUiCopy.inputTitle),
              matching: find.byType(AppSurfaceCard),
            ),
          );
          final field = find.byType(TextField);
          await tester.enterText(field, _input);
          final controller = tester.widget<TextField>(field).controller!;
          controller.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 9,
          );
          await scrollTo(AiScheduleUiCopy.recognize);
          final button = find.ancestor(
            of: find.byIcon(Icons.manage_search_outlined),
            matching: find.byType(FilledButton),
          );
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(ai.recognitions, 1);
          await measureDraft('draft');
          final scroll = tester.state<ScrollableState>(listScroll);
          // Use an attainable offset in both languages. A bottom offset can
          // legitimately clamp when translated content becomes shorter.
          scroll.position.jumpTo(32);
          await tester.pumpAndSettle();
          final beforeOffset = scroll.position.pixels;
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          final sameState = identical(tester.state(screen), retained);
          if (!sameState) {
            probe.errors.add('Locale change remounted the actual pushed route');
          }
          final afterScroll = tester.state<ScrollableState>(listScroll);
          if (!identical(afterScroll, scroll) ||
              (afterScroll.position.pixels - beforeOffset).abs() > .1) {
            probe.errors.add('Scroll state or offset lost on locale change');
          }
          expect(
            ai.recognitions,
            1,
            reason: 'Changing locale must not call recognition again',
          );
          afterScroll.position.jumpTo(0);
          await tester.pumpAndSettle();
          await scrollTo(AiScheduleUiCopy.inputTitle);
          final currentController = tester.widget<TextField>(field).controller!;
          if (!identical(currentController, controller)) {
            probe.errors.add('Input controller lost on locale change');
          }
          if (currentController.text != _input) {
            probe.errors.add('Input lost on locale change');
          }
          if (currentController.selection !=
              const TextSelection(baseOffset: 2, extentOffset: 9)) {
            probe.errors.add('Input selection lost on locale change');
          }
          if (sameState) {
            await measureDraft('live-locale-draft');
          } else {
            probe.errors.add('Recognized draft lost on locale change');
          }
          await probe.finish();
        });
      }
    }
  }
}

class _SyntheticAi extends AiService {
  int recognitions = 0;
  @override
  bool get enabled => false;
  @override
  Future<AiScheduleDraft> createScheduleDraft(
    String input, {
    DateTime? now,
  }) async {
    recognitions++;
    return draft;
  }

  AiScheduleDraft get draft => AiScheduleDraft(
    type: AiScheduleType.calendar,
    title: _title,
    notes: _notes,
    startAt: DateTime(2026, 10, 22, 15),
    endAt: DateTime(2026, 10, 22, 16),
    subtasks: const [_subtask],
    source: AiScheduleSource.localParser,
    warningKind: AiScheduleWarningKind.unavailable,
  );
}
