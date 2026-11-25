// Production pushed routes and themes; feedback traffic is entirely synthetic.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/feedback_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/feedback_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

const _statuses = ['open', 'in_progress', 'resolved', 'closed'];
final _items = [
  for (var i = 0; i < _statuses.length; i++)
    {
      'id': i + 1,
      'category': 'bug',
      'status': _statuses[i],
      'content': 'Synthetic report ${i + 1} 原文保留。',
      'admin_reply': 'Synthetic reply ${i + 1} 回复原文。',
      'created_at': '2026-10-21T0${i + 1}:30:00Z',
      'updated_at': '2026-10-21T0${i + 1}:45:00Z',
    },
];

class _FeedbackProbe extends RouteRenderProbe {
  _FeedbackProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    // Detail has both an inner field scroll and the dialog's outer viewport.
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
  }
}

Future<void> _checkFieldGeometry(
  WidgetTester tester,
  RouteRenderProbe probe,
  Finder label,
  String role,
) async {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
  final boundary =
      probe.boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  final transform = paragraph.getTransformTo(boundary);
  final rect = MatrixUtils.transformRect(
    transform,
    Offset.zero & paragraph.size,
  );
  final scale = rect.height / paragraph.size.height;
  if (scale < .749) probe.errors.add('$role adds label shrink: $scale');
  final background = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final x = (rect.left - 3).floor(), y = rect.center.dy.floor();
      expect(x, inInclusiveRange(0, image.width - 1));
      expect(y, inInclusiveRange(0, image.height - 1));
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        255,
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  });
  final style = paragraph.text.style!;
  final foreground = style.foreground?.color ?? style.color!;
  final a = Color.alphaBlend(foreground, background!).computeLuminance();
  final b = background.computeLuminance();
  final ratio = (math.max(a, b) + .05) / (math.min(a, b) + .05);
  final paintedFontSize = paragraph.textScaler.scale(style.fontSize!) * scale;
  final required = paintedFontSize >= 24 ? 3.0 : 4.5;
  probe.rows.add({
    'role': '$role painted label contrast',
    'ratio': ratio,
    'required': required,
    'paintedFontSize': paintedFontSize,
    'foregroundARGB': foreground.toARGB32(),
    'backgroundARGB': background.toARGB32(),
  });
  if (ratio < required) {
    probe.errors.add('$role contrast $ratio below $required');
  }
  final field = find.ancestor(of: label, matching: find.byType(TextField));
  final editable = tester
      .state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      )
      .renderEditable;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  );
  final lines = boxes.map((box) => box.top).toSet().length;
  var overlaps = false;
  if (lines > 1 && editable.plainText.isNotEmpty) {
    final viewport = MatrixUtils.transformRect(
      editable.getTransformTo(boundary),
      Offset.zero & editable.size,
    );
    final values = editable.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: editable.plainText.length),
    );
    for (final box in boxes) {
      final labelRect = MatrixUtils.transformRect(transform, box.toRect());
      for (final value in values) {
        final valueRect = MatrixUtils.transformRect(
          editable.getTransformTo(boundary),
          value.toRect(),
        ).intersect(viewport);
        final intersection = labelRect.intersect(valueRect);
        if (intersection.width > .5 && intersection.height > .5) {
          overlaps = true;
        }
      }
    }
  }
  probe.rows.add({
    'role': role,
    'geometricScale': scale,
    'labelLines': lines,
    'selectionBoxesOverlap': overlaps,
    'enforcedForWrapping': lines > 1 && editable.plainText.isNotEmpty,
  });
  if (overlaps) probe.errors.add('$role wrapped label overlaps draft');
}

Future<void> _selectable(
  WidgetTester tester,
  RouteRenderProbe probe,
  String value,
  String role,
) async {
  final finder = find.byWidgetPredicate(
    (widget) => widget is SelectableText && widget.data == value,
  );
  await probe.reveal(finder);
  final editable = tester
      .state<EditableTextState>(
        find.descendant(of: finder, matching: find.byType(EditableText)),
      )
      .renderEditable;
  expect(editable.text!.toPlainText(), value);
  final render =
      probe.boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  final rect = MatrixUtils.transformRect(
    editable.getTransformTo(render),
    Offset.zero & editable.size,
  );
  final style = editable.text!.style!;
  final painter = TextPainter(
    text: editable.text,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(tester.element(finder)),
  )..layout(maxWidth: editable.size.width);
  final complete = painter.height <= editable.size.height + .1;
  painter.dispose();
  if (!complete) probe.errors.add('$role selectable content incomplete');
  final background = await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final x = (rect.left - 3).floor(), y = rect.center.dy.floor();
      expect(x, inInclusiveRange(0, image.width - 1));
      expect(y, inInclusiveRange(0, image.height - 1));
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        255,
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  });
  final fg = style.foreground?.color ?? style.color!;
  final a = Color.alphaBlend(fg, background!).computeLuminance();
  final b = background.computeLuminance();
  final ratio = (math.max(a, b) + .05) / (math.min(a, b) + .05);
  final size = MediaQuery.textScalerOf(
    tester.element(finder),
  ).scale(style.fontSize!);
  final required = size >= 24 ? 3.0 : 4.5;
  probe.rows.add({
    'role': role,
    'text': value,
    'ratio': ratio,
    'required': required,
    'incomplete': !complete,
    'foregroundARGB': fg.toARGB32(),
    'backgroundARGB': background.toARGB32(),
  });
  if (ratio < required) {
    probe.errors.add('$role contrast $ratio below $required');
  }
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        final name = 'feedback-$brand-${locale.name}-${layout.name}';
        testWidgets(name, (tester) async {
          var gets = 0;
          final posts = <Map<String, dynamic>>[];
          final transport = MockClient((request) async {
            if (request.method == 'GET') {
              expect(request.url.path, '/api/feedback/me');
              expect(request.url.queryParameters['page_size'], '10');
              gets++;
              return http.Response(
                jsonEncode({
                  'items': _items,
                  'total': 4,
                  'page': 1,
                  'total_pages': 1,
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            expect(request.method, 'POST');
            expect(request.url.path, '/api/feedback');
            posts.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode(
                posts.length == 1
                    ? {'detail': 'PRIVATE synthetic diagnostic'}
                    : {'id': 5},
              ),
              posts.length == 1 ? 503 : 200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          });
          addTearDown(transport.close);
          final auth = AuthProvider(
            initialState: const AuthState(
              userId: 'synthetic-feedback',
              username: 'Synthetic',
              token: 'synthetic-feedback-token',
            ),
            client: ApiClient(
              baseUrl: 'https://synthetic.example.test',
              httpClient: transport,
            ),
          );
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const ValueKey('open_feedback_theme'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BrandRouteSurface(
                        child: FeedbackScreen(initialCategory: 'wish'),
                      ),
                    ),
                  ),
                  child: const Text('Open synthetic feedback'),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const ValueKey('open_feedback_theme')));
          await tester.pumpAndSettle();
          expect(gets, 1);
          final history = tester.state(find.byType(FeedbackScreen));
          final probe = _FeedbackProbe(tester, boundary, name);
          Future<void> text(
            String copy,
            String role, {
            bool contrast = true,
          }) async {
            final finder = find.text(copy);
            if (finder.evaluate().isEmpty) {
              final scroll = find
                  .descendant(
                    of: find.byType(ListView).last,
                    matching: find.byType(Scrollable),
                  )
                  .first;
              await tester.scrollUntilVisible(
                finder,
                140,
                scrollable: scroll,
                maxScrolls: 40,
              );
            }
            await probe.text(finder.last, role: role, contrast: contrast);
          }

          Future<void> records(String stage) async {
            final scroll = find
                .descendant(
                  of: find.byType(RefreshIndicator),
                  matching: find.byType(Scrollable),
                )
                .first;
            tester.state<ScrollableState>(scroll).position.jumpTo(0);
            await tester.pumpAndSettle();
            await text(
              FeedbackUiCopy.historySummary(
                total: 4,
                page: 1,
                totalPages: 1,
                loggedIn: true,
              ),
              '$stage history summary',
            );
            await probe.capture('$stage-hero');
            for (var i = 0; i < _items.length; i++) {
              await text(
                FeedbackUiCopy.statusLabel(_statuses[i]),
                '$stage ${_statuses[i]} status',
              );
              await text(_items[i]['created_at'] as String, '$stage timestamp');
              await text(
                _items[i]['content'] as String,
                '$stage original content',
              );
              await text(
                _items[i]['admin_reply'] as String,
                '$stage original reply',
              );
              final replyColumn = find
                  .ancestor(
                    of: find.text(_items[i]['admin_reply'] as String),
                    matching: find.byType(Column),
                  )
                  .first;
              await probe.text(
                find.descendant(
                  of: replyColumn,
                  matching: find.text(FeedbackUiCopy.detailReply()),
                ),
                role: '$stage record reply heading',
              );
              await probe.capture('$stage-record-$i');
            }
            final position = tester.state<ScrollableState>(scroll).position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
            final pagination = tester.getRect(
              find.byKey(const ValueKey('feedback_record_pagination')),
            );
            final fab = tester.getRect(
              find.byKey(const ValueKey('feedback_submit_fab')),
            );
            final viewport = tester.getRect(find.byType(RefreshIndicator));
            final clear =
                !pagination.overlaps(fab) &&
                pagination.top >= viewport.top &&
                pagination.bottom <= viewport.bottom;
            probe.rows.add({
              'role': '$stage pagination at scroll end',
              'fullyVisibleWithoutFabOverlap': clear,
              'gapAboveFab': fab.top - pagination.bottom,
            });
            if (!clear) {
              probe.errors.add('$stage pagination obscured at scroll end');
            }
            await probe.capture('$stage-pagination');
          }

          await records('initial');
          final historyScroll = find
              .descendant(
                of: find.byType(RefreshIndicator),
                matching: find.byType(Scrollable),
              )
              .first;
          tester.state<ScrollableState>(historyScroll).position.jumpTo(0);
          await tester.pumpAndSettle();
          final firstContent = find.text(_items.first['content'] as String);
          await tester.scrollUntilVisible(
            firstContent,
            120,
            scrollable: historyScroll,
            maxScrolls: 30,
          );
          await probe.reveal(firstContent);
          await tester.tap(firstContent);
          await tester.pumpAndSettle();
          final dialog = tester.element(find.byType(AppDialog));
          Future<void> detail(String stage) async {
            for (final copy in [
              FeedbackUiCopy.detailSubmittedAt(),
              FeedbackUiCopy.detailUpdatedAt(),
              FeedbackUiCopy.detailContent(),
              FeedbackUiCopy.detailReply(),
            ]) {
              final finder = find.descendant(
                of: find.byType(AppDialog),
                matching: find.text(copy),
              );
              await probe.text(finder, role: '$stage detail field label');
            }
            for (final key in [
              'created_at',
              'updated_at',
              'content',
              'admin_reply',
            ]) {
              await _selectable(
                tester,
                probe,
                _items.first[key] as String,
                '$stage detail $key',
              );
            }
            await probe.capture('$stage-detail');
          }

          await detail('initial');
          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(AppDialog)), same(dialog));
          expect(tester.state(find.byType(FeedbackScreen)), same(history));
          expect(gets, 1);
          await detail('live');
          await tester.tap(find.text(FeedbackUiCopy.actionClose()));
          await tester.pumpAndSettle();
          await records('live');
          final fab = find.byKey(const ValueKey('feedback_submit_fab'));
          await tester.tap(fab);
          await tester.pumpAndSettle();
          final submitState = tester.state(find.byType(FeedbackSubmitScreen));
          Future<void> form(String stage) async {
            await text(
              FeedbackUiCopy.submitHeaderSubtitle(),
              '$stage submit guidance',
            );
            await text(
              FeedbackUiCopy.categoryMenuLabel(),
              '$stage category label',
            );
            await text(
              FeedbackUiCopy.categoryLabel('wish'),
              '$stage selected category',
            );
            await text(
              FeedbackUiCopy.contentLabel('wish'),
              '$stage content field label',
              contrast: false,
            );
            await _checkFieldGeometry(
              tester,
              probe,
              find.text(FeedbackUiCopy.contentLabel('wish')).last,
              '$stage content label geometry',
            );
            await text(
              FeedbackUiCopy.categoryHelp('wish'),
              '$stage input helper',
            );
            await probe.capture('$stage-form');
          }

          await form('initial');
          final field = find.byKey(const ValueKey('feedback_submit_content'));
          final controller = tester.widget<TextField>(field).controller!;
          controller.text = 'Synthetic retained draft 原文';
          controller.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 7,
          );
          final value = controller.value;
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(
            tester.state(find.byType(FeedbackSubmitScreen)),
            same(submitState),
          );
          expect(controller.value, value);
          expect(gets, 1);
          expect(posts, isEmpty);
          await form('live');
          final submit = find.byKey(
            const ValueKey('feedback_submit_page_button'),
          );
          await tester.ensureVisible(submit);
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(posts, [
            {'category': 'wish', 'content': value.text},
          ]);
          expect(controller.value, value);
          expect(find.textContaining('PRIVATE'), findsNothing);
          await text(
            FeedbackUiCopy.formatError(
              const ApiException('503: PRIVATE synthetic diagnostic'),
            ),
            'submit API error',
          );
          await probe.capture('submit-error');
          await tester.ensureVisible(submit);
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(posts.length, 2);
          expect(posts.last, posts.first);
          expect(gets, 2);
          expect(find.byType(FeedbackSubmitScreen), findsNothing);
          expect(tester.state(find.byType(FeedbackScreen)), same(history));
          await probe.finish();
        });
      }
    }
  }
}
